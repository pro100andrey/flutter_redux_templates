import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../audit/checks.dart';
import '../audit/finding.dart';
import '../engine/changeset.dart';
import '../flow/flow_docs.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../util/console.dart';
import '../skills/skill_gen.dart';
import '../workspace/frx_workspace.dart';
import 'options.dart';
import 'wiring.dart';

/// Audits the project for common drift: substates not wired into `AppState`,
/// missing freezed/auto_route parts (build_runner not run), and route ↔
/// connector mismatches — plus **placement**: code that is fully wired,
/// compiles, and sits in the wrong place. Read-only by default; `--fix` repairs
/// the findings that carry a [Fix]. Exits 1 when errors remain, which no
/// placement finding ever is.
///
/// What to check lives in [auditChecks]; this command decides how to say it and
/// how to repair it.
class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser
      ..addFlag(
        'fix',
        negatable: false,
        help:
            'Repair auto-fixable findings: run build_runner for missing '
            'parts, remove orphan substate folders, regenerate docs/flows and '
            'rewrite .claude/skills. It applies without a preview — '
            '`frx update-skills --dry-run --diff` is the one that shows the '
            'skill changes first.'
            'and remove orphan substate folders.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit findings as JSON '
            '({findings:[{severity,message,file,fix,rule}]}) instead of the '
            'report. Read-only (ignores --fix).',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Audit the project for wiring drift, ungenerated code and misplaced '
      'declarations.';

  @override
  List<String> get aliases => ['dr'];

  @override
  Future<int> run() async {
    final root = argResults?['root'] as String?;
    final fix = argResults?['fix'] as bool? ?? false;
    final json = argResults?['json'] as bool? ?? false;
    final repo = FrxWorkspace.locate(startDir: root);

    // Process-state observations are for a human reading the report; the
    // editor re-audits on file events and would keep a stale one on screen.
    var findings = audit(repo, processState: !json);

    // Machine-readable mode is read-only (the VSCode Problems integration reads
    // it); emit and exit before any report or repair.
    if (json) {
      console.out.writeln(
        jsonEncode({
          'findings': [for (final f in findings) f.toJson()],
        }),
      );
      return _exitCode(findings);
    }

    _report(repo, findings);

    if (findings.isEmpty || !fix) return _exitCode(findings);

    final fixes = findings.map((f) => f.fix).nonNulls.toList();
    if (fixes.isEmpty) {
      console.out
        ..writeln()
        ..writeln('Nothing here is auto-fixable — resolve manually.');
      return _exitCode(findings);
    }

    console.out
      ..writeln()
      ..writeln('--fix: applying ${fixes.length} remediation(s)…');

    // Sorted into remedy groups by one exhaustive switch. Exhaustive is the
    // point: a fourth [Fix] stops compiling here, rather than being counted
    // among the remediations above and then silently never applied.
    final buildRunner = <String>{};
    final orphans = <String>{};
    var flowDocs = false;
    var skills = false;
    for (final fix in fixes) {
      switch (fix) {
        case BuildRunnerFix(:final package):
          buildRunner.add(package);
        case OrphanFix(:final folder):
          orphans.add(folder);
        case FlowDocsFix():
          flowDocs = true;
        case SkillsFix():
          skills = true;
      }
    }

    // The order between groups is load-bearing, so it is spelled out rather
    // than left to the order findings happen to arrive in.
    //
    // Regenerate missing parts first, once per affected package — while every
    // source still exists. Removing an orphan first would delete a `business`
    // source that a dependent package's (`app`) build_runner tracks, and an
    // incremental build can't drop a deleted input from a package it doesn't
    // write to (it throws InvalidOutputException).
    for (final pkg in buildRunner) {
      final code = await _runBuildRunner(repo, pkg);
      if (code != 0) {
        console.err.writeln('⚠ build_runner failed in $pkg (exit $code).');
      }
    }

    // Then remove orphan folders (dead code not wired into AppState). Nothing is
    // regenerated afterwards: an orphan isn't in AppState, so deleting it leaves
    // no generated part stale.
    for (final folder in orphans) {
      await _removeOrphan(repo, folder);
    }

    // Last: the docs describe the code, so regenerate them only once the code
    // has stopped moving — an orphan removed above must not survive in a flow.
    if (flowDocs) _regenerateFlowDocs(repo);

    // Last, and independent of everything above: the skills are a function of
    // the CLI, not of the tree, so nothing another remedy does can change what
    // they should say.
    if (skills) await _regenerateSkills(repo);

    console.out
      ..writeln()
      ..writeln('Re-checking…')
      ..writeln();
    findings = audit(repo, processState: true);
    _report(repo, findings);
    return _exitCode(findings);
  }

  void _report(FrxWorkspace repo, List<Finding> findings) {
    console.out
      ..writeln('frx doctor  (${repo.root.path})')
      ..writeln();
    if (findings.isEmpty) {
      console.out.writeln('✓ No issues found.');
      return;
    }
    final errors = findings.where((f) => f.severity == Severity.error).length;
    for (final f in findings) {
      console.out.writeln(
        '  ${f.severity == Severity.error ? '✗' : '⚠'} ${f.message}',
      );
    }
    console.out
      ..writeln()
      ..writeln('${findings.length} issue(s) — $errors error(s).');
  }

  int _exitCode(List<Finding> findings) =>
      findings.any((f) => f.severity == Severity.error) ? 1 : 0;

  // --- fixers ----------------------------------------------------------------

  /// Deletes an orphan substate folder and unwires its selectors. The folder
  /// isn't in `AppState` (that's what makes it an orphan), so this reuses the
  /// same engine `frx remove` does, minus any `app_state.dart` edit.
  Future<void> _removeOrphan(FrxWorkspace repo, String folder) async {
    final AppStateSource appState;
    try {
      appState = AppStateSource.of(repo);
    } on StateError {
      return;
    }
    // Use the raw folder name the audit reported for the path (it's the actual
    // basename on disk); derive the casings only for the selectors edit.
    final artifact = SubstateArtifact.parse(folder);
    final dir = Directory(p.join(appState.reduxDir.path, folder));
    final selectors = SelectorsSource.beside(appState.file);

    final unwire = selectors.exists
        ? selectors.unwire(
            field: artifact.field,
            pascal: artifact.name.pascal,
            snake: artifact.name.snake,
          )
        : null;

    // Through [apply], not a bare `Process.run('dart', ['format', …])`: that
    // hand-rolled copy dropped the `.dart` filter and the failure warning
    // [formatFiles] exists to carry, and skipped the docs refresh a removed
    // substate can invalidate.
    //
    // [apply] and not the writing-command tail either, and deliberately: the
    // audit is not a writing command. It reports, and repairs only when asked;
    // it has no plan to print, no overwrite guard, no `--diff`, and its own exit
    // codes. What it wants is exactly the engine — the journal that makes a
    // failed repair leave the tree as it was, the formatting, the docs refresh —
    // and that is what [apply] is. What it was *also* doing by hand is the
    // change construction, which is [OutcomeAsChange].
    await apply(
      Changeset([
        if (dir.existsSync()) DeleteDirectory(dir.path),
        ?unwire?.editTo(selectors.file),
      ]),
      format: true,
      repoRoot: repo.root,
    );
    console.out.writeln('  ✓ removed orphan redux/$folder${p.separator}');
  }

  /// The same changeset `frx update-skills` previews, applied.
  Future<void> _regenerateSkills(FrxWorkspace repo) async {
    final changes = SkillGen.changesIn(repo.root);
    if (changes.isEmpty) return;
    final applied = await apply(Changeset(changes), format: false);
    console.out.writeln(
      '  ✓ ${applied.written.length} skill file(s) written'
      '${applied.removed.isEmpty ? '' : ', ${applied.removed.length} removed'}.',
    );
  }

  /// Rewrites `docs/flows/` from the current sources.
  void _regenerateFlowDocs(FrxWorkspace repo) {
    for (final change in FlowDocs(repo).write()) {
      console.out.writeln(
        '  ✓ ${change.kind == DocDriftKind.orphan ? 'removed' : 'wrote'} '
        '${change.relative}',
      );
    }
  }

  Future<int> _runBuildRunner(FrxWorkspace repo, String pkg) async {
    console.out.writeln('  build_runner build  ($pkg) …');
    final proc = await Process.start(
      'dart',
      const ['run', 'build_runner', 'build'],
      workingDirectory: p.join(repo.root.path, pkg),
      mode: ProcessStartMode.inheritStdio,
    );
    return proc.exitCode;
  }
}
