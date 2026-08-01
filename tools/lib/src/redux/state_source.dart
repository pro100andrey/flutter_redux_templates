import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';

import '../ast/declarations.dart';
import '../ast/source_index.dart';
import 'ast_edit.dart';

/// The outcome of adding a field to a `@freezed` substate state class.
class StateFieldResult implements EditOutcome {
  const StateFieldResult({
    required this.source,
    required this.changes,
    required this.alreadyPresent,
  });

  /// The full edited state-file source (unchanged if [alreadyPresent]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a factory parameter of that name already existed.
  final bool alreadyPresent;

  @override
  bool get unchanged => alreadyPresent;
}

/// Reads and edits a substate's `@freezed` state model — inserting a new field
/// into its redirecting factory constructor, the same AST-splice approach
/// [AppStateSource] uses for `AppState`.
class StateSource {
  StateSource(this.file);

  final File file;

  /// Adds a `<type> <name>` field to the factory of class [className]
  /// (`<Pascal>State`). [defaultExpr] wraps it in `@Default(...)`; [imports]
  /// are added (sorted) when the type needs them (e.g. fast_immutable_collections
  /// for an `IList`). Idempotent when a field of that name already exists.
  StateFieldResult addField({
    required String className,
    required String name,
    required String type,
    String? defaultExpr,
    List<String> imports = const [],
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = sourceIndex.unitFor(file);
    final cls = _stateClass(unit, className);
    final factory = _redirectingFactory(cls, className);

    if (factory.parameters.parameters.any((p) => p.name?.lexeme == name)) {
      return StateFieldResult(
        source: content,
        changes: const [],
        alreadyPresent: true,
      );
    }

    final edits = <Edit>[];
    final changes = <String>[];

    // Imports the field's type needs, each in sorted position in its section.
    final importDirs = unit.directives.whereType<ImportDirective>().toList();
    final present = importDirs.map((d) => d.uri.stringValue).toSet();
    for (final uri in imports.where((u) => !present.contains(u))) {
      edits.add(importInsertion(importDirs, uri));
      changes.add("import '$uri';");
    }

    final params = factory.parameters;
    final decl = defaultExpr != null
        ? '@Default($defaultExpr) $type $name'
        : '$type $name';
    final delimiter = params.rightDelimiter;
    edits.add(
      // A factory with no named group at all has to grow one; from there the
      // shared comma rule applies.
      delimiter == null
          ? Edit.insert(params.rightParenthesis.offset, '{$decl}')
          : insertIntoList(
              elements: params.parameters,
              closer: delimiter,
              element: decl,
            ),
    );
    changes.add('field: $decl');

    return StateFieldResult(
      source: applyEdits(content, edits),
      changes: changes,
      alreadyPresent: false,
    );
  }

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
