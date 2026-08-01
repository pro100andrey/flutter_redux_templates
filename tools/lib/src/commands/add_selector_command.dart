import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../scaffold/type_imports.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Adds a computed getter to a substate's `Select<Pascal>` extension type in the
/// selectors facade — the manual edit (open selectors.dart, find the block, add
/// a getter) done for you. No codegen: selectors are hand-written code.
class AddSelectorCommand extends WritingCommand {
  @override
  String get name => 'add-selector';

  @override
  String get description =>
      'Add a computed getter to a substate\'s Select<Pascal> selector.';

  @override
  String get invocation => 'frx add-selector <substate> <name>';

  @override
  List<String> get aliases => ['asel'];

  @override
  List<String> get positionals => const ['substate', 'name'];

  @override
  WriteFlags get flags => const WriteFlags(force: false, diff: true);

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'type',
        abbr: 't',
        defaultsTo: 'Object?',
        help: 'The getter return type. Tighten it from the default.',
      )
      ..addOption(
        'expr',
        abbr: 'e',
        help:
            'The getter body expression. Defaults to reading the state field '
            'of the same name (`_state.<substate>.<name>`).',
      );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final substate = requireCasing(0);
    final getter = requireCasing(1);

    final artifact = SubstateArtifact(substate);
    final appState = AppStateSource.of(repo);
    final selectors = SelectorsSource.beside(appState.file);
    if (!selectors.exists) {
      refuse(
        'No selectors.dart beside ${p.relative(appState.file.path)} — nothing '
        'to add a selector to.',
      );
    }

    final returnType = results['type'] as String;
    final result = selectors.addSelector(
      selectorType: artifact.selectorType,
      getterName: getter.camel,
      returnType: returnType,
      expr:
          (results['expr'] as String?) ??
          '_state.${artifact.name.camel}.${getter.camel}',
      // `--type 'IList<String>'` names a package type in a library that need
      // not already import it — the same hole `add-field --action` had.
      imports: TypeImports.forType(returnType),
    );

    final wiring = [
      Wiring.at(
        selectors.file,
        result,
        skipped: 'getter "${getter.camel}" already present — skipped.',
      ),
    ];

    return WritePlan(
      changes: Changeset(wiring.edits),
      header: 'Add selector "${getter.camel}" to ${artifact.selectorType}',
      narrate: wiring.narrate,
      closing: result.alreadyPresent
          ? '✓ Nothing to do.'
          : '✓ Added ${artifact.selectorType}.${getter.camel}.',
    );
  }
}
