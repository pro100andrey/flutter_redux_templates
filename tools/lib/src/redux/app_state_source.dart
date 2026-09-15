import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/construction.dart';
import '../ast/declarations.dart';
import '../ast/directives.dart';
import '../ast/file_source.dart';
import '../refusal.dart';
import '../workspace/frx_workspace.dart';
import 'ast_edit.dart';

/// One substate composed into the root `AppState`.
class Substate {
  const Substate({required this.field, required this.type, this.offset});

  /// The field name on `AppState`, e.g. `logIn`.
  final String field;

  /// Where the field's name sits in `app_state.dart`, for a finding to anchor
  /// on. Null only for a [Substate] built without a tree.
  final int? offset;

  /// The declared type, e.g. `LogInState`.
  final String type;

  /// Whether this field is a substate rather than something the framework put
  /// on `AppState`.
  ///
  /// `wait` is an `AsyncRedux` `Wait`, has no folder, no selector and no change
  /// log entry, and every reader that walks these fields has to skip it. The
  /// test was written out six times before it lived here — and one of them
  /// getting it wrong means a reader reporting a missing state file for a class
  /// the framework ships.
  bool get isSubstate => type.endsWith('State');
}

/// Reads and edits `business/lib/redux/app_state.dart` via the analyzer AST.
///
/// This is the single wiring point for substates in this project, so it is the
/// foundation every state-related command builds on. Parsing (not resolving) is
/// enough to read and locate nodes, and needs no package config — fast and
/// dependency-free at runtime. Edits are computed as precise character-offset
/// insertions found via the AST, then spliced into the source; `dart format`
/// normalizes the whitespace afterwards.
class AppStateSource extends FileSource {
  AppStateSource(super.file);

  /// The `app_state.dart` inside an already-resolved workspace.
  ///
  /// A command that holds a workspace has already answered "where is the
  /// monorepo". Walking up again would answer it a second time and, because
  /// [AppStateSource.locate] keys on a different marker, could answer it
  /// *differently* — a
  /// repo whose `AppState` is missing sends it climbing past the root it was
  /// just handed, to report the absence against some ancestor directory.
  factory AppStateSource.of(FrxWorkspace repo) {
    final file = File(p.join(repo.root.path, _relativePath));
    if (!file.existsSync()) {
      // Not [locate]'s advice. "Run this from inside the monorepo, or pass
      // --root" is what you say to someone who is somewhere else; the root here
      // is already resolved and already honoured `--root`. What is wrong is the
      // project. Says what is missing and where it was looked for, and nothing
      // about what the caller wanted with it: `graph` and `doctor` reach this
      // too, and "no AppState to wire into" is wrong for a command that only
      // reads.
      throw FrxRefusal(
        'No "$_relativePath" under ${repo.root.path} — this project has no '
        'AppState.',
      );
    }
    return AppStateSource(file);
  }

  /// Finds `app_state.dart` by walking up from [startDir] (or the current
  /// directory) until a `business/lib/redux/app_state.dart` is found. This lets
  /// the CLI run from anywhere inside the monorepo, or after a global install.
  ///
  /// For a caller with **no** workspace yet — `list-substates` resolving from
  /// the user's `--root`, and `TargetResolver` asking whether there is a
  /// project of either kind above. A caller that already holds one uses
  /// [AppStateSource.of]:
  /// walking up from a root already found can only return the same file, or one
  /// outside the repo, and the second is what it did.
  factory AppStateSource.locate({String? startDir}) =>
      AppStateSource(locateFile(_relativePath, startDir: startDir));

  /// Path of `app_state.dart` relative to the repo root.
  static const _relativePath = 'business/lib/redux/app_state.dart';

  /// The `business/lib/redux` directory that holds `app_state.dart` and every
  /// substate folder.
  Directory get reduxDir => file.parent;

  /// The monorepo root — `redux` → `lib` → `business` → root.
  Directory get repoRoot => reduxDir.parent.parent.parent;

  /// Returns the substates currently composed into `AppState`, in source order.
  List<Substate> readSubstates() {
    final factory = _redirectingFactory(_appStateClass(unit));
    return [
      for (final param in factory.parameters.parameters)
        Substate(
          field: param.name?.lexeme ?? '<unnamed>',
          type: param.type?.toSource() ?? 'dynamic',
          offset: param.name?.offset ?? param.offset,
        ),
    ];
  }

