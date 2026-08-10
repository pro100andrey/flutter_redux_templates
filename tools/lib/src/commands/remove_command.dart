import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../model/removable_artifact.dart';
import '../model/substate_artifact.dart';
import '../model/target_resolver.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../redux/state_source.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../scaffold/type_imports.dart';
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
          'field',
          for (final k in RemovableKind.values) k.flag,
        ],
        help: 'Force the target kind (default: auto-detect).',
      )
      // Only `action` and `field` can legitimately exist twice under one name,
      // because the substate folder is part of their address — and a field
      // named `value` is in every slice `add-substate` made with its default
      // kind. Every other kind lives in one directory, so a duplicate there is
      // a naming collision to fix rather than a target to disambiguate.
      ..addOption(
        'state',
        abbr: 's',
        help:
            'For --kind action / field: the substate that owns it, when the '
            'name is used under more than one.',
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

    // A field is addressed by its substate and its name, never by a class, so
    // it is asked for rather than detected — see [_removeField]. Answered
    // before the wiring sources are located, because a field lives entirely in
    // `business`: a project with no router can still lose one.
    if (forced == 'field') {
      return _removeField(name, repo, state: state, apply: apply);
    }

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

      // A field is not *resolved* by auto-detection — it is asked for, see
      // [_removeField] — but it does count as a collision. Without this,
      // `add-field log_in tags:String?` plus a `Tags` model made `remove tags
      // --apply` delete the model and never mention the field: an ambiguity
      // resolved by a rule, which this command's own doctrine says is still an
      // ambiguity and under `--apply` is unrecoverable.
      final kinds = [
        ...wired,
        if (_substatesWithField(repo, name.camel).isNotEmpty) 'field',
        ...matched.map((a) => a.kind.flag),
      ];
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
      // Before refusing, ask the one kind auto-detection does not reach. "Not a
      // wired substate or page" is a true sentence about a name that is plainly
      // *there* as a field, and the reflex it teaches is the hand edit the
      // guard refuses — after which there is nothing left to try.
      final owners = _substatesWithField(repo, name.camel);
      if (owners.isNotEmpty) {
        refuse(
          '${resolution.error!}\n'
          '  "${name.camel}" is a field of '
          '${owners.length == 1 ? 'substate "${owners.single.snake}"' : 'substates ${owners.map((o) => o.snake).join(', ')}'} '
          '— remove it with `frx remove ${name.camel} --kind field'
          '${owners.length == 1 ? '' : ' --state <substate>'}`.',
        );
      }
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
        '✓ Removed ${a.kind.flag} "${a.className}".',
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

  // --- field -----------------------------------------------------------------

  /// The plan for one field of one substate: the factory parameter, the getter
  /// on the facade and the setter action that copies it — the inverse of
  /// `add-field`.
  ///
  /// **Why `remove` grew a kind that is not an artifact.** A field was the one
  /// thing this architecture could add and not take away. `add-field` puts one
  /// in, `add-substate` puts a `value` in every slice made with the default
  /// kind, and the way out was a hand edit to `<slice>_state.dart` — which the
  /// guard refuses, correctly, because a field there carries wiring. So a
  /// scaffolded field stayed: `remove --kind action` deletes its setter and
  /// leaves the field, and `rm` cannot open a file to take one line out of it.
  ///
  /// **Not auto-detected, unlike every other kind.** A field is named in camel
  /// case, which is also how a substate's own field is spelled: making `remove
  /// Home` consult the fields would turn a project with a `home` field into one
  /// where the page needs `--kind page`. So `--kind field` is asked for, and
  /// what carries the discoverability is the failure path above, which names
  /// the command when the name it was handed is a field.
  WritePlan _removeField(
    Casing name,
    FrxWorkspace repo, {
    required String? state,
    required bool apply,
  }) => inSourceIndex(() {
    // One snapshot for the whole plan. Without a scope every lookup builds its
    // own index, and this plan reads the same state file five times and parses
    // it three: the owner search, the declaration, and the edit.
    final field = name.camel;
    final owner = state == null
        ? _fieldOwner(repo, field)
        // Parsed, not interpolated: `--state _shared` reached `Casing.parse`
        // raw and threw a `FormatException` the runner does not map, so a bad
        // flag value exited 255 with a stack trace where every other command
        // exits 64 with a sentence.
        : _requireSubstate(state);

    final artifact = SubstateArtifact(owner);

    final stateFile = artifact.stateFile(repo.businessRedux);
    if (!stateFile.existsSync()) {
      refuse(
        'Substate "${owner.snake}" has no ${p.relative(stateFile.path)} — '
        'is the name right? (see `frx list-substates`).',
      );
    }

    final source = StateSource(stateFile);
    // Read before it is removed: which imports the field was the reason for is
    // a question about its declaration — `IList<String> tags` needs
    // fast_immutable_collections, `Task? current` needs the model — and after
    // the removal there is no declaration left to ask.
    final declaration = source.declarationOf(
      className: artifact.stateType,
      name: field,
    );
    if (declaration == null) {
      refuse(
        '${artifact.stateType} has no field "$field" '
        '(${p.relative(stateFile.path)}).',
      );
    }
    final prune = ImportProbes.forRemoved(repo, [declaration]);
    final selectors = SelectorsSource(repo.selectorsFile);

    // What still reads it *inside the two files being edited*. Neither is
    // frx's to rewrite: a computed getter on the state class and a selector
    // whose body was hand-written are somebody's code, and the state file is
    // one the guard will not let them repair afterwards. So this refuses
    // instead of writing a file that cannot compile and reporting `✓`.
    //
    // The template ships an instance — `bool get isAvailable => token != null;`
    // beside `String? get token` — so this is the ordinary case, not the corner
    // one.
    final readers = [
      for (final member in source.readersOf(
        className: artifact.stateType,
        field: field,
      ))
        '${artifact.stateType}.$member',
      if (selectors.exists)
        for (final member in selectors.readersOf(
          selectorType: artifact.selectorType,
          getterName: field,
        ))
          '${artifact.selectorType}.$member',
    ];
    if (readers.isNotEmpty) {
      refuse(
        'Field "$field" is still read by ${readers.join(', ')} — removing it '
        'would leave ${readers.length == 1 ? 'that member' : 'those members'} '
        'naming a declaration that is gone.\n'
        '  Rewrite or delete '
        '${readers.length == 1 ? 'it' : 'them'} first; a selector body is '
        'yours to edit by hand, and `frx remove <name> --kind field` again '
        'afterwards.',
      );
    }

    final wiring = [
      Wiring.of(
        artifact.stateType,
        stateFile,
        source.removeField(
          className: artifact.stateType,
          name: field,
          prune: prune,
        ),
        way: WiringWay.unwired,
      ),
      if (selectors.exists)
        Wiring.of(
          'Selectors',
          selectors.file,
          selectors.removeSelector(
            selectorType: artifact.selectorType,
            getterName: field,
            prune: prune,
          ),
          skipped:
              '${artifact.selectorType} has no "$field" getter — nothing to '
              'unwire.',
          way: WiringWay.unwired,
        ),
    ];

    // The setter goes with the field. `add-field --action` writes it and the
    // `value` kind arrives with one, and what it does is `copyWith(<field>:)` —
    // so left behind it is not a stale action, it is a file that does not
    // compile. Named in the plan like any other deletion, which is what the
    // preview is for: a hand-edited setter is visible before `--apply`.
    final setter = File(
      p.join(
        repo.businessRedux.path,
        artifact.folder,
        'actions',
        'set_${name.snake}_action.dart',
      ),
    );
    final hasSetter = setter.existsSync();

    // The slice's other actions are *not* deleted — `add_tasks_action.dart` is
    // the slice's, not the field's — but the ones that assign it stop
    // compiling, and "run the audit" in the closing line does not say which
    // files. Named here, at the moment of the decision, from the preview.
    final holders = _actionsNaming(repo, artifact, field, except: setter);

    return WritePlan(
      changes: Changeset([
        ...wiring.edits,
        if (hasSetter) DeleteFile(setter.path),
      ]),
      header:
          'Remove field "$field" from ${artifact.stateType}  '
          '(substate: ${owner.snake})',
      narrate: () {
        console.out.writeln();
        wiring.narrate();
        if (holders.isEmpty) return;
        console.out.writeln(
          'Still names "$field" (left in place, will not compile):',
        );
        for (final f in holders) {
          console.out.writeln('  ! ${p.relative(f)}');
        }
        console.out.writeln();
      },
      previewOnly: !apply,
      previewNotice: kPreviewNotice,
      closing:
          '✓ Removed field "$field" from ${artifact.stateType}'
          '${hasSetter ? ' (with its setter action)' : ''}.\n'
          '  Note: reducers that assigned it and connectors that read it now '
          'dangle — run `frx doctor` / `dart analyze`.',
      // The freezed part still declares the field in `copyWith` and `==`, so
      // the state does not compile until it is regenerated. Same package as
      // `add-field`'s, and an incremental build handles it.
      build: (_) => BuildStep.build(
        FrxWorkspace.packageRootOf(stateFile.path),
        nextHint: 'regenerate the freezed part without the field',
      ),
    );
  });

  /// The slice's action files that still name [field], [except] the setter this
  /// removal already deletes.
  ///
  /// Text, not a parse: this is a warning list, and the question "does anything
  /// in here still say the word" is exactly what it looks like. A false
  /// positive costs a line of output; the alternative — saying nothing — is
  /// what left `add_tasks_action.dart` assigning a field that no longer exists
  /// with the command reporting `✓`.
  List<String> _actionsNaming(
    FrxWorkspace repo,
    SubstateArtifact artifact,
    String field, {
    required File except,
  }) {
    final dir = Directory(
      p.join(repo.businessRedux.path, artifact.folder, 'actions'),
    );
    if (!dir.existsSync()) return const [];

    final word = RegExp('\\b${RegExp.escape(field)}\\b');
    final naming = <String>[];
    for (final file in sourceIndex.filesUnder(dir, recursive: false)) {
      if (p.equals(file.path, except.path)) continue;
      if (word.hasMatch(sourceIndex.sourceOf(file))) naming.add(file.path);
    }
    return naming..sort();
  }

  /// The `--state` value, as the substate name it has to be.
  Casing _requireSubstate(String raw) {
    try {
      return Casing.parse(raw);
    } on FormatException catch (e) {
      usageException('Invalid --state "$raw": ${e.message}');
    }
  }

  /// The one substate whose state class declares [field].
  ///
  /// The same stance as an action's: found rather than demanded, and *refused*
  /// rather than guessed when more than one carries the name — which for a
  /// field is the common case, not the corner one. Every slice `add-substate`
  /// made with its default kind has a `value`, and picking one of them under
  /// `--apply` is not a recoverable mistake.
  Casing _fieldOwner(FrxWorkspace repo, String field) {
    final owners = _substatesWithField(repo, field);
    if (owners.isEmpty) {
      // Not `frx which` — it resolves a *class or route* to its artifact and
      // answers "not a wired frx substate or page" for every field there is,
      // which is a dead end dressed as a next step.
      refuse(
        'No substate declares a field "$field" (see `frx list-substates` for '
        'the slices, and `frx graph --focus <slice>` for what each holds).',
      );
    }
    if (owners.length > 1) {
      usageException(
        '"$field" is a field of ${owners.length} substates '
        '(${owners.map((o) => o.snake).join(', ')}). '
        'Disambiguate with --state <substate>.',
      );
    }
    return owners.single;
  }

  /// The substates whose state class declares a field named [field].
  ///
  /// Parses rather than greps: a `value` inside a doc comment or an action's
  /// body is not a field, and the question being asked is what the factory
  /// declares. Pre-filtered on the text first, so a slice that never says the
  /// word is not parsed at all.
  ///
  /// A folder this cannot read simply does not answer — a state file that is
  /// missing, does not parse, holds no `@freezed` class, or is not even named
  /// like one (`_shared/`, `2fa/`). All three failures are caught, because this
  /// runs on the failure path of *every* `frx remove`: an unhandled
  /// `FormatException` here turned a plain typo into exit 255 and a stack trace.
  List<Casing> _substatesWithField(FrxWorkspace repo, String field) {
    final owners = <Casing>[];
    for (final folder in repo.substateDirs()) {
      try {
        final name = Casing.parse(folder);
        final artifact = SubstateArtifact(name);
        final file = artifact.stateFile(repo.businessRedux);
        if (!file.existsSync()) continue;
        // The cheap half: a state file that does not contain the word cannot
        // declare it, and is read without being parsed.
        if (sourceIndex.unitIf(file, (s) => s.contains(field)) == null) {
          continue;
        }
        final declared = StateSource(
          file,
        ).declarationOf(className: artifact.stateType, name: field);
        if (declared != null) owners.add(name);
      } on FormatException {
        continue;
      } on StateError {
        continue;
      }
    }
    return owners;
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
