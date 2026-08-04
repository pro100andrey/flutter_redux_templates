import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../ast/rename_edits.dart';
import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../engine/diff.dart';
import '../engine/write_path.dart';
import '../engine/write_report.dart';
import '../model/page_artifact.dart';
import '../model/substate_artifact.dart';
import '../model/target_resolver.dart';
import '../redux/app_state_source.dart';
import '../redux/ast_edit.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'frx_command.dart';
import 'options.dart';

/// A planned file move.
typedef _Move = ({String from, String to});

/// Renames a substate or page — files, classes, and every wiring reference.
///
/// The mechanics are textual but scoped: a fixed set of *identifier* renames
/// (`OldState` → `NewState`, `OldRoute` → `NewRoute`, the camel field, …) is
/// applied with word boundaries across the `business`/`app`/`ui` lib trees,
/// plus the snake path tokens in imports/parts. Distinctive identifiers make
/// this safe in practice; previews by default, applies with `--force`, and
/// `dart analyze` after is the definitive check.
class RenameCommand extends Command<int> with NameArg {
  RenameCommand() {
    argParser
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: ['substate', 'page'],
        help:
            'Force the target kind (default: auto-detect from what is wired).',
      )
      // `--apply`, not `--force`: `--force` means "overwrite" for every
      // scaffolder, and reusing it for "actually do it" made `add-page --force`
      // and `rename --force` opposites. `--force` stays accepted, unadvertised,
      // so existing scripts keep working.
      ..addFlag(
        'apply',
        abbr: 'a',
        negatable: false,
        help:
            'Apply the rename (move files + rewrite references). Without it '
            'the plan is only previewed.',
      )
      ..addFlag('force', abbr: 'f', negatable: false, hide: true)
      ..addFlag(
        'build-runner',
        abbr: 'b',
        negatable: false,
        help: 'Run build_runner in the affected package after renaming.',
      )
      ..addFlag(
        'diff',
        negatable: false,
        help: 'Also print a unified diff of the reference rewrites.',
      )
      ..addFlag(
        'format',
        defaultsTo: true,
        help: 'Run `dart format` on the edited files.',
      )
      ..addFlag('json', negatable: false, help: kMachineHelp)
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'rename';

  @override
  String get description =>
      'Rename a substate or page — files, classes, and all wiring references.';

  @override
  String get invocation =>
      'frx rename <old> <new> [--kind substate|page] --apply';

  @override
  List<String> get aliases => ['mv'];

  @override
  List<String> get positionals => const ['old', 'new'];

  @override
  Future<int> run() async {
    final results = argResults!;
    final oldName = requireCasing(0);
    final newName = requireCasing(1);
    if (oldName.snake == newName.snake) {
      usageException('Old and new names are the same.');
    }

    final resolver = TargetResolver.locate(results['root'] as String?);
    final resolution = resolver.resolve(
      oldName,
      forced: results['kind'] as String?,
    );
    if (!resolution.ok) {
      console.err.writeln(resolution.error);
      return resolution.code;
    }
    final appState = resolver.appState;
    final routes = resolver.routes;
    final kind = resolution.kind!;

    // Collision guard: the new name must not already exist in that role. Matches
    // any field (not just `…State` ones) so renaming onto a framework field
    // like `wait` is refused too.
    if (kind == ArtifactKind.substate &&
        appState != null &&
        appState.readSubstates().any(
          (s) => s.field == SubstateArtifact(newName).field,
        )) {
      console.err.writeln('AppState already has a field "${newName.camel}".');
      return 70;
    }
    if (kind == ArtifactKind.page &&
        routes != null &&
        routes.readRoutes().any(
          (r) => r.routeType == PageArtifact(newName).routeType,
        )) {
      console.err.writeln(
        'AppRouter already registers ${newName.pascal}Route.',
      );
      return 70;
    }

    final repoRoot = (routes?.repoRoot ?? appState!.repoRoot).path;
    return kind == ArtifactKind.substate
        ? _renameSubstate(oldName, newName, appState!, repoRoot, results)
        : _renamePage(oldName, newName, routes!, repoRoot, results);
  }

