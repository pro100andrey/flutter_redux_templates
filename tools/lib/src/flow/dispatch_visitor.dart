/// Finding every `dispatch*(...)` in a subtree — and in the functions of the
/// same file it calls out to.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'flow_model.dart';

/// Every function-like declaration in a unit that a callback could be built by,
/// keyed by name: the members of every class, and the top-level functions.
///
/// Parse-only, so this is a name table and not a resolution. Two members with
/// the same name in two classes of one file collapse into one entry — the last
/// wins. That is the same ambiguity the rest of the flow reader already lives
/// with (`Foo()` cannot be told from a function call either), and the shape it
/// mis-resolves — one connector file declaring two factories with a same-named
/// private helper — puts both helpers in the same view-model anyway.
Map<String, AstNode> localFunctionBodies(CompilationUnit unit) {
  final out = <String, AstNode>{};
  for (final decl in unit.declarations) {
    if (decl is FunctionDeclaration) {
      out[decl.name.lexeme] = decl.functionExpression.body;
    } else if (decl is ClassDeclaration) {
      for (final member in decl.body.members) {
        if (member is MethodDeclaration) {
          out[member.name.lexeme] = member.body;
        }
      }
    }
  }
  return out;
}

/// Reports every variable a destructuring pattern declares.
///
/// `for (final (i, t) in rows.indexed)` is the shape that made this necessary:
/// both `i` and `t` are bindings, and either could shadow a method the walk
/// would otherwise follow into.
class _PatternVariables extends RecursiveAstVisitor<void> {
  _PatternVariables(this.onName);

  final void Function(String) onName;

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    onName(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }
}

/// Collects every `dispatch*(...)` inside whatever it is pointed at, **and
/// inside the members it calls out to**.
///
/// [_root] bounds the upward walks (condition / trigger) so they never escape
/// the subtree we were handed.
///
/// ## Why it follows calls
///
/// A view-model field's value is not always written where the field is. The
/// moment a list row needs a callback, the row gets built by a helper:
///
/// ```dart
/// ItemVm _item(TaskView task) =>
///     ItemVm(id: task.id.value, onTap: () => dispatch(OpenTaskAction(...)));
///
/// @override
/// _Vm fromStore() =>
///     _Vm(view: ViewVm(tasks: [for (final t in rows) _item(t)]));
/// ```
///
/// Reading only the subtree of the `_Vm` argument finds no dispatch here, so
/// the region reports no interactions — and a region with no interactions gets
/// no lane, so it leaves the diagram entirely. The loss is silent and it is not
/// small: measured on one page, six of eleven regions were missing, and the
/// nine dispatches that went with them were the ones the map is read for.
///
/// [_locals] is the name table to follow into; without one this reads a single
/// subtree exactly as it used to. [_visited] is shared down the recursion, so a
/// helper reached twice is read once and two helpers calling each other
/// terminate.
///
/// ## Why a name is not enough
///
/// The table is keyed by name and the file is parsed, not resolved, so a name
/// standing in the source is not evidence that it refers to the declaration of
/// that name. Anything nearer binds first:
///
/// ```dart
/// void reset() => dispatch(ResetAction());       // a method
/// _Vm fromStore() {
///   final reset = 'label';                       // …and a local that shadows it
///   return _Vm(caption: reset);                  // NOT a dispatch
/// }
/// ```
///
/// Following that produced a use case for `caption` dispatching `ResetAction`,
/// which no run of the program can do. That is worse than the gap this class
/// was written to close: a missing region is a map that is short, and an
/// invented one is a map that is wrong, and only the second survives being
/// checked against the code. So a name is followed only when nothing between it
/// and the unit root binds it — [_boundNearby].
class DispatchVisitor extends RecursiveAstVisitor<void> {
  DispatchVisitor([this._root, this._locals = const {}, Set<String>? visited])
    : _visited = visited ?? <String>{};

  final AstNode? _root;
  final Map<String, AstNode> _locals;
  final Set<String> _visited;
  final steps = <DispatchStep>[];

  /// Source offsets of the `dispatch*(` call sites [steps] came from.
  ///
  /// The identity of a dispatch is where it is written, and the accounting in
  /// `FlowReader.read` needs exactly that. Counting [steps] instead compared a
  /// tally of *attributions* against a tally of *call sites*: one helper
  /// reached from two `_Vm` fields is two attributions of one site, which made
  /// the subtraction go negative and swallow a real gap elsewhere in the same
  /// file — the failure `UntracedDispatch` exists to prevent, reintroduced
  /// inside it.
  final callSites = <int>{};

