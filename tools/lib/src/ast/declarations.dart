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
///
/// The same goes one level down. A class's members are `decl.body.members`
/// whatever the body is — an `EmptyClassBody` (`class Foo;`) answers with an
/// empty list — so the `body is BlockClassBody ? body.members : const []`
/// that seven readers wrote is the analyzer's own accessor spelled long. And
/// the lookups every editor makes inside a class — the parameter called `x`,
/// the redirecting factory, the declared type of each field — were each
/// written out two to eight times, which is two to eight chances to disagree
/// about what `required this.x` or `= _Foo` looks like.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'construction.dart' show Construction;

/// Every class declared at the top level of [unit].
Iterable<ClassDeclaration> classesIn(CompilationUnit unit) =>
    unit.declarations.whereType<ClassDeclaration>();

/// The top-level class called [name], or null when the unit has none.
ClassDeclaration? classNamed(CompilationUnit unit, String name) {
  for (final c in classesIn(unit)) {
    if (c.namePart.typeName.lexeme == name) {
      return c;
    }
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
    if (d.namePart.typeName.lexeme == name) {
      return d;
    }
  }

  return null;
}

/// The top-level mixin called [name], or null.
///
/// `name`, not the `namePart` spelling a class uses: analyzer 14 gives a mixin
/// a plain name token.
MixinDeclaration? mixinNamed(CompilationUnit unit, String name) {
  for (final d in unit.declarations.whereType<MixinDeclaration>()) {
    if (d.name.lexeme == name) {
      return d;
    }
  }

  return null;
}

/// The parameter called [name] in [params], or null.
///
/// In analyzer 14+, every [FormalParameter] exposes `name` and `type`
/// directly, so there is no wrapper node to unwrap — a defaulted parameter
/// carries its default on a `defaultClause` rather than in a wrapper.
FormalParameter? parameterNamed(FormalParameterList params, String name) {
  for (final p in params.parameters) {
    if (p.name?.lexeme == name) {
      return p;
    }
  }

  return null;
}

/// The unnamed, redirecting factory of [cls] — the
/// `const factory Foo({…}) = _Foo;` a `@freezed` class is built through — or
/// null when it has none.
ConstructorDeclaration? redirectingFactoryOf(ClassDeclaration cls) {
  for (final c in cls.body.members.whereType<ConstructorDeclaration>()) {
    if (c.factoryKeyword != null &&
        c.name == null &&
        c.redirectedConstructor != null) {
      return c;
    }
  }

  return null;
}

/// The declared type of each instance field of [cls], by name.
///
/// `this.x` is almost never written with a type — the type sits on the field
/// declaration — so a reader that wants a constructor parameter's type looks
/// here. A field written without one (`final x = 0;`) is absent.
Map<String, String> fieldTypesOf(ClassDeclaration cls) {
  final types = <String, String>{};
  for (final member in cls.body.members.whereType<FieldDeclaration>()) {
    if (member.isStatic) {
      continue;
    }

    final type = member.fields.type?.toSource();
    if (type == null) {
      continue;
    }

    for (final v in member.fields.variables) {
      types[v.name.lexeme] = type;
    }
  }

  return types;
}

/// Whether [cls] declares an instance or static field called [name].
bool declaresField(ClassDeclaration cls, String name) => cls.body.members
    .whereType<FieldDeclaration>()
    .any((f) => f.fields.variables.any((v) => v.name.lexeme == name));