  // --- page ------------------------------------------------------------------

  Future<int> _renamePage(
    Casing oldN,
    Casing newN,
    RoutesSource routes,
    String repoRoot,
    ArgResults results,
  ) async {
    final oldA = PageArtifact(oldN);
    final newA = PageArtifact(newN);
    final moves = <_Move>[
      (
        from: oldA.pageFile(routes.pagesDir).path,
        to: newA.pageFile(routes.pagesDir).path,
      ),
      (
        from: oldA.connectorFile(routes.connectorsDir).path,
        to: newA.connectorFile(routes.connectorsDir).path,
      ),
    ];

    final rename = RenameEdits(
      identifiers: {
        oldA.connectorClass: newA.connectorClass,
        oldA.pageClass: newA.pageClass,
        oldA.routeType: newA.routeType,
      },
      // The two files that moved, by basename.
      paths: {
        '${oldN.snake}_page_connector': '${newN.snake}_page_connector',
        '${oldN.snake}_page': '${newN.snake}_page',
      },
      // The two strings a page rename owns: the route path auto_route derives
      // from the page name (a custom one does not match and is kept), and the
      // placeholder the page scaffold writes.
      literals: {
        oldA.defaultPath: newA.defaultPath,
        oldA.pageClass: newA.pageClass,
      },
    );

    return _execute(
      results,
      what: 'page "${oldN.pascal}" → "${newN.pascal}"',
      repoRoot: repoRoot,
      moves: moves,
      rename: rename,
      // The old ui page is deleted (moved); an incremental app build can't
      // drop a removed input of another package — clean first (same reason as
      // `frx remove`).
      buildPackageRoot: routes.appPackageRoot.path,
      buildCommands: const [
        ['run', 'build_runner', 'clean'],
        ['run', 'build_runner', 'build'],
      ],
      staleGenerated: const [],
      nextHint: 'regenerate the router (rename the route class)',
    );
  }

  // --- substate --------------------------------------------------------------

  Future<int> _renameSubstate(
    Casing oldN,
    Casing newN,
    AppStateSource appState,
    String repoRoot,
    ArgResults results,
  ) async {
    final oldA = SubstateArtifact(oldN);
    final newA = SubstateArtifact(newN);
    final oldDir = oldA.dir(appState.reduxDir);
    final newDir = newA.dir(appState.reduxDir).path;
    if (!oldDir.existsSync()) {
      console.err.writeln('${p.relative(oldDir.path)} does not exist.');
      return 70;
    }
    if (Directory(newDir).existsSync()) {
      console.err.writeln('${p.relative(newDir)} already exists.');
      return 70;
    }

    // Every file inside the folder whose *name* carries the old snake as a
    // whole segment moves too (models/old_state.dart, actions/add_old_action.dart).
    // Only the frx-generated basenames are renamed — their classes are in the
    // identifier sweep below, so file and class stay in step. A hand-written
    // `log_in_with_email_action.dart` keeps its name (its class
    // `LogInWithEmailAction` matches no pattern), staying self-consistent.
    final renamableBases = oldA.renamableBasenames(newA);
    final moves = <_Move>[];
    for (final f in oldDir.listSync(recursive: true).whereType<File>()) {
      // Generated files stay behind (deleted as stale below) — build_runner
      // regenerates them under the new name.
      if (FrxWorkspace.isGenerated(f.path)) continue;
      final rel = p.relative(f.path, from: oldDir.path);
      final base = p.basename(rel);
      moves.add((
        from: f.path,
        to: p.join(newDir, p.dirname(rel), renamableBases[base] ?? base),
      ));
    }

    final rename = RenameEdits(
      identifiers: {
        // `<Pascal>Action` covers the convention of a domain action named after
        // its substate (forgot_password_action.dart → ForgotPasswordAction);
        // Add/Retrieve are the table-kind pair.
        oldA.stateType: newA.stateType,
        oldA.waitingEnum: newA.waitingEnum,
        oldA.selectorType: newA.selectorType,
        oldA.actionClass: newA.actionClass,
        oldA.addActionClass: newA.addActionClass,
        oldA.retrieveActionClass: newA.retrieveActionClass,
        // The camel field and facade getter (`state.copyWith.old(…)`,
        // `old.query`). A common word, and the old sweep kept it out of `ui`
        // wholesale because its hits there are l10n keys — the token walk skips
        // `current.<name>` exactly instead, so a connector holding one is safe
        // too and the package exclusion is not needed.
        oldN.camel: newN.camel,
      },
      paths: {
        // The folder the substate lives in, and every moved file whose *name*
        // changed — imports naming either must follow.
        oldN.snake: newN.snake,
        for (final m in moves)
          if (p.basename(m.from) != p.basename(m.to))
            p.basenameWithoutExtension(m.from): p.basenameWithoutExtension(
              m.to,
            ),
      },
    );

    return _execute(
      results,
      what: 'substate "${oldN.pascal}" → "${newN.pascal}"',
      repoRoot: repoRoot,
      moves: moves,
      rename: rename,
      emptiedDirs: [oldDir.path],
      buildPackageRoot: FrxWorkspace.packageRootOf(appState.file.path),
      buildCommands: const [
        ['run', 'build_runner', 'build'],
      ],
      // Generated files left in the old folder (freezed parts, …) would
      // linger beside nothing — drop them; build_runner remakes the new ones.
      staleGenerated: [
        for (final f in oldDir.listSync(recursive: true).whereType<File>())
          if (FrxWorkspace.isGenerated(f.path)) f.path,
      ],
      // The one string neither the token walk nor a path rule can reach: the
      // change log's label names the substate the line beside it tests.
      afterEdits: (path, content) => StoreSource.owns(path, root: repoRoot)
          ? StoreSource.relabel(content, was: oldA.field, field: newA.field)
          : content,
      nextHint: 'regenerate the freezed part for the renamed state',
    );
  }

