import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../workspace/frx_workspace.dart';
import '../ast/declarations.dart';
import '../ast/source_index.dart';
import 'ast_edit.dart';

/// One substate composed into the root `AppState`.
class Substate {
  const Substate({required this.field, required this.type});

  /// The field name on `AppState`, e.g. `logIn`.
  final String field;

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

/// The outcome of wiring a substate into `AppState`.
class WireResult implements EditOutcome {
  const WireResult({
    required this.source,
    required this.changes,
    required this.alreadyWired,
  });

  /// The full, edited `app_state.dart` source (unchanged if [alreadyWired]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a field of the same name already existed — nothing was changed.
  final bool alreadyWired;

  @override
  bool get unchanged => alreadyWired;
}

/// The outcome of unwiring a substate from `AppState`.
class UnwireResult with Unwiring {
  const UnwireResult({
    required this.source,
    required this.changes,
    required this.found,
  });

  /// The full, edited `app_state.dart` source (unchanged when not [found]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a factory field of the given name existed and was removed.
  @override
  final bool found;
}

/// Reads and edits `business/lib/redux/app_state.dart` via the analyzer AST.
///
/// This is the single wiring point for substates in this project, so it is the
/// foundation every state-related command builds on. Parsing (not resolving) is
/// enough to read and locate nodes, and needs no package config — fast and
/// dependency-free at runtime. Edits are computed as precise character-offset
/// insertions found via the AST, then spliced into the source; `dart format`
/// normalizes the whitespace afterwards.
class AppStateSource {
  AppStateSource(this.file);

  final File file;

  /// Path of `app_state.dart` relative to the repo root.
  static const _relativePath = 'business/lib/redux/app_state.dart';

  /// The `business/lib/redux` directory that holds `app_state.dart` and every
  /// substate folder.
  Directory get reduxDir => file.parent;

  /// The monorepo root — `redux` → `lib` → `business` → root.
  Directory get repoRoot => reduxDir.parent.parent.parent;

  /// Finds `app_state.dart` by walking up from [startDir] (or the current
  /// directory) until a `business/lib/redux/app_state.dart` is found. This lets
  /// the CLI run from anywhere inside the monorepo, or after a global install.
  ///
  /// For a caller with **no** workspace yet — `list-substates` resolving from
  /// the user's `--root`, and `TargetResolver` asking whether there is a project
  /// of either kind above. A caller that already holds one uses [of]: walking up
  /// from a root already found can only return the same file, or one outside the
  /// repo, and the second is what it did.
  static AppStateSource locate({String? startDir}) {
    final root = walkUpForMarker(
      startDir,
      _relativePath,
      (origin) =>
          'Could not find "$_relativePath" walking up from "$origin". '
          'Run this from inside the monorepo, or pass --root.',
    );
    return AppStateSource(File(p.join(root.path, _relativePath)));
  }

  /// The `app_state.dart` inside an already-resolved workspace.
  ///
  /// A command that holds a workspace has already answered "where is the
  /// monorepo". Walking up again would answer it a second time and, because
  /// [locate] keys on a different marker, could answer it *differently* — a
  /// repo whose `AppState` is missing sends it climbing past the root it was
  /// just handed, to report the absence against some ancestor directory.
  static AppStateSource of(FrxWorkspace repo) {
    final file = File(p.join(repo.root.path, _relativePath));
    if (!file.existsSync()) {
      // Not [locate]'s advice. "Run this from inside the monorepo, or pass
      // --root" is what you say to someone who is somewhere else; the root here
      // is already resolved and already honoured `--root`. What is wrong is the
      // project.
      // Says what is missing and where it was looked for, and nothing about
      // what the caller wanted with it: `graph` and `doctor` reach this too, and
      // "no AppState to wire into" is wrong for a command that only reads.
      throw StateError(
        'No "$_relativePath" under ${repo.root.path} — this project has no '
        'AppState.',
      );
    }
    return AppStateSource(file);
  }

  /// Returns the substates currently composed into `AppState`, in source order.
  List<Substate> readSubstates() {
    final unit = _parse();
    final ctor = _redirectingFactory(_appStateClass(unit));

    // In analyzer 14+, every FormalParameter exposes `name` and `type`
    // directly, so there's no wrapper node to unwrap.
    return [
      for (final param in ctor.parameters.parameters)
        Substate(
          field: param.name?.lexeme ?? '<unnamed>',
          type: param.type?.toSource() ?? 'dynamic',
        ),
    ];
  }

