import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../redux/store_source.dart';
import '../scaffold/substate_scaffold.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Scaffolds a substate folder and wires it into `AppState` via AST.
///
/// This is the "smart" command: instead of the developer hand-editing
/// `app_state.dart` after generating files, the import, the factory field, and
/// the `initial()` entry are inserted automatically.
class AddSubstateCommand extends WritingCommand {
  @override
  String get name => 'add-substate';

  @override
  String get description =>
      'Scaffold an AsyncRedux substate and wire it into AppState (AST).';

  @override
  String get invocation => 'frx add-substate <name>';

  @override
  List<String> get aliases => ['as'];

  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  void describeArgs(ArgParser parser) {
    parser.addOption(
      'kind',
      abbr: 'k',
      allowed: ['value', 'search', 'table'],
      defaultsTo: 'value',
      help: 'Which substate flavour to scaffold.',
      allowedHelp: {
        'value': 'A single nullable `value` field + SetValueAction.',
        'search': 'A `query` string + `IList<int> view` + SetQueryAction.',
        'table': 'A byId `IMap` table + view + Add…/Retrieve… actions.',
      },
    );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final name = requireName();
    final force = results['force'] as bool;
    final kind = SubstateKind.parse(results['kind'] as String);
    final source = AppStateSource.of(repo);

    final a = SubstateArtifact(name);
    final substateDir = a.dir(source.reduxDir).path;
    final scaffold = SubstateScaffold(name, kind: kind);
    final files = scaffold.files();

    // A dry run writes nothing, so it should still show the plan (with
    // `overwrite` actions) rather than failing — the exit-70 guard only applies
    // to a real run.
    //
    // Guarded on the *directory*, not on the individual files the write engine
    // checks: a substate is regenerated as a unit, and `--force` here means
    // "replace the folder", which is why the plan below can delete it.
    final exists = Directory(substateDir).existsSync();
    if (!(results['dry-run'] as bool) && exists && !force) {
      refuse(
        '${p.relative(substateDir)} already exists. Use --force to overwrite.',
      );
    }

    final wire = source.wireSubstate(
      field: a.field,
      type: a.stateType,
      importPath: a.stateImportPath,
    );

    // Wire the selectors into the `Select`/`Selectors` facade, when the project
    // has one. Skipped silently for projects without a `selectors.dart`.
    final selectors = SelectorsSource.beside(source.file);
    final selectorBlock = scaffold.selectorBlock();
    final selectorWire = selectors.exists
        ? selectors.wire(
            field: a.field,
            pascal: name.pascal,
            block: selectorBlock.block,
            imports: selectorBlock.imports,
            force: force,
          )
        : null;

    // The persistor's change log, when the project kept it: one line per
    // AppState field, feeding the `Δ …` the action logger prints. Opt-in like
    // the docs export — a project without the block gets no entry and no note.
    final store = StoreSource.of(repo);
    final storeWire = store.changed() == null
        ? null
        : store.wire(field: a.field);

    final wiring = [
      Wiring.of(
        'AppState',
        source.file,
        wire,
        skipped: 'field "${a.field}" already present — wiring skipped.',
      ),
      if (storeWire != null)
        Wiring.of(
          'Store',
          store.file,
          storeWire,
          skipped: 'change log already lists "${a.field}" — wiring skipped.',
        ),
      if (selectorWire != null)
        Wiring.of(
          'Selectors',
          selectors.file,
          selectorWire,
          skipped: '${a.selectorType} already present — wiring skipped.',
        ),
    ];

    return WritePlan(
      changes: Changeset([
        // With --force, regenerate the folder cleanly so files from a prior kind
        // don't linger (e.g. a value-kind `set_value_action.dart` when the
        // substate is re-scaffolded as a table). Deletes run first, so declaring
        // it alongside the writes is safe.
        if (force && exists) DeleteDirectory(substateDir),
        for (final entry in files.entries)
          WriteFile(p.join(substateDir, entry.key), entry.value),
        ...wiring.edits,
      ]),
      header:
          'Substate "${name.pascal}"  '
          '(field: ${a.field}, type: ${a.stateType}, kind: ${kind.name})',
      narrate: wiring.narrate,
      build: (_) => BuildStep.build(
        FrxWorkspace.packageRootOf(source.file.path),
        nextHint: 'generate the freezed part for the new state',
      ),
    );
  }
}
