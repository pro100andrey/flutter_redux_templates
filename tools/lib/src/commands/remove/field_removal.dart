import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ast/source_index.dart';
import '../../engine/build_step.dart';
import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../model/substate_artifact.dart';
import '../../redux/selectors_source.dart';
import '../../redux/state_source.dart';
import '../../refusal.dart';
import '../../scaffold/type_imports.dart';
import '../../util/casing.dart';
import '../../util/console.dart';
import '../../workspace/frx_workspace.dart';
import '../substate_target.dart';
import '../wiring.dart';
import '../writing_command.dart';
import 'left_in_place.dart';

/// `remove --kind field`: one field of one substate — the factory parameter,
/// the getter on the facade and the setter action that copies it — the inverse
/// of `add-field`.
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
/// case, which is also how a substate's own field is spelled: making
/// `remove Home` consult the fields would turn a project with a `home` field
/// into one where the page needs `--kind page`. So `--kind field` is asked
/// for, and what carries the discoverability is the failure path of the
/// command, which names this kind when the name it was handed is a field.
mixin FieldRemoval on WritingCommand {
  /// The plan for field [name] of the substate that owns it.
  WritePlan removeField(
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
        : requireSubstate(state);

    final artifact = SubstateArtifact(owner);
    final stateFile = requireStateFile(repo, artifact);

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
    final setter = artifact.actionFile(repo.businessRedux, 'set_${name.snake}');
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
        narrateLeftInPlace('Still names "$field"', holders);
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
    final dir = artifact.actionsDir(repo.businessRedux);
    if (!dir.existsSync()) {
      return const [];
    }

    final word = RegExp('\\b${RegExp.escape(field)}\\b');
    final naming = <String>[];
    for (final file in sourceIndex.filesUnder(dir, recursive: false)) {
      if (p.equals(file.path, except.path)) {
        continue;
      }
      if (word.hasMatch(sourceIndex.sourceOf(file))) {
        naming.add(file.path);
      }
    }

    return naming..sort();
  }

  /// The one substate whose state class declares [field].
  ///
  /// The same stance as an action's: found rather than demanded, and *refused*
  /// rather than guessed when more than one carries the name — which for a
  /// field is the common case, not the corner one. Every slice `add-substate`
  /// made with its default kind has a `value`, and picking one of them under
  /// `--apply` is not a recoverable mistake.
  Casing _fieldOwner(FrxWorkspace repo, String field) {
    final owners = substatesWithField(repo, field);
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
  /// `FormatException` here turned a plain typo into exit 255 and a stack
  /// trace.
  List<Casing> substatesWithField(FrxWorkspace repo, String field) {
    final owners = <Casing>[];
    for (final folder in repo.substateDirs()) {
      try {
        final name = Casing.parse(folder);
        final artifact = SubstateArtifact(name);
        final file = artifact.stateFile(repo.businessRedux);
        if (!file.existsSync()) {
          continue;
        }
        // The cheap half: a state file that does not contain the word cannot
        // declare it, and is read without being parsed.
        if (sourceIndex.unitIf(file, (s) => s.contains(field)) == null) {
          continue;
        }

        final declared = StateSource(
          file,
        ).declarationOf(className: artifact.stateType, name: field);
        if (declared != null) {
          owners.add(name);
        }
      } on FormatException {
        continue;
      } on FrxRefusal {
        continue;
      }
    }
    return owners;
  }
}
