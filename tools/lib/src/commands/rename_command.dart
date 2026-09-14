import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../ast/rename_edits.dart';
import '../engine/build_step.dart';
import '../model/page_artifact.dart';
import '../model/substate_artifact.dart';
import '../model/target_resolver.dart';
import '../redux/app_state_source.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'frx_command.dart';
import 'options.dart';
import 'rename/rename_execution.dart';
import 'rename/rename_plan.dart';

/// Renames a substate or page — files, classes, and every wiring reference.
///
/// The mechanics are textual but scoped: a fixed set of *identifier* renames
/// (`OldState` → `NewState`, `OldRoute` → `NewRoute`, the camel field, …) is
/// applied with word boundaries across the `business`/`app`/`ui` lib trees,
/// plus the snake path tokens in imports/parts. Distinctive identifiers make
/// this safe in practice; previews by default, applies with `--force`, and
/// `dart analyze` after is the definitive check.
///
/// The two kinds decide a [RenamePlan] each; carrying one out — the preview,
/// the pre-flight, the apply, the codegen — is `rename/rename_execution.dart`.
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

    // Collision guard: the new name must not already exist in that role.
    // Matches any field (not just `…State` ones) so renaming onto a framework
    // field like `wait` is refused too.
    if (kind == ArtifactKind.substate && appState != null) {
      final newField = SubstateArtifact(newName).field;
      if (appState.readSubstates().any((s) => s.field == newField)) {
        console.err.writeln(
          'AppState already has a field "${newName.camel}".',
        );
        return 70;
      }
    }
    if (kind == ArtifactKind.page && routes != null) {
      final newRoute = PageArtifact(newName).routeType;
      if (routes.readRoutes().any((r) => r.routeType == newRoute)) {
        console.err.writeln(
          'AppRouter already registers ${newName.pascal}Route.',
        );
        return 70;
      }
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
  ) {
    final oldA = PageArtifact(oldN);
    final newA = PageArtifact(newN);
    final moves = <Move>[
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

    return executeRename(
      RenamePlan(
        what: 'page "${oldN.pascal}" → "${newN.pascal}"',
        repoRoot: repoRoot,
        moves: moves,
        rename: rename,
        // The old ui page is deleted (moved) — the same reason `frx remove`
        // cleans first.
        build: BuildStep.cleanBuild(
          routes.appPackageRoot.path,
          nextHint: 'regenerate the router (rename the route class)',
        ),
      ),
      results,
      command: name,
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
    // whole segment moves too (models/old_state.dart,
    // actions/add_old_action.dart). Only the frx-generated basenames are
    // renamed — their classes are in the identifier sweep below, so file and
    // class stay in step. A hand-written `log_in_with_email_action.dart` keeps
    // its name (its class `LogInWithEmailAction` matches no pattern), staying
    // self-consistent.
    //
    // Generated files stay behind (deleted as stale below) — build_runner
    // regenerates them under the new name. One listing sorts the folder into
    // the two.
    final renamableBases = oldA.renamableBasenames(newA);
    final moves = <Move>[];
    final staleGenerated = <String>[];
    for (final f in oldDir.listSync(recursive: true).whereType<File>()) {
      if (FrxWorkspace.isGenerated(f.path)) {
        staleGenerated.add(f.path);
        continue;
      }
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

    return executeRename(
      RenamePlan(
        what: 'substate "${oldN.pascal}" → "${newN.pascal}"',
        repoRoot: repoRoot,
        moves: moves,
        rename: rename,
        emptiedDirs: [oldDir.path],
        build: BuildStep.build(
          FrxWorkspace.packageRootOf(appState.file.path),
          nextHint: 'regenerate the freezed part for the renamed state',
        ),
        // Generated files left in the old folder (freezed parts, …) would
        // linger beside nothing — drop them; build_runner remakes the new
        // ones.
        staleGenerated: staleGenerated,
        // The one string neither the token walk nor a path rule can reach: the
        // change log's label names the substate the line beside it tests.
        afterEdits: (path, content) => StoreSource.owns(path, root: repoRoot)
            ? StoreSource.relabel(content, was: oldA.field, field: newA.field)
            : content,
      ),
      results,
      command: name,
    );
  }
}
