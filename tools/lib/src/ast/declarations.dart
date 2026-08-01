/// Finding a declaration by name in an unresolved parse tree.
///
/// Small, but it is the second thing every reader in frx re-implements after
/// [Construction] — six files spelled the same two-step by hand:
///
///     unit.declarations
///         .whereType<ClassDeclaration>()
///         .where((c) => c.namePart.typeName.lexeme == name)
///         .firstOrNull
///
/// `namePart.typeName.lexeme` rather than a `name` field is an analyzer 14
/// spelling, and it is the sort of detail that is fine in one place and a
/// migration in six.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// Every class declared at the top level of [unit].
Iterable<ClassDeclaration> classesIn(CompilationUnit unit) =>
    unit.declarations.whereType<ClassDeclaration>();

/// The top-level class called [name], or null when the unit has none.
ClassDeclaration? classNamed(CompilationUnit unit, String name) {
  for (final c in classesIn(unit)) {
    if (c.namePart.typeName.lexeme == name) return c;
  }
  return null;
}

/// The name of the first top-level class, or null for a unit with none.
///
/// Used where a file is known to hold one artifact and the question is only
/// what it is called.
String? firstClassNameIn(CompilationUnit unit) =>
    classesIn(unit).firstOrNull?.namePart.typeName.lexeme;

/// The top-level extension type called [name], or null.
ExtensionTypeDeclaration? extensionTypeNamed(
  CompilationUnit unit,
  String name,
) {
  for (final d in unit.declarations.whereType<ExtensionTypeDeclaration>()) {
    if (d.namePart.typeName.lexeme == name) return d;
  }
  return null;
}
