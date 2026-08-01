import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../model/substate_artifact.dart';
import '../model/target_resolver.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Removes a substate or page: deletes its files and unwires it via AST — the
/// inverse of `add-substate` / `add-page`.
///
/// Destructive, so it previews the plan by default and only touches the disk
/// with `--apply`. The kind is auto-detected from what's wired (`AppState`
/// field vs `AppRouter` route); `--kind` forces it when a name matches both.
class RemoveCommand extends WritingCommand {
  @override
  String get name => 'remove';

  @override
  String get description =>
      'Remove a substate or page: delete its files and unwire it (AST).';

  @override
  String get invocation => 'frx remove <name> [--kind substate|page] --apply';

  @override
  List<String> get aliases => ['rm'];

  /// No `--dry-run`: a destructive command previews by *default* and writes on
  /// `--apply`, which is a difference in stance rather than in spelling.
  ///
  /// No `--force` either — not because it has none, but because the one it has
  /// is not the base's. Declared below, where its own meaning is.
  @override
  WriteFlags get flags => const WriteFlags(
    dryRun: false,
    force: false,
    diff: true,
    buildRunner: true,
  );

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: ['substate', 'page'],
        help:
            'Force the target kind (default: auto-detect from what is wired).',
      )
      // `--apply`, not `--force`: for the scaffolders `--force` means
      // "overwrite what is there", and spelling "actually do it" the same way
      // made `add-page --force` and `remove --force` opposites. `--force` stays
      // accepted so existing scripts keep working, but it is not the name — and
      // that is why it is declared here rather than taken from the base, whose
      // `--force` is the other meaning.
      ..addFlag(
        'apply',
        abbr: 'a',
        negatable: false,
        help:
            'Apply the removal (delete files + unwire). Without it the plan is '
            'only previewed.',
      )
      ..addFlag('force', abbr: 'f', negatable: false, hide: true);
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final name = requireName();

    // Locate each source independently and resolve the kind: removing a
    // substate shouldn't require a router (or vice versa), so a project missing
    // one file can still remove the other kind.
    final resolver = TargetResolver.locate(results['root'] as String?);
    final resolution = resolver.resolve(
      name,
      forced: results['kind'] as String?,
    );
    if (!resolution.ok) {
      // The resolver already decides which failure is the user's usage and
      // which is the project's shape; the two exit codes are its answer, and
      // this maps them to the two ways a command has of saying so.
      if (resolution.code == 64) usageException(resolution.error!);
      refuse(resolution.error!);
    }

    // Either spelling; `--force` is the retired one.
    final apply = (results['apply'] as bool) || (results['force'] as bool);
    return switch (resolution.kind!) {
      ArtifactKind.substate => _removeSubstate(
        name,
        resolver.appState ??
            refuse('Could not locate app_state.dart to remove a substate.'),
        repo,
        apply: apply,
      ),
      ArtifactKind.page => _removePage(
        name,
        resolver.routes ??
            refuse('Could not locate app_router.dart to remove a page.'),
        apply: apply,
      ),
    };
  }

  // --- substate --------------------------------------------------------------

  WritePlan _removeSubstate(
    Casing name,
    AppStateSource appState,
    FrxWorkspace repo, {
    required bool apply,
  }) {
    final a = SubstateArtifact(name);
    final substateDir = a.dir(appState.reduxDir);
    // Guard: only delete the folder if it really holds this substate's state
    // model, so a forced `--kind substate` can never nuke a sibling folder
    // (`common/`, `services/`) that happens to share the name.
    final canDeleteFolder = a.stateFile(appState.reduxDir).existsSync();

    final unwire = appState.unwireSubstate(
      field: a.field,
      importPath: a.stateImportPath,
    );
    final selectors = SelectorsSource.beside(appState.file);
    final selUnwire = selectors.exists
        ? selectors.unwire(
            field: a.field,
            pascal: name.pascal,
            snake: name.snake,
          )
        : null;

    // The persistor's change log, when the project kept it. Matched on either
    // half, so a line left labelled with the old name after a rename goes too.
    final store = StoreSource.of(repo);
    final storeUnwire = store.changed() == null
        ? null
        : store.unwire(field: a.field);

    final wiring = [
      Wiring.of(
        'AppState',
        appState.file,
        unwire,
        skipped: 'field "${a.field}" not present — nothing to unwire.',
        way: WiringWay.unwired,
      ),
      if (storeUnwire != null)
        Wiring.of(
          'Store',
          store.file,
          storeUnwire,
          skipped: 'change log does not list "${a.field}" — nothing to unwire.',
          way: WiringWay.unwired,
        ),
      if (selUnwire != null)
        Wiring.of(
          'Selectors',
          selectors.file,
          selUnwire,
          skipped: '${a.selectorType} absent — nothing to unwire.',
          way: WiringWay.unwired,
        ),
    ];

    return WritePlan(
      changes: Changeset([
        if (canDeleteFolder) DeleteDirectory(substateDir.path),
        ...wiring.edits,
      ]),
      header:
          'Remove substate "${name.pascal}"  '
          '(field: ${a.field}, type: ${a.stateType})',
      narrate: () {
        if (!canDeleteFolder) {
          console.out.writeln(
            '  • ${p.relative(substateDir.path)} — no ${name.snake}_state.dart, '
            'left in place',
          );
        }
        // One blank line before the blocks, because what precedes them is a
        // note about a file rather than nothing. The blocks space themselves.
        console.out.writeln();
        wiring.narrate();
      },
      previewOnly: !apply,
      previewNotice: 'Preview only — re-run with --apply to apply.',
      closing:
          '✓ Removed substate "${name.pascal}".\n'
          '  Note: code elsewhere that dispatched its actions or read its '
          'selectors now dangles — run `frx doctor` / `dart analyze`.',
      // A substate lives entirely in `business`, so its deleted files (and
      // their freezed parts) are in the same package build_runner writes to —
      // incremental build handles the deletion fine.
      build: (_) => BuildStep.build(
        FrxWorkspace.packageRootOf(appState.file.path),
        nextHint: 'regenerate AppState (its freezed part)',
        args: const ['--delete-conflicting-outputs'],
      ),
    );
  }

  // --- page ------------------------------------------------------------------

  WritePlan _removePage(
    Casing name,
    RoutesSource routes, {
    required bool apply,
  }) {
    final a = PageArtifact(name);
    final files = [
      a.pageFile(routes.pagesDir),
      a.connectorFile(routes.connectorsDir),
    ];

    final unwire = routes.unwirePage(
      routeType: a.routeType,
      connectorImport: a.connectorImport,
    );
    final wiring = [
      Wiring.of(
        'Router',
        routes.file,
        unwire,
        skipped: 'route ${a.routeType} not registered — nothing to unwire.',
        way: WiringWay.unwired,
      ),
    ];

    return WritePlan(
      changes: Changeset([
        for (final f in files)
          if (f.existsSync()) DeleteFile(f.path),
        ...wiring.edits,
      ]),
      header: 'Remove page "${name.pascal}"  (route: ${a.routeType})',
      narrate: () {
        for (final f in files) {
          if (!f.existsSync()) {
            console.out.writeln('  • ${p.relative(f.path)} — not found');
          }
        }
        console.out.writeln();
        wiring.narrate();
        for (final w in unwire.warnings) {
          console.err.writeln('⚠ $w');
        }
      },
      previewOnly: !apply,
      previewNotice: 'Preview only — re-run with --apply to apply.',
      closing: '✓ Removed page "${name.pascal}".',
      // The deleted page lives in `ui`, but build_runner runs in `app`; an
      // incremental build would try to delete the now-missing `ui` input from a
      // build that can't write to `ui` and crash. A `clean` first drops the
      // stale asset graph so the rebuild never references it.
      build: (_) => BuildStep(
        packageRoot: routes.appPackageRoot.path,
        commands: const [
          ['run', 'build_runner', 'clean'],
          ['run', 'build_runner', 'build'],
        ],
        nextHint: 'regenerate the router (drop the ${a.routeType} class)',
      ),
    );
  }
}