  /// Wires a substate into `AppState`: adds the model import (kept sorted among
  /// the relative imports), a `required <type> <field>` factory parameter, and
  /// a `<field>: <type>()` entry in `AppState.initial()`. Returns the edited
  /// source; idempotent when the field already exists.
  WireResult wireSubstate({
    required String field,
    required String type,
    required String importPath,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = _parse(content);
    final appState = _appStateClass(unit);
    final factory = _redirectingFactory(appState);
    final initial = _initialFactory(appState);

    if (factory.parameters.parameters.any((x) => x.name?.lexeme == field)) {
      return WireResult(source: content, changes: const [], alreadyWired: true);
    }

    final edits = <Edit>[];
    final changes = <String>[];

    // 1) import, inserted in sorted position among the relative imports.
    final imports = unit.directives.whereType<ImportDirective>().toList();
    if (!imports.any((d) => d.uri.stringValue == importPath)) {
      edits.add(importInsertion(imports, importPath));
      changes.add("import '$importPath';");
    }

    // 2) factory parameter, before `wait` (kept last) or appended.
    final params = factory.parameters;
    final waitParam = params.parameters
        .where((x) => x.name?.lexeme == 'wait')
        .firstOrNull;
    // Named params live inside `{ }`, whose `}` (rightDelimiter) sits *before*
    // the `)` — an empty list must close against the `}`, or the parameter
    // lands outside the group.
    edits.add(
      insertIntoList(
        elements: params.parameters,
        closer: params.rightDelimiter ?? params.rightParenthesis,
        element: 'required $type $field',
        before: waitParam,
      ),
    );
    changes.add('factory field: required $type $field');

    // 3) `initial()` argument, before `wait:` or appended.
    final args = _initialArguments(initial);
    final waitArg = args.arguments
        .whereType<NamedArgument>()
        .where((e) => e.name.lexeme == 'wait')
        .firstOrNull;
    edits.add(
      insertIntoList(
        elements: args.arguments,
        closer: args.rightParenthesis,
        element: '$field: $type()',
        before: waitArg,
      ),
    );
    changes.add('initial(): $field: $type()');

    return WireResult(
      source: applyEdits(content, edits),
      changes: changes,
      alreadyWired: false,
    );
  }

  /// Removes a substate from `AppState`: drops the `required <type> <field>`
  /// factory parameter, the `<field>: <type>()` entry in `initial()`, and the
  /// model import [importPath] (when present). The inverse of [wireSubstate];
  /// returns the edited source, or `found: false` when no such field exists.
  UnwireResult unwireSubstate({required String field, String? importPath}) {
    final content = sourceIndex.sourceOf(file);
    final unit = _parse(content);
    final appState = _appStateClass(unit);
    final factory = _redirectingFactory(appState);

    final param = factory.parameters.parameters
        .where((x) => x.name?.lexeme == field)
        .firstOrNull;
    if (param == null) {
      return UnwireResult(source: content, changes: const [], found: false);
    }

    final edits = <Edit>[removeListItem(content, param)];
    final changes = <String>['factory field: $field'];

    // The `<field>: <type>()` entry in `initial()`.
    final args = _initialArguments(_initialFactory(appState));
    final arg = args.arguments
        .whereType<NamedArgument>()
        .where((e) => e.name.lexeme == field)
        .firstOrNull;
    if (arg != null) {
      edits.add(removeListItem(content, arg));
      changes.add('initial(): $field');
    }

    // The model import, matched exactly against the path add-substate used.
    if (importPath != null) {
      final imp = unit.directives
          .whereType<ImportDirective>()
          .where((d) => d.uri.stringValue == importPath)
          .firstOrNull;
      if (imp != null) {
        edits.add(removeDirective(content, imp));
        changes.add("import '$importPath'");
      }
    }

    return UnwireResult(
      source: applyEdits(content, edits),
      changes: changes,
      found: true,
    );
  }

  // --- AST helpers ----------------------------------------------------------

  /// The tree for [file], or for [content] when the caller is mid-edit and
  /// holding text that is not on disk yet.
  CompilationUnit _parse([String? content]) => content == null
      ? sourceIndex.unitFor(file)
      : parseString(content: content, throwIfDiagnostics: false).unit;

  ClassDeclaration _appStateClass(CompilationUnit unit) {
    final appState = classNamed(unit, 'AppState');
    if (appState == null) {
      throw StateError('class AppState not found in "${file.path}".');
    }
    return appState;
  }

  Iterable<ConstructorDeclaration> _constructors(ClassDeclaration cls) {
    final body = cls.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];
    return members.whereType<ConstructorDeclaration>();
  }

  /// The generative `= _AppState` factory: unnamed, redirecting.
  ConstructorDeclaration _redirectingFactory(ClassDeclaration cls) {
    final ctor = _constructors(cls)
        .where(
          (c) =>
              c.factoryKeyword != null &&
              c.name == null &&
              c.redirectedConstructor != null,
        )
        .firstOrNull;
    if (ctor == null) {
      throw StateError(
        'AppState redirecting factory constructor not found in "${file.path}".',
      );
    }
    return ctor;
  }

  ConstructorDeclaration _initialFactory(ClassDeclaration cls) {
    final ctor = _constructors(
      cls,
    ).where((c) => c.name?.lexeme == 'initial').firstOrNull;
    if (ctor == null) {
      throw StateError(
        'AppState.initial() factory not found in "${file.path}".',
      );
    }
    return ctor;
  }

  /// The argument list of the `AppState(...)` call inside `initial()`, whether
  /// or not it is `const`. An unresolved parse renders `const AppState(...)` as
  /// an [InstanceCreationExpression] but a non-const `AppState(...)` as a
  /// [MethodInvocation]; matching the callee *name* across both handles either,
  /// where grabbing the first `InstanceCreationExpression` would pick an inner
  /// `const Foo()` and splice the new argument into the wrong object.
  ArgumentList _initialArguments(ConstructorDeclaration initial) {
    final finder = _AppStateConstruction();
    initial.body.accept(finder);
    final args = finder.arguments;
    if (args == null) {
      throw StateError(
        'AppState.initial() does not construct AppState(...) — '
        'cannot wire automatically.',
      );
    }
    return args;
  }
}

/// Finds the argument list of the first `AppState(...)` construction, matching
/// both the `const`/`new` form ([InstanceCreationExpression]) and the
/// un-keyworded form ([MethodInvocation]) — how an *unresolved* parse represents
/// a constructor call it can't tell apart from a function call.
class _AppStateConstruction extends RecursiveAstVisitor<void> {
  ArgumentList? arguments;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _maybe(node.constructorName.type.toSource(), node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _maybe(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  void _maybe(String name, ArgumentList list) {
    if (arguments == null && name == 'AppState') arguments = list;
  }
}
