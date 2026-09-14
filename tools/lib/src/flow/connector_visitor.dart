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
Set<String> connectorNamesIn(CompilationUnit unit) {
  final built = <String>{};
  unit.accept(_ConnectorVisitor(built));
  return built;
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
  _ConnectorVisitor(this.into);

  final Set<String> into;

  void _record(String name) {
    if (name.endsWith('Connector')) {
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
    if (node.target == null) {
      _record(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}