  // --- shared execution ------------------------------------------------------

  /// Previews (or with `--apply` applies) [moves] plus [rename] applied to
  /// every non-generated `.dart` under the `business`/`app`/`ui` lib trees.
  Future<int> _execute(
    ArgResults results, {
    required String what,
    required String repoRoot,
    required List<_Move> moves,
    required RenameEdits rename,
    required String buildPackageRoot,
    required List<List<String>> buildCommands,
    required List<String> staleGenerated,
    required String nextHint,
    List<String> emptiedDirs = const [],
    String Function(String path, String content)? afterEdits,
  }) async {
    // Either spelling; `--force` is the retired one. Named `applying` because
    // `apply` is the changeset applier this ends up calling.
    final applying = (results['apply'] as bool) || (results['force'] as bool);
    final asJson = machineMode(results);

    if (!asJson) {
      console.out
        ..writeln('Rename $what')
        ..writeln();
    }

    // Which files change, and how many edits in each. Off the parse tree —
    // see [RenameEdits] for what that replaced and why.
    final edits = <String, ({String content, int count})>{};
    for (final dir in ['business', 'app', 'ui']) {
      final lib = Directory(p.join(repoRoot, dir, 'lib'));
      if (!lib.existsSync()) continue;
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || FrxWorkspace.isGenerated(f.path)) {
          continue;
        }
        final original = f.readAsStringSync();
        final planned = rename.of(
          parseString(content: original, throwIfDiagnostics: false).unit,
        );
        var content = applyEdits(original, planned);
        var count = planned.length;
        // What neither the tree nor a textual sweep can do, done by something
        // that knows what the text is *for*. A string literal must survive a
        // rename — a persistence key does — and the persistor's change log is a
        // string that *names a substate*, so the general rule is right and wrong
        // at the same time.
        if (afterEdits != null) {
          final fixed = afterEdits(f.path, content);
          if (fixed != content) {
            content = fixed;
            count++;
          }
        }
        if (content != original) {
          edits[f.path] = (content: content, count: count);
        }
      }
    }

    // Content edits are declared before the moves so they land while the paths
    // are still the old ones; [apply] preserves that order (and runs the
    // deletes first, which is harmless here — a stale generated file is never
    // also an edit target).
    //
    // Built here rather than after the preview gate, because the machine format
    // is one shape in two states and the planned state needs the same value the
    // applied one does.
    final plan = Changeset([
      for (final e in edits.entries)
        EditFile(
          e.key,
          before: File(e.key).readAsStringSync(),
          after: e.value.content,
        ),
      for (final m in moves) MoveFile(from: m.from, path: m.to),
      // Only the ones that are really there: a plan that lists a delete which
      // cannot happen describes something other than what it will do.
      for (final g in staleGenerated.where((g) => File(g).existsSync()))
        DeleteFile(g),
    ]);
    final report = asJson
        ? WriteReport.of(plan, command: name, relativeTo: repoRoot)
        : null;
    final step = BuildStep(
      packageRoot: buildPackageRoot,
      commands: buildCommands,
      nextHint: nextHint,
    );

    if (!asJson) {
      console.out.writeln('Files:');
      for (final m in moves) {
        console.out.writeln(
          '  move  ${p.relative(m.from)} → ${p.relative(m.to)}',
        );
      }
      for (final g in staleGenerated.where((g) => File(g).existsSync())) {
        console.out.writeln('  delete  ${p.relative(g)} (stale generated)');
      }
      console.out
        ..writeln()
        ..writeln('References (${edits.length} file(s)):');
      for (final e in edits.entries) {
        console.out.writeln('  ~ ${p.relative(e.key)}  (${e.value.count})');
      }
      console.out.writeln();

      if (results['diff'] as bool) {
        // The files still hold their old content (edits aren't applied yet).
        for (final e in edits.entries) {
          console.out.write(
            unifiedDiff(
              File(e.key).readAsStringSync(),
              e.value.content,
              path: p.relative(e.key),
            ),
          );
        }
        console.out.writeln();
      }
    }

    if (!applying) {
      console.out.writeln(
        report?.render(applied: false, build: plannedBuild(step)) ??
            'Preview only — re-run with --apply to apply.',
      );
      return 0;
    }

    // Pre-flight before touching anything: every source must exist and no
    // destination may — renameSync would otherwise silently overwrite an
    // unwired file at the target path, or throw mid-apply after the reference
    // edits were already written.
    for (final m in moves) {
      if (!File(m.from).existsSync()) {
        console.err.writeln(
          '✗ ${p.relative(m.from)} does not exist — aborting.',
        );
        return 70;
      }
      if (File(m.to).existsSync()) {
        console.err.writeln(
          '✗ ${p.relative(m.to)} already exists — aborting (move it away or '
          'remove it first).',
        );
        return 70;
      }
    }

    await apply(
      plan,
      format: results['format'] as bool,
      repoRoot: Directory(repoRoot),
    );

    // Pruning an emptied directory stays here: whether a folder left behind by
    // a move is *meaningfully* empty is rename's question, not one a generic
    // applier can answer.
    for (final d in emptiedDirs) {
      final dir = Directory(d);
      if (dir.existsSync() &&
          dir.listSync(recursive: true).whereType<File>().isEmpty) {
        dir.deleteSync(recursive: true);
      }
    }

    // A renamed import token can fall out of alphabetical order — re-sort the
    // directives in every package the sweep touched (scoped to that one lint).
    final touchedPackages = {
      for (final f in [...edits.keys, ...moves.map((m) => m.to)])
        p.join(repoRoot, p.split(p.relative(f, from: repoRoot)).first),
    };
    for (final pkg in touchedPackages) {
      await Process.run('dart', [
        'fix',
        '--apply',
        '--code=directives_ordering',
      ], workingDirectory: pkg);
    }

    if (!asJson) {
      console.out.writeln(
        '✓ Renamed. Run `dart analyze` to confirm nothing dangles.',
      );
    }

    final built = await runBuild(
      step,
      enabled: results['build-runner'] as bool,
      report: !asJson,
    );
    if (report != null) {
      console.out.writeln(
        report.render(applied: true, build: appliedBuild(step, built)),
      );
    }
    return built.code;
  }
}
