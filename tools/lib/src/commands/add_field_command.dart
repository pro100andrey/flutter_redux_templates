import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
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
  /// `--force` is declared below rather than taken from the base, because here
  /// it means "the field is already there — change it", which is a narrower
  /// thing than "overwrite the file".
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
      // Retyping a field, not overwriting a file. `add-substate --kind table`
      // scaffolds `IMap<int, Object>` because the element type is unknown when
      // the slice is made, and tightening it to `IMap<int, Task>` was hand work
      // — until the guard refused hand edits to state files, at which point a
      // traced run shipped `Object` because nothing could change it.
      //
      // Behind a flag, not automatic: a silent retype would make a typo in the
      // type rewrite a field that was already right.
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help:
            'When the field already exists, rewrite its declaration to this '
            'type (and its selector getter to match).',
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
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async =>
      inSourceIndex(() => _plan(repo, results));

  /// One snapshot for the whole plan.
  ///
  /// The same type is asked about three times — the state file, the facade and
  /// the setter each import it independently — and answering "which model file
  /// supplies `ResultSuccess`" reads `models/lib`. Outside a scope every lookup
  /// builds its own index, so that directory was walked once per question.
  WritePlan _plan(FrxWorkspace repo, ArgResults results) {
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

    // Before anything reads the file. The `--force` check below parses it, and
    // it used to run first: `add-field <typo> x:int? --force` died with an
    // unhandled PathNotFoundException and a stack trace, where the same typo
    // without `--force` got the refusal two lines down. A guard that only holds
    // for some flag combinations is not a guard.
    final artifact = SubstateArtifact(substate);
    final stateFile = artifact.stateFile(repo.businessRedux);
    if (!stateFile.existsSync()) {
      refuse(
        'Substate "${substate.snake}" has no ${p.relative(stateFile.path)} — '
        'is the name right? (see `frx list-substates`).',
      );
    }

    // Retyping rebuilds the declaration from what this invocation was given, so
    // an `@Default(...)` the old one carried and this one does not is dropped —
    // silently changing `AppState.initial()` for every reader. Nullable types do
    // not require `--default`, which is exactly where it would slip through, so
    // the ask is made explicit rather than inferred.
    if ((results['force'] as bool) && defaultExpr == null) {
      final existing = StateSource(
        stateFile,
      ).defaultOf(className: artifact.stateType, name: field.camel);
      if (existing != null) {
        usageException(
          'Field "${field.camel}" currently defaults to `$existing`, and '
          '--force would drop it. Pass --default to say what it should be, or '
          '--default \'$existing\' to keep it.',
        );
      }
    }

    // The field's type and its `@Default(...)` both land in the state file, so
    // both are asked — `tags:IList<String>?` needs the package for the type,
    // `--default 'IListConst([])'` for the expression.
    final result = StateSource(stateFile).addField(
      className: artifact.stateType,
      name: field.camel,
      type: type,
      defaultExpr: defaultExpr,
      imports: [
        ...TypeImports.forAll([type, defaultExpr]),
        ...ProjectTypeImports.forAll(repo, [type, defaultExpr]),
      ],
      retype: results['force'] as bool,
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
            imports: [
              ...TypeImports.forType(type),
              ...ProjectTypeImports.forAll(repo, [type]),
            ],
            retype: results['force'] as bool,
          )
        : null;

    // The setter is scaffolding: never clobber an existing one (a hand-edited
    // SetValueAction, say) — write it only when absent.
    final writeAction = withAction && !actionFile.existsSync();
    final setterContent = writeAction
        ? ArtifactTemplates.fieldSetter(
            substate,
            field,
            type,
            extraImports: ProjectTypeImports.forAll(repo, [type]),
          )
        : null;

    final state = Wiring.at(
      stateFile,
      result,
      skipped:
          'field "${field.camel}" already present — skipped. '
          'Pass --force to rewrite its declaration to $type.',
    );
    final selector = selectorResult == null
        ? null
        : Wiring.at(
            selectors!.file,
            selectorResult,
            skipped:
                'getter "${field.camel}" already present — skipped. '
                'Pass --force to rewrite its return type.',
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
      ),
    );
  }
}