  /// Wires a substate into `AppState`: adds the model import (kept sorted among
  /// the relative imports), a `required <type> <field>` factory parameter, and
  /// a `<field>: <type>()` entry in `AppState.initial()`. Returns the edited
  /// source; idempotent when the field already exists.
  Edited wireSubstate({
    required String field,
    required String type,
    required String importPath,
  }) {
    final (source: content, :unit) = snapshot;
    final appState = _appStateClass(unit);
    final params = _redirectingFactory(appState).parameters;
    final initial = _initialFactory(appState);

    if (parameterNamed(params, field) != null) {
      return Edited.nothing(content);
    }

    final edits = <Edit>[];
    final changes = <String>[];

    // 1) import, inserted in sorted position among the relative imports.
    final imports = importsOf(unit);
    if (importNamed(imports, importPath) == null) {
      edits.add(importInsertion(imports, importPath));
      changes.add("import '$importPath';");
    }

    // 2) factory parameter, before `wait` (kept last) or appended.
    // Named params live inside `{ }`, whose `}` (rightDelimiter) sits *before*
    // the `)` — an empty list must close against the `}`, or the parameter
    // lands outside the group.
    edits.add(
      insertIntoList(
        elements: params.parameters,
        closer: params.rightDelimiter ?? params.rightParenthesis,
        element: 'required $type $field',
        before: parameterNamed(params, 'wait'),
      ),
    );
    changes.add('factory field: required $type $field');

    // 3) `initial()` argument, before `wait:` or appended.
    final args = _initialArguments(initial);
    edits.add(
      insertIntoList(
        elements: args.arguments,
        closer: args.rightParenthesis,
        element: '$field: $type()',
        before: namedArgumentOf(args, 'wait'),
      ),
    );
    changes.add('initial(): $field: $type()');

    return Edited(source: applyEdits(content, edits), changes: changes);
  }

  /// Removes a substate from `AppState`: drops the `required <type> <field>`
  /// factory parameter, the `<field>: <type>()` entry in `initial()`, and the
  /// model import [importPath] (when present). The inverse of [wireSubstate];
  /// returns the edited source, or `found: false` when no such field exists.
  Unwired unwireSubstate({required String field, String? importPath}) {
    final (source: content, :unit) = snapshot;
    final appState = _appStateClass(unit);

    final param = parameterNamed(
      _redirectingFactory(appState).parameters,
      field,
    );
    if (param == null) {
      return Unwired.absent(content);
    }

    final edits = <Edit>[removeListItem(content, param)];
    final changes = <String>['factory field: $field'];

    // The `<field>: <type>()` entry in `initial()`.
    final arg = namedArgumentOf(
      _initialArguments(_initialFactory(appState)),
      field,
    );
    if (arg != null) {
      edits.add(removeListItem(content, arg));
      changes.add('initial(): $field');
    }

    // The model import, matched exactly against the path add-substate used.
    if (importPath != null) {
      final imp = importNamed(importsOf(unit), importPath);
      if (imp != null) {
        edits.add(removeDirective(content, imp));
        changes.add("import '$importPath'");
      }
    }

    return Unwired(source: applyEdits(content, edits), changes: changes);
  }

  // --- AST helpers ----------------------------------------------------------

  ClassDeclaration _appStateClass(CompilationUnit unit) =>
      classIn(unit, 'AppState');

  /// The generative `= _AppState` factory: unnamed, redirecting.
  ConstructorDeclaration _redirectingFactory(ClassDeclaration cls) =>
      redirectingFactoryOf(cls) ??
      (throw FrxRefusal(
        'AppState redirecting factory constructor not found in "${file.path}".',
      ));

  ConstructorDeclaration _initialFactory(ClassDeclaration cls) {
    for (final c in cls.body.members.whereType<ConstructorDeclaration>()) {
      if (c.name?.lexeme == 'initial') {
        return c;
      }
    }
    throw FrxRefusal('AppState.initial() factory not found in "${file.path}".');
  }

  /// The argument list of the `AppState(...)` call inside `initial()`, whether
  /// or not it is `const`. An unresolved parse renders `const AppState(...)` as
  /// an [InstanceCreationExpression] but a non-const `AppState(...)` as a
  /// [MethodInvocation]; [Construction] reads the callee *name* across both,
  /// where grabbing the first `InstanceCreationExpression` would pick an inner
  /// `const Foo()` and splice the new argument into the wrong object.
  ArgumentList _initialArguments(ConstructorDeclaration initial) =>
      Construction.firstIn(
        initial.body,
        (made) => made.fullName == 'AppState',
      )?.arguments ??
      (throw const FrxRefusal(
        'AppState.initial() does not construct AppState(...) — '
        'cannot wire automatically.',
      ));
}