  /// Read [name]'s body, if it is a local function we have not been through.
  ///
  /// The nested visitor is rooted at that body rather than at ours: `trigger`
  /// and `condition` are read by walking up from the dispatch, and the answer
  /// that matters is the one local to where the closure is written — `onTap`
  /// for the example above, which is inside the helper and not visible from the
  /// call site.
  void _follow(String name, AstNode at) {
    final body = _locals[name];
    if (body == null || _boundNearby(name, at)) {
      return;
    }

    if (!_visited.add(name)) {
      return;
    }

    final v = DispatchVisitor(body, _locals, _visited);
    body.accept(v);
    steps.addAll(v.steps);
    callSites.addAll(v.callSites);
  }

  /// Whether [name] is bound by something between [at] and the unit root.
  ///
  /// Parameters, local variables, pattern variables, catch clauses, loop
  /// variables — every binder Dart lets shadow a member with. Walking outwards
  /// is enough because a binding that is not on this ancestor chain is not in
  /// scope here, and a member the chain does not shadow is the one the name
  /// means.
  static bool _boundNearby(String name, AstNode at) {
    for (AstNode? n = at; n != null; n = n.parent) {
      if (_bindsIn(n, name)) {
        return true;
      }
    }
    return false;
  }

  static bool _bindsIn(AstNode node, String name) {
    if (node is FunctionExpression) {
      return _inParams(node.parameters, name);
    }

    if (node is MethodDeclaration) {
      return _inParams(node.parameters, name);
    }

    if (node is FunctionDeclaration) {
      return _inParams(node.functionExpression.parameters, name);
    }

    if (node is CatchClause) {
      return node.exceptionParameter?.name.lexeme == name ||
          node.stackTraceParameter?.name.lexeme == name;
    }

    if (node is Block) {
      // A `var`/`final` anywhere in the enclosing block, not only before this
      // point: Dart hoists local declarations over their whole block, so a name
      // declared later still shadows the member here (and referring to it early
      // is a compile error, not a call to the member).
      for (final statement in node.statements) {
        if (statement is VariableDeclarationStatement &&
            statement.variables.variables.any((v) => v.name.lexeme == name)) {
          return true;
        }

        if (statement is FunctionDeclarationStatement &&
            statement.functionDeclaration.name.lexeme == name) {
          return true;
        }
        // `final (reset, _) = pair;` — a destructuring declaration binds every
        // variable in its pattern, and reads exactly like the `final reset = …`
        // one statement up. Missing it left the walk following `reset` into a
        // method of that name and inventing a use case for the field it was
        // handed to, which is the failure this whole guard exists to prevent.
        if (statement is PatternVariableDeclarationStatement &&
            _patternBinds(statement.declaration.pattern, name)) {
          return true;
        }
      }
    }
    // `if (label case final reset?)` and the `case` arms of a switch: the
    // pattern's variables are in scope for the branch, and the branch is where
    // the reference sits.
    if (node is IfStatement) {
      final caseClause = node.caseClause;
      if (caseClause != null &&
          _patternBinds(caseClause.guardedPattern.pattern, name)) {
        return true;
      }
    }
    if (node is SwitchPatternCase) {
      return _patternBinds(node.guardedPattern.pattern, name);
    }

    if (node is SwitchExpressionCase) {
      return _patternBinds(node.guardedPattern.pattern, name);
    }

    if (node is ForStatement) {
      return _loopBinds(node.forLoopParts, name);
    }

    if (node is ForElement) {
      return _loopBinds(node.forLoopParts, name);
    }

    return false;
  }

  /// Whether a `for` — statement or collection element, the two carry the same
  /// loop parts — declares [name].
  static bool _loopBinds(ForLoopParts parts, String name) {
    if (parts is ForPartsWithDeclarations) {
      return parts.variables.variables.any((v) => v.name.lexeme == name);
    }

    if (parts is ForEachPartsWithDeclaration) {
      return parts.loopVariable.name.lexeme == name;
    }

    if (parts is ForEachPartsWithPattern) {
      return _patternBinds(parts.pattern, name);
    }

    return false;
  }

  static bool _inParams(FormalParameterList? params, String name) =>
      params?.parameters.any((p) => p.name?.lexeme == name) ?? false;

