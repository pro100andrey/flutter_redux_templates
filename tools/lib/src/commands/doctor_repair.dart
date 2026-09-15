import 'dart:io';

import 'package:path/path.dart' as p;

import '../audit/finding.dart';
import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../flow/flow_docs.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../refusal.dart';
import '../skills/skill_gen.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';

/// `frx doctor --fix`: the remediations the audit's findings carry, applied in
/// the one order that is safe.
///
/// What to check lives in the audit; how to say it lives in the command; this
/// is how to repair it.
Future<void> repair(FrxWorkspace repo, List<Fix> fixes) async {
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

  // Then remove orphan folders (dead code not wired into AppState). Nothing
  // is regenerated afterwards: an orphan isn't in AppState, so deleting it
  // leaves no generated part stale.
  for (final folder in orphans) {
    await _removeOrphan(repo, folder);
  }

  // Last: the docs describe the code, so regenerate them only once the code
  // has stopped moving — an orphan removed above must not survive in a flow.
  if (flowDocs) {
    _regenerateFlowDocs(repo);
  }

  // Last, and independent of everything above: the skills are a function of
  // the CLI, not of the tree, so nothing another remedy does can change what
  // they should say.
  if (skills) {
    await _regenerateSkills(repo);
  }
}

/// Deletes an orphan substate folder and unwires its selectors. The folder
/// isn't in `AppState` (that's what makes it an orphan), so this reuses the
/// same engine `frx remove` does, minus any `app_state.dart` edit.
Future<void> _removeOrphan(FrxWorkspace repo, String folder) async {
  final AppStateSource appState;
  try {
    appState = AppStateSource.of(repo);
  } on FrxRefusal {
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
  // it has no plan to print, no overwrite guard, no `--diff`, and its own
  // exit codes. What it wants is exactly the engine — the journal that makes
  // a failed repair leave the tree as it was, the formatting, the docs
  // refresh — and that is what [apply] is. What it was *also* doing by hand
  // is the change construction, which is [OutcomeAsChange].
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
  final changes = SkillGen().changesIn(repo);
  if (changes.isEmpty) {
    return;
  }
  final applied = await apply(Changeset(changes), format: false);
  final removed = applied.removed.isEmpty
      ? ''
      : ', ${applied.removed.length} removed';
  console.out.writeln(
    '  ✓ ${applied.written.length} skill file(s) written$removed.',
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

Future<int> _runBuildRunner(FrxWorkspace repo, String pkg) {
  console.out.writeln('  build_runner build  ($pkg) …');
  return streamProcess(
    'dart',
    const ['run', 'build_runner', 'build'],
    p.join(repo.root.path, pkg),
  );
}
