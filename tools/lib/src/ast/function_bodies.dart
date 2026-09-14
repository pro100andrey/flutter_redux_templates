/// What a function body evaluates to, read without resolution.
///
/// `_Vm fromStore() => _Vm(…)` and `List<AutoRoute> get routes => […]` are the
/// shapes frx writes, and both editors also accept the block form somebody
/// reformatted them into — a body whose first `return` carries the value. The
/// two readers each kept a visitor for that second case, one of them written
/// twice.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// The expression [body] returns: an arrow body's, or the first `return`'s in
/// a block. Null for a block with no `return` and for an external or native
/// body.
Expression? resultOf(FunctionBody body) {
  if (body is ExpressionFunctionBody) {
    return body.expression;
  }
  final finder = _ReturnFinder();
  body.accept(finder);
  return finder.expression;
}

/// Finds the first returned expression in a block body.
class _ReturnFinder extends RecursiveAstVisitor<void> {
  Expression? expression;

  @override
  void visitReturnStatement(ReturnStatement node) {
    expression ??= node.expression;
    super.visitReturnStatement(node);
  }
}