  /// Any variable a destructuring pattern introduces —
  /// `for (final (i, t) in …)` binds both `i` and `t`.
  static bool _patternBinds(AstNode pattern, String name) {
    var found = false;
    pattern.accept(_PatternVariables((n) => found |= n == name));
    return found;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final kind = DispatchKind.parse(node.methodName.name);
    // A view-model calls `dispatch(...)` bare; a service holds the store and
    // calls `_store.dispatch(...)`. Both dispatch. The target is required to be
    // a plain reference so that only something *named* like a store qualifies —
    // it keeps `whatever().dispatch(...)` out without needing to resolve types.
    final target = node.target;
    if (kind != null && (target == null || target is SimpleIdentifier)) {
      steps.add(_stepFrom(node, kind));
      callSites.add(node.offset);
    } else if (target == null) {
      // `_item(task)` — a helper on the factory, or a top-level one. Also the
      // shape a constructor call takes without resolution, which is why the
      // name table decides: only something this file declares as a function is
      // followed.
      _follow(node.methodName.name, node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A tear-off — `onTap: _openTask` — is the same hop with the parentheses
    // left off, and loses the dispatch the same way.
    //
    // Guarded down to identifiers that stand for themselves. The `methodName`
    // of an invocation is handled above; either side of a `.` belongs to
    // something else — the right-hand side is a member of another object, and
    // the left-hand side is that object, so `session.userName` beside a
    // `session()` method used to be read as a call to it.
    //
    // An argument *label* needs no guard: `onTap:` is a token on the
    // [NamedArgument], not an identifier node, so it never arrives here.
    final parent = node.parent;
    final isInvocationName =
        parent is MethodInvocation && parent.methodName == node;
    final isPartOfDotted =
        (parent is PropertyAccess && parent.propertyName == node) ||
        parent is PrefixedIdentifier ||
        (parent is MethodInvocation && parent.target == node);
    if (!isInvocationName && !isPartOfDotted) {
      _follow(node.name, node);
    }

    super.visitSimpleIdentifier(node);
  }

  /// The argument holding the action.
  ///
  /// The first, normally: `dispatch(SaveAction())`. `StoreProvider` takes the
  /// context first — `StoreProvider.dispatch<AppState>(context, SaveAction())`
  /// — and reading argument zero there names `context` as the action
  /// dispatched. The call was recognised all along; what it resolved to was the
  /// wrong node, so the action really being dispatched was reported as reached
  /// by nobody.
  ///
  /// Keyed on the class name rather than on a shape heuristic: this is
  /// async_redux's own static API, and `StoreProvider.dispatch` is the whole
  /// list of ways to get a store from a `BuildContext`.
  static Expression? _actionArgumentOf(MethodInvocation node) {
    final args = node.argumentList.arguments.whereType<Expression>().toList();
    final target = node.target;
    final at = target is SimpleIdentifier && target.name == 'StoreProvider'
        ? 1
        : 0;
    return at < args.length ? args[at] : null;
  }

  DispatchStep _stepFrom(MethodInvocation node, DispatchKind kind) {
    final arg = _actionArgumentOf(node);
    var target = arg?.toSource() ?? '?';
    String? route;
    String? routeArgs;

    if (arg is MethodInvocation) {
      if (arg.target != null) {
        // A factory such as `GoAction.push(const LogInRoute())`.
        target = '${arg.target!.toSource()}.${arg.methodName.name}';
        final inner = arg.argumentList.arguments
            .whereType<Expression>()
            .firstOrNull;
        if (inner != null) {
          route = _routeTypeOf(inner);
          if (route != null) {
            routeArgs = _routeArgsOf(inner);
          }
        }
      } else {
        // `RegistrationAction(...)` — a constructor, as far as we can tell.
        target = arg.methodName.name;
      }
    }

    return DispatchStep(
      kind: kind,
      target: target,
      route: route,
      routeArgs: routeArgs,
      awaited: node.parent is AwaitExpression,
      condition: _enclosingCondition(node),
      trigger: _enclosingTrigger(node),
    );
  }

  /// The nearest named argument between this dispatch and the callback root —
  /// `onChanged` for a dispatch inside `FieldVm(onChanged: …)`. Null when the
  /// dispatch sits directly in the view-model field's own callback.
  String? _enclosingTrigger(AstNode node) {
    for (var n = node.parent; n != null && n != _root; n = n.parent) {
      if (n is NamedArgument) {
        return n.name.lexeme;
      }
    }
    return null;
  }

  /// What a route constructor was handed, source-verbatim and without the
  /// `key:` auto_route adds to every generated route — `id: id`. Null when it
  /// takes nothing, so a plain route reads no differently than before.
  static String? _routeArgsOf(Expression e) {
    final NodeList<Argument> args;
    if (e is InstanceCreationExpression) {
      args = e.argumentList.arguments;
    } else if (e is MethodInvocation) {
      args = e.argumentList.arguments;
    } else {
      return null;
    }

    final kept = [
      for (final a in args)
        if (!(a is NamedArgument && a.name.lexeme == 'key')) a.toSource(),
    ];

    return kept.isEmpty ? null : kept.join(', ');
  }

  /// `const LogInRoute()` → `LogInRoute`; anything unrecognised → null.
  static String? _routeTypeOf(Expression e) {
    final src = e.toSource().replaceAll('const ', '').trim();
    final open = src.indexOf('(');
    final name = open < 0 ? src : src.substring(0, open);
    return name.endsWith('Route') ? name : null;
  }

  /// The condition of the nearest enclosing `if`, so a guarded dispatch can be
  /// drawn as an `alt` block. Stops at the callback boundary.
  static String? _enclosingCondition(AstNode node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is FunctionExpression) {
        return null; // left the callback
      }

      if (n is IfStatement) {
        return n.expression.toSource();
      }
    }
    return null;
  }
}
