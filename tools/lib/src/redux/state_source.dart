import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';

import '../ast/declarations.dart';
import '../ast/source_index.dart';
import 'ast_edit.dart';

/// Reads and edits a substate's `@freezed` state model — inserting a new field
/// into its redirecting factory constructor, the same AST-splice approach
/// [AppStateSource] uses for `AppState`.
class StateSource {
  StateSource(this.file);

  final File file;

  /// Adds a `<type> <name>` field to the factory of class [className]
  /// (`<Pascal>State`). [defaultExpr] wraps it in `@Default(...)`; [imports]
  /// are added (sorted) when the type needs them (e.g. fast_immutable_collections
  /// for an `IList`).
  ///
  /// A field of that name already there is left alone unless [retype], which
  /// rewrites its declaration to the one asked for.
  ///
  /// **Why retyping belongs here at all.** `add-substate --kind table` scaffolds
  /// `IMap<int, Object>` on purpose — the element type is not known when the
  /// slice is made, and tightening it later was hand work. That was fine while
  /// the state file could be edited by hand; once the guard refused that
  /// channel, the only way to turn `Object` into `Task` was gone, and a traced
  /// run shipped `IMap<int, Object>` because of it. A command that silently
  /// answers "already present" to "make this field a `Task`" is not idempotent,
  /// it is unhelpful.
  Edited addField({
    required String className,
    required String name,
    required String type,
    String? defaultExpr,
    List<String> imports = const [],
    bool retype = false,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = sourceIndex.unitFor(file);
    final cls = _stateClass(unit, className);
    final factory = _redirectingFactory(cls, className);

    final existing = factory.parameters.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull;
    if (existing != null) {
      final wanted = _declaration(type, name, defaultExpr);
      if (!retype || existing.toSource() == wanted) {
        return Edited.nothing(content);
      }

      final edits = <Edit>[Edit.replace(existing.offset, existing.end, wanted)];
      // The new type may need an import the old one did not.
      final added = addImports(applyEdits(content, edits), imports);
      return Edited(
        source: added.source,
        changes: ['field: ${existing.toSource()} → $wanted', ...added.changes],
      );
    }

    final params = factory.parameters;
    final decl = _declaration(type, name, defaultExpr);
    final delimiter = params.rightDelimiter;
    final edits = <Edit>[
      // A factory with no named group at all has to grow one; from there the
      // shared comma rule applies.
      delimiter == null
          ? Edit.insert(params.rightParenthesis.offset, '{$decl}')
          : insertIntoList(
              elements: params.parameters,
              closer: delimiter,
              element: decl,
            ),
    ];

    // Imports the field's type needs, each in sorted position in its section.
    final added = addImports(applyEdits(content, edits), imports);
    return Edited(
      source: added.source,
      changes: [...added.changes, 'field: $decl'],
    );
  }

  /// The `@Default(...)` expression on field [name], or null when it has none.
  ///
  /// Asked before a retype, which rebuilds the declaration from scratch: a
  /// default the old one carried and the new invocation does not would be
  /// dropped, and dropping it changes what `AppState.initial()` produces for
  /// every reader. Better to refuse and name it than to write it away.
  String? defaultOf({required String className, required String name}) {
    final unit = sourceIndex.unitFor(file);
    final factory = _redirectingFactory(
      _stateClass(unit, className),
      className,
    );
    final param = factory.parameters.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull;
    if (param == null) return null;
    for (final annotation in param.metadata) {
      if (annotation.name.name != 'Default') continue;
      final args = annotation.arguments?.arguments;
      if (args != null && args.isNotEmpty) return args.first.toSource();
    }
    return null;
  }

  /// The source of one factory parameter — written in one place so an added
  /// field and a retyped one cannot disagree about their own spelling.
  static String _declaration(String type, String name, String? defaultExpr) =>
      defaultExpr != null
      ? '@Default($defaultExpr) $type $name'
      : '$type $name';

  ClassDeclaration _stateClass(CompilationUnit unit, String className) {
    final cls = classNamed(unit, className);
    if (cls == null) {
      throw StateError('class $className not found in "${file.path}".');
    }
    return cls;
  }

  /// The `const factory <Name>({...}) = _<Name>;` redirecting constructor.
  ConstructorDeclaration _redirectingFactory(
    ClassDeclaration cls,
    String className,
  ) {
    final body = cls.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];
    final ctor = members
        .whereType<ConstructorDeclaration>()
        .where(
          (c) =>
              c.factoryKeyword != null &&
              c.name == null &&
              c.redirectedConstructor != null,
        )
        .firstOrNull;
    if (ctor == null) {
      throw StateError(
        '$className has no redirecting factory constructor in "${file.path}" '
        '— is it a `@freezed` state class?',
      );
    }
    return ctor;
  }
}
