/// Which connectors a file constructs — how a screen is composed out of
/// regions, and the one fact a dead-connector verdict rests on.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// The names of the connector classes [unit] constructs.
///
/// Shared by the page walk, which resolves each name to the file it must open
/// next, and by the graph, which needs the composition the walk uses
/// internally: a connector no file builds is dead, and the actions it alone
/// dispatches are dead with it — which the orphan list could not say while
/// composition was known only inside the walk.
///
/// **Names, where the walk resolves files.** The walk keeps only what a
/// `*_connector.dart` import resolves to, which is right for a walk that must
/// open the file next. Applied to the question "does anything construct this
/// class" it answers no for every connector that does not live in a file named
/// that way — measured: `AppConnector` lives in `app.dart` and is built in
/// `run_env.dart`, and the file-resolving read called the app's own root
/// widget unbuilt.
Set<String> connectorNamesIn(CompilationUnit unit) =>
    constructedNamesIn(unit, suffixes: const {'Connector'});

/// The names ending in one of [suffixes] that [unit] constructs.
///
/// The graph asks the connector question of service dispatchers too: a
/// `ConnectivityDispatcher` is constructed once, where the app wires its
/// services, and one nothing constructs is dead with every action only it
/// dispatches — the same verdict, one suffix over.
Set<String> constructedNamesIn(
  CompilationUnit unit, {
  required Set<String> suffixes,
}) {
  final built = <String>{};
  unit.accept(_ConnectorVisitor(built, suffixes));
  return built;
}

/// The functions in [unit] that construct a connector, by the name a caller
/// invokes them by: a top-level `openSettings` as `openSettings`, a static
/// `SettingsConnector.show` as `SettingsConnector.show`. Each maps to the
/// connectors its body constructs.
///
/// A connector shown from a dialog is built nowhere a page composes it. The
/// file declares `openSettings(context)`, which is the only place the class
/// is constructed, and three other connectors call that — so "no file
/// constructs it" was false, and the reason the verdict could not see was
/// that the construction sits behind a function call. This is the half of the
/// answer a builder file holds; [callNamesIn] is the half a caller holds.
Map<String, Set<String>> connectorBuildersIn(CompilationUnit unit) {
  final builders = <String, Set<String>>{};
  void record(String name, FunctionBody body) {
    final built = <String>{};
    body.accept(_ConnectorVisitor(built, const {'Connector'}));
    if (built.isNotEmpty) {
      builders[name] = built;
    }
  }

  // Instance and extension methods by their bare name: `context.openC()` is
  // called on a value whose type a parse cannot know, so the name is all a
  // caller holds. Missed, `extension on BuildContext { void openC() => … }`
  // — the dialog idiom written as an extension — built its connector for
  // nobody, and the connector read as constructed by no file.
  void members(String? type, Iterable<ClassMember> body) {
    for (final m in body.whereType<MethodDeclaration>()) {
      if (m.isStatic && type != null) {
        record('$type.${m.name.lexeme}', m.body);
      } else if (!m.isStatic) {
        record(m.name.lexeme, m.body);
      }
    }
  }

  for (final d in unit.declarations) {
    switch (d) {
      case FunctionDeclaration():
        record(d.name.lexeme, d.functionExpression.body);
      case ClassDeclaration():
        members(d.namePart.typeName.lexeme, d.body.members);
      case MixinDeclaration():
        members(d.name.lexeme, d.body.members);
      case ExtensionDeclaration():
        members(d.name?.lexeme, d.body.members);
      case ExtensionTypeDeclaration():
        members(d.namePart.typeName.lexeme, d.body.members);
      default:
    }
  }
  return builders;
}

/// Every function [unit] invokes by a bare name or a `Type.name` — the
/// spellings [connectorBuildersIn] keys on — and the bare name of every
/// method it invokes on something, which is how an instance or extension
/// method is keyed there. Generous on purpose: a name is cheap to hold and
/// means nothing until a builder by that name is found in a file this one
/// imports.
Set<String> callNamesIn(CompilationUnit unit) {
  final calls = <String>{};
  unit.accept(_CallVisitor(calls));
  return calls;
}

class _CallVisitor extends RecursiveAstVisitor<void> {
  _CallVisitor(this.into);

  final Set<String> into;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    into.add(node.methodName.name);
    if (target is SimpleIdentifier) {
      into.add('${target.name}.${node.methodName.name}');
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects the names of every `<Something>Connector` constructed in a tree.
///
/// A name test rather than a type test, because frx parses without resolution.
/// The suffix is the convention `add-connector` and `add-page` both write and
/// `remove` reads back, so it is the rule the rest of the CLI already keys on.
///
/// Both node shapes are collected. `const Foo()` parses as an
/// [InstanceCreationExpression]; a bare `Foo()` cannot be told from a
/// function call without resolution and arrives as a [MethodInvocation] — the
/// same ambiguity the dispatch reader already lives with.
class _ConnectorVisitor extends RecursiveAstVisitor<void> {
  _ConnectorVisitor(this.into, this.suffixes);

  final Set<String> into;
  final Set<String> suffixes;

  void _record(String name) {
    if (suffixes.any(name.endsWith)) {
      into.add(name);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target == null) {
      _record(node.methodName.name);
    } else if (target is SimpleIdentifier && _isTypeName(target.name)) {
      // `AConnector.dialog()` — a named constructor without `const` has the
      // shape of a static call, and read as one it constructed nothing.
      _record(target.name);
    }
    super.visitMethodInvocation(node);
  }

  /// `BConnector.new`, `BConnector.dialog` handed on uncalled — a tear-off
  /// constructs every time it is called, and `builder: BConnector.new` is
  /// the whole construction.
  @override
  void visitConstructorReference(ConstructorReference node) {
    _record(node.constructorName.type.name.lexeme);
    super.visitConstructorReference(node);
  }

  /// A named constructor torn off without `.new` parses as a type-prefixed
  /// identifier, which a parse cannot tell from a static field — so a
  /// `SettingsConnector.routeName` counts too. That errs the safe way: a
  /// connector wrongly counted as built stays off a list of things to delete.
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_isTypeName(node.prefix.name)) {
      _record(node.prefix.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  static bool _isTypeName(String name) =>
      name.isNotEmpty && name[0] == name[0].toUpperCase() && name[0] != '_';
}
