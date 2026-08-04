import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../model/removable_artifact.dart';
import '../model/substate_artifact.dart';
import '../model/target_resolver.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../engine/write_path.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Removes an artifact: deletes its files and unwires whatever registered it —
/// the inverse of the `add-*` command that made it.
///
/// Destructive, so it previews the plan by default and only touches the disk
/// with `--apply`.
///
/// Two kinds of target, resolved differently on purpose. A substate and a page
/// are *wired*: they are found by what the project declares (an `AppState`
/// field, an `AppRouter` route) and removing one is mostly an unwiring job. The
/// rest — action, model, widget, connector, service — are file sets in known
/// places whose `add-*` wired nothing central, so they are found on disk and
/// removing one is about deleting the whole set: a widget's preview in the
/// mirror tree, a service's dispatcher beside it, a model's `.freezed.dart`.
///
/// That set is the reason this command grew. Across six traced builds the agent
/// reached for raw `rm` sixty-odd times — for actions, models and connectors it
/// could not ask `remove` for — and `rm` deletes the file it was given and
/// leaves the rest of the set behind.
class RemoveCommand extends WritingCommand {
  @override
  String get name => 'remove';

  @override
  String get description =>
      'Remove an artifact: delete its files and unwire it (AST).';

  @override
  String get invocation => 'frx remove <name> [--kind <kind>] --apply';

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
        allowed: [
          'substate',
          'page',
          for (final k in RemovableKind.values) k.flag,
        ],
        help: 'Force the target kind (default: auto-detect).',
      )
      // Only `action` can legitimately exist twice under one name, because the
      // substate folder is part of its address. Every other kind lives in one
      // directory, so a duplicate there is a naming collision to fix rather
      // than a target to disambiguate.
      ..addOption(
        'state',
        abbr: 's',
        help:
            'For --kind action: the substate that owns it, when the name is '
            'used under more than one.',
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
    final forced = results['kind'] as String?;
    final state = results['state'] as String?;
    final apply = applying(results);

    final onDisk = RemovableResolver(repo);
    final fileKinds = {for (final k in RemovableKind.values) k.flag: k};

    // Forced to a file kind: there is no wiring to consult, so the wiring
    // sources are never located — a project missing `app_router.dart` can still
    // delete a model.
    if (forced != null && fileKinds.containsKey(forced)) {
      final kind = fileKinds[forced]!;
      final found = onDisk.resolve(kind, name, state: state);
      if (found == null) {
        if (onDisk.blocked != null) usageException(onDisk.blocked!);
        refuse(_notFound(kind, name, state));
      }
      return _removeFiles(found, apply: apply);
    }

    // Locate each source independently and resolve the kind: removing a
    // substate shouldn't require a router (or vice versa), so a project missing
    // one file can still remove the other kind.
    final resolver = TargetResolver.locate(results['root'] as String?);

    // Auto-detection has to see both worlds. Without this, `remove ArchiveTask`
    // reports "nothing named that is wired" for an action the project plainly
    // has, and the reflex it teaches is `rm` — which is the habit this command
    // grew to replace.
    if (forced == null) {
      final wired = [
        if (resolver.isSubstate(name)) 'substate',
        if (resolver.isPage(name)) 'page',
      ];
      final matched = <RemovableArtifact>[];
      for (final kind in RemovableKind.values) {
        final found = onDisk.resolve(kind, name, state: state);
        if (found != null) matched.add(found);
        // An ambiguity inside one kind is still an ambiguity; surfacing it here
        // beats reporting "nothing found" for a name that matched twice.
        if (onDisk.blocked != null) usageException(onDisk.blocked!);
      }

      final kinds = [...wired, ...matched.map((a) => a.kind.flag)];
      if (kinds.length > 1) {
        usageException(
          '"${name.pascal}" matches ${kinds.length} kinds (${kinds.join(', ')}). '
          'Disambiguate with --kind ${kinds.join('|')}.',
        );
      }
      if (matched.length == 1)
        return _removeFiles(matched.single, apply: apply);
    }

    final resolution = resolver.resolve(name, forced: forced);
    if (!resolution.ok) {
      // The resolver already decides which failure is the user's usage and
      // which is the project's shape; the two exit codes are its answer, and
      // this maps them to the two ways a command has of saying so.
      if (resolution.code == 64) usageException(resolution.error!);
      refuse(resolution.error!);
    }

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

  // --- file artifacts --------------------------------------------------------

  /// The plan for a kind that wired nothing central: delete the set, name what
  /// the set did not include, and say what stops compiling.
  WritePlan _removeFiles(RemovableArtifact a, {required bool apply}) {
    return WritePlan(
      changes: Changeset([
        for (final f in a.files) DeleteFile(f),
        for (final d in a.directories) DeleteDirectory(d),
      ]),
      header: a.header,
      narrate: () {
        for (final m in a.missing) {
          console.out.writeln('  • ${p.relative(m)} — not found');
        }
        if (a.missing.isNotEmpty) console.out.writeln();
      },
      previewOnly: !apply,
      previewNotice: kPreviewNotice,
      closing: [
        '✓ Removed ${a.kind.flag} "${a.name.pascal}".',
        if (a.dangles != null) '  Note: ${a.dangles}.',
      ].join('\n'),
    );
  }

  /// The "nothing of this kind here" message, told in terms of where it looked.
  /// A bare "not found" leaves the user unable to tell a typo from a wrong
  /// `--kind`, which is the mistake this command's kind list makes easy.
  String _notFound(RemovableKind kind, Casing name, String? state) =>
      switch (kind) {
        RemovableKind.action =>
          'No action "${name.pascal}" under '
              '${state == null ? 'any substate' : 'substate "$state"'} '
              '(looked for ${name.snake}_action.dart in redux/*/actions/).',
        RemovableKind.model =>
          'No model or enum "${name.pascal}" — models/lib/${name.snake}.dart '
              'does not exist.',
        RemovableKind.widget =>
          'No widget "${name.pascal}" — no ${name.snake}.dart in any ui/lib '
              'widget folder.',
        RemovableKind.connector =>
          'No connector "${name.pascal}" — '
              'app/lib/connectors/${name.snake}_connector.dart does not exist.',
        RemovableKind.service =>
          'No service "${name.pascal}" — '
              'business/lib/redux/services/${name.snake}/ does not exist.',
      };

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
      previewNotice: kPreviewNotice,
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
      previewNotice: kPreviewNotice,
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
