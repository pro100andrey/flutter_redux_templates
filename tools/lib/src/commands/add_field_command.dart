import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../redux/selectors_source.dart';
import '../redux/state_source.dart';
import '../scaffold/artifact_templates.dart';
import '../scaffold/type_imports.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Adds a field to an existing substate's `@freezed` state class — the common
/// daily edit (grow a state) done for you: the factory parameter is spliced in
/// via AST, and `--action` also scaffolds its `Set<Field>Action` setter.
class AddFieldCommand extends WritingCommand {
  @override
  String get name => 'add-field';

  @override
  String get description =>
      'Add a field to an existing substate state (+ optional setter action).';

  @override
  String get invocation => 'frx add-field <substate> <name:type>';

  @override
  List<String> get aliases => ['af'];

  @override
  List<String> get positionals => const ['substate', 'name:type'];

  @override
  WriteFlags get flags =>
      const WriteFlags(force: false, diff: true, buildRunner: true);

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'default',
        abbr: 'd',
        help:
            'A `@Default(<expr>)` for the field. Required for a non-nullable '
            'type (a state field must be nullable or defaulted).',
      )
      ..addFlag(
        'action',
        abbr: 'a',
        negatable: false,
        help: 'Also scaffold a Set<Field>Action setter in the substate.',
      )
      ..addFlag(
        'selector',
        defaultsTo: true,
        help:
            'Also add a getter for the field to the substate\'s Select<Pascal> '
            'in selectors.dart.',
      );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final substate = requireCasing(0);
    final (field, type) = requireSpec(1);

    final defaultExpr = results['default'] as String?;
    // A freezed state is constructed with no args (`XState()`), so every field
    // must be nullable or carry a default — refuse a bare non-nullable one.
    if (!type.endsWith('?') && defaultExpr == null) {
      usageException(
        'Non-nullable field "${field.camel}" ($type) needs --default <expr> '
        '(or make it nullable: "${field.camel}:$type?").',
      );
    }

    final artifact = SubstateArtifact(substate);
    final stateFile = artifact.stateFile(repo.businessRedux);
    if (!stateFile.existsSync()) {
      refuse(
        'Substate "${substate.snake}" has no ${p.relative(stateFile.path)} — '
        'is the name right? (see `frx list-substates`).',
      );
    }

    // The field's type and its `@Default(...)` both land in the state file, so
    // both are asked — `tags:IList<String>?` needs the package for the type,
    // `--default 'IListConst([])'` for the expression.
    final result = StateSource(stateFile).addField(
      className: artifact.stateType,
      name: field.camel,
      type: type,
      defaultExpr: defaultExpr,
      imports: TypeImports.forAll([type, defaultExpr]),
    );

    final withAction = results['action'] as bool;
    final actionFile = File(
      p.join(
        stateFile.parent.parent.path,
        'actions',
        'set_${field.snake}_action.dart',
      ),
    );

    // A field with no selector is a field a connector cannot read without
    // hand-editing selectors.dart, so wire it here rather than leaving the
    // substate half-wired.
    //
    // Located only when asked for: there may be no app_state.dart to sit beside,
    // and --no-selector has to be a way out of that, not a flag consulted after
    // the throw.
    final selectors = (results['selector'] as bool)
        ? SelectorsSource.beside(AppStateSource.of(repo).file)
        : null;
    final selectorResult = (selectors != null && selectors.exists)
        ? selectors.addSelector(
            selectorType: artifact.selectorType,
            getterName: field.camel,
            returnType: type,
            expr: '_state.${substate.camel}.${field.camel}',
            // The getter lands in a different library than the state, so the
            // type it returns has to be importable there too. Only the type —
            // the default is never written into selectors.dart.
            imports: TypeImports.forType(type),
          )
        : null;

    // The setter is scaffolding: never clobber an existing one (a hand-edited
    // SetValueAction, say) — write it only when absent.
    final writeAction = withAction && !actionFile.existsSync();
    final setterContent = writeAction
        ? ArtifactTemplates.fieldSetter(substate, field, type)
        : null;

    final state = Wiring.at(
      stateFile,
      result,
      skipped: 'field "${field.camel}" already present — skipped.',
    );
    final selector = selectorResult == null
        ? null
        : Wiring.at(
            selectors!.file,
            selectorResult,
            skipped: 'getter "${field.camel}" already present — skipped.',
          );

    return WritePlan(
      changes: Changeset()
        ..addIf(state.edit)
        ..addIf(
          setterContent == null
              ? null
              : WriteFile(actionFile.path, setterContent),
        )
        ..addIf(selector?.edit),
      header: 'Add field "${field.camel}" ($type) to ${artifact.stateType}',
      // Not [WiringReport.narrate]: the two blocks are not adjacent, because two
      // notes about what was *not* written can land between them.
      narrate: () {
        state.narrate();
        if (withAction && !writeAction) {
          console.out
            ..writeln()
            ..writeln(
              '  • ${p.relative(actionFile.path)} already exists '
              '— left in place',
            );
        }
        if (selectors != null && selectorResult == null) {
          // Asked for, but there is no facade to add to. Said out loud: the
          // getter is what a connector reads the field through, and its absence
          // surfaces much later, as a compile error in the connector.
          console.out
            ..writeln()
            ..writeln(
              '  • no ${p.relative(selectors.file.path)} — selector not added.',
            );
        }
        if (selector != null) {
          console.out.writeln();
          selector.narrate();
        }
        console.out.writeln();
      },
      build: (_) => BuildStep.build(
        FrxWorkspace.packageRootOf(stateFile.path),
        nextHint: 'regenerate the freezed part for the field',
        args: const ['--delete-conflicting-outputs'],
      ),
    );
  }
}
