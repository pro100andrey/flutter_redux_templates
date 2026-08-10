import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../ast/source_index.dart';

import '../workspace/frx_workspace.dart';
import 'flow_model.dart';

/// Reads a page's use-case flow out of the source AST.
///
/// Parse-only, like the rest of frx — which means the parser cannot know that
/// `RegistrationAction(...)` is a constructor rather than a function call, so
/// both arrive as a [MethodInvocation] with a null target. That's fine: frx
/// already keys off the naming conventions it generates.
class FlowReader {
  FlowReader(this.workspace);

  final FrxWorkspace workspace;

  /// Build the flow for [connectorFile] — its `_Vm` callbacks, the actions they
  /// dispatch, and what each of those actions does.
  /// **It descends into the connectors the page is composed of.** A route
  /// connector need not hold a view-model at all: a page split into regions
  /// hands each slot a connector of its own, and the frame is then a `build`
  /// that constructs six widgets and reads nothing. Stopping at the route
  /// connector reported such a page as having no interactions — not "the frame
  /// has none", which is true, but "the page has none", which is the opposite
  /// of why the split was made. The regions are where every callback went.
  ///
  /// Depth is not bounded. The composition that prompted this is three deep —
  /// a page, a content region switching between eight views, and a rail taking
  /// a project picker as a slot — and "one level" would be a number chosen to
  /// fit one app.
  PageFlow read({
    required File connectorFile,
    required String page,
    required String connectorClass,
    required String pageClass,
  }) {
    final useCases = <UseCase>[];
    final actions = <String, ActionInfo>{};
    final regions = <String>[];
    final untraced = <UntracedDispatch>[];

    // Keyed by canonical path: a region reachable through two slots is one
    // region, and a cycle between two connectors is a stack overflow.
    final seen = <String>{};

    void walk(File file, String? owner) {
      if (!seen.add(p.canonicalize(file.path))) return;

      final unit = sourceIndex.unitFor(file);

      final vm = _VmVisitor(_localFunctionBodies(unit));
      unit.accept(vm);

      // What the file dispatches, against what the walk got to. The difference
      // is reported rather than dropped: a region with no use case gets no lane
      // and vanishes, and a map that is quietly six regions short is read as a
      // map of a page that is small. See [UntracedDispatch].
      //
      // Compared as *sets of call sites*, never as counts. One helper reached
      // from two `_Vm` fields is a shape `_VmVisitor` supports on purpose, and
      // it makes attributions outnumber call sites — subtracting tallies then
      // reads as "nothing missing" and hides a genuinely unreachable dispatch
      // elsewhere in the same file.
      final all = _DispatchVisitor();
      unit.accept(all);
      final missed = all.callSites.difference(vm.attributed);
      if (missed.isNotEmpty) {
        untraced.add(
          UntracedDispatch(
            connectorClass: owner ?? connectorClass,
            count: missed.length,
          ),
        );
      }

      // Resolve every `package:business/...` import to a file on disk so a
      // dispatched action can be looked up by class name.
      final actionFiles = _actionFilesFrom(unit, file.parent);

      for (final useCase in vm.useCases) {
        useCases.add(
          owner == null
              ? useCase
              : UseCase(name: useCase.name, steps: useCase.steps, owner: owner),
        );
        for (final step in useCase.steps) {
          if (step.isNavigation || actions.containsKey(step.target)) continue;
          final actionFile = actionFiles[step.target];
          actions[step.target] = actionFile == null
              ? ActionInfo(className: step.target)
              : readAction(actionFile);
        }
      }

      // Depth-first in source order, so the regions read down the page the way
      // its slots are written.
      for (final nested in _connectorsIn(unit, file.parent).entries) {
        if (seen.contains(p.canonicalize(nested.value.path))) continue;
        regions.add(nested.key);
        walk(nested.value, nested.key);
      }
    }

    walk(connectorFile, null);

    return PageFlow(
      page: page,
      connectorClass: connectorClass,
      pageClass: pageClass,
      useCases: useCases,
      actions: actions,
      connectorFile: connectorFile.path,
      regions: regions,
      untraced: untraced,
    );
  }

  /// The connector classes constructed inside [unit], by class name, in source
  /// order — each resolved to the file its import points at.
  ///
  /// **Constructions, not imports.** A connector importing another proves
  /// nothing about composition: a sidebar imports six action files it never
  /// builds. What makes a region part of a page is that the page's connector
  /// *builds* it — as a slot argument, or inside the `switch` a content region
  /// uses to pick one of eight views.
  ///
  /// Both node shapes are collected. `const Foo()` parses as an
  /// [InstanceCreationExpression]; a bare `Foo()` cannot be told from a function
  /// call without resolution and arrives as a [MethodInvocation] — the same
  /// ambiguity the dispatch reader already lives with.
  ///
  /// Only `app`'s connectors can appear: `ui` does not depend on `app`, so a
  /// slot is filled where the widget tree is assembled and nowhere else.
  Map<String, File> _connectorsIn(CompilationUnit unit, Directory from) {
    final built = <String>{};
    unit.accept(_ConnectorVisitor(built));
    if (built.isEmpty) return const {};

    final files = <String, File>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || !uri.endsWith('_connector.dart')) continue;
      final file = _resolveImport(uri, from);
      if (file == null || !file.existsSync()) continue;
      final cls = firstClassNameIn(sourceIndex.unitFor(file));
      if (cls != null && built.contains(cls)) files[cls] = file;
    }
    return files;
  }

  /// Every `dispatch*(...)` in [file], paired with the action files its imports
  /// resolve to.
  ///
  /// The same read [read] performs on a connector, for a source that is not
  /// one. A service dispatcher dispatches into the store exactly as a view-model
  /// does, but it has no `_Vm` and no page — so a reader that only walks
  /// connectors reports its actions as dispatched by nobody.
  ({List<DispatchStep> steps, Map<String, File> actionFiles}) readDispatches(
    File file,
  ) {
    final unit = sourceIndex.unitFor(file);
    final v = _DispatchVisitor();
    unit.accept(v);
    return (steps: v.steps, actionFiles: _actionFilesFrom(unit, file.parent));
  }

  /// What a single action does: its mixins, whether it's async, the AppState
  /// field it writes, any cascading dispatches, and whether it can fail loudly.
  ActionInfo readAction(File file) => readActionWithImports(file).info;

  /// [readAction] plus the action files this action's own imports resolve to,
  /// from one parse.
  ///
  /// A caller that follows cascades needs both — what the action dispatches and
  /// which file each dispatched name refers to. Asking for them separately
  /// parsed every action file twice, and threw away a `steps` list identical to
  /// the `dispatches` it already held.
  ({ActionInfo info, Map<String, File> actionFiles}) readActionWithImports(
    File file,
  ) {
    final unit = sourceIndex.unitFor(file);
    final v = _ActionVisitor();
    unit.accept(v);
    return (
      info: ActionInfo(
        className: v.className ?? p.basenameWithoutExtension(file.path),
        declaresClass: v.className != null,
        mixins: v.mixins,
        isAsync: v.isAsync,
        writes: v.writes,
        dispatches: v.dispatches,
        throwsUserException: v.throwsUserException,
        file: file.path,
      ),
      actionFiles: _actionFilesFrom(unit, file.parent),
    );
  }

  /// Map of `ActionClassName` → file, built from the unit's `_action.dart`
  /// imports. A `package:business/redux/x/actions/y_action.dart` import maps to
  /// `<root>/business/lib/redux/x/actions/y_action.dart`.
  ///
  /// [from] is the directory holding the source, needed for relative imports:
  /// a connector lives in `app` and reaches actions by package uri, but a
  /// service lives *inside* `business` and reaches them by `../../`.
  Map<String, File> _actionFilesFrom(CompilationUnit unit, Directory from) {
    final out = <String, File>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || !uri.endsWith('_action.dart')) continue;
      final file = _resolveImport(uri, from);
      if (file == null || !file.existsSync()) continue;
      final cls = firstClassNameIn(sourceIndex.unitFor(file));
      if (cls != null) out[cls] = file;
    }
    return out;
  }

  /// `package:<pkg>/<path>` → `<root>/<pkg>/lib/<path>`; anything without a
  /// scheme is resolved against [from].
  File? _resolveImport(String uri, Directory from) {
    if (!uri.startsWith('package:')) {
      if (uri.contains(':')) return null; // dart:, http: — not ours
      return File(p.normalize(p.join(from.path, uri)));
    }
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    return File(
      p.join(
        workspace.root.path,
        rest.substring(0, slash),
        'lib',
        rest.substring(slash + 1),
      ),
    );
  }
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

/// Collects the names of every `<Something>Connector` constructed in a tree.
///
/// A name test rather than a type test, because frx parses without resolution.
/// The suffix is the convention `add-connector` and `add-page` both write and
/// `remove` reads back, so it is the rule the rest of the CLI already keys on.
class _ConnectorVisitor extends RecursiveAstVisitor<void> {
  _ConnectorVisitor(this.into);

  final Set<String> into;

  void _record(String name) {
    if (name.endsWith('Connector')) into.add(name);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null) _record(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}

/// Every function-like declaration in a unit that a callback could be built by,
/// keyed by name: the members of every class, and the top-level functions.
///
/// Parse-only, so this is a name table and not a resolution. Two members with
/// the same name in two classes of one file collapse into one entry — the last
/// wins. That is the same ambiguity the rest of this file already lives with
/// (`Foo()` cannot be told from a function call either), and the shape it
/// mis-resolves — one connector file declaring two factories with a same-named
/// private helper — puts both helpers in the same view-model anyway.
Map<String, AstNode> _localFunctionBodies(CompilationUnit unit) {
  final out = <String, AstNode>{};
  for (final decl in unit.declarations) {
    if (decl is FunctionDeclaration) {
      out[decl.name.lexeme] = decl.functionExpression.body;
    } else if (decl is ClassDeclaration) {
      final body = decl.body;
      if (body is! BlockClassBody) continue;
      for (final member in body.members) {
        if (member is MethodDeclaration) out[member.name.lexeme] = member.body;
      }
    }
  }
  return out;
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
/// _Vm fromStore() => _Vm(view: ViewVm(tasks: [for (final t in rows) _item(t)]));
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
/// was written to close: a missing region is a map that is short, and an invented
/// one is a map that is wrong, and only the second survives being checked
/// against the code. So a name is followed only when nothing between it and the
/// unit root binds it — [_boundNearby].
class _DispatchVisitor extends RecursiveAstVisitor<void> {
  _DispatchVisitor([this._root, this._locals = const {}, Set<String>? visited])
    : _visited = visited ?? <String>{};

  final AstNode? _root;
  final Map<String, AstNode> _locals;
  final Set<String> _visited;
  final steps = <DispatchStep>[];

  /// Source offsets of the `dispatch*(` call sites [steps] came from.
  ///
  /// The identity of a dispatch is where it is written, and the accounting in
  /// [FlowReader.read] needs exactly that. Counting [steps] instead compared a
  /// tally of *attributions* against a tally of *call sites*: one helper reached
  /// from two `_Vm` fields is two attributions of one site, which made the
  /// subtraction go negative and swallow a real gap elsewhere in the same file —
  /// the failure `UntracedDispatch` exists to prevent, reintroduced inside it.
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
    if (body == null || _boundNearby(name, at)) return;
    if (!_visited.add(name)) return;
    final v = _DispatchVisitor(body, _locals, _visited);
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
      if (_bindsIn(n, name)) return true;
    }
    return false;
  }

  static bool _bindsIn(AstNode node, String name) {
    if (node is FunctionExpression) {
      return _inParams(node.parameters, name);
    }
    if (node is MethodDeclaration) return _inParams(node.parameters, name);
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
      }
    }
    if (node is ForStatement) {
      final parts = node.forLoopParts;
      if (parts is ForPartsWithDeclarations) {
        return parts.variables.variables.any((v) => v.name.lexeme == name);
      }
      if (parts is ForEachPartsWithDeclaration) {
        return parts.loopVariable.name.lexeme == name;
      }
      if (parts is ForEachPartsWithPattern) {
        return _patternBinds(parts.pattern, name);
      }
    }
    if (node is ForElement) {
      final parts = node.forLoopParts;
      if (parts is ForEachPartsWithDeclaration) {
        return parts.loopVariable.name.lexeme == name;
      }
      if (parts is ForEachPartsWithPattern) {
        return _patternBinds(parts.pattern, name);
      }
      if (parts is ForPartsWithDeclarations) {
        return parts.variables.variables.any((v) => v.name.lexeme == name);
      }
    }
    return false;
  }

  static bool _inParams(FormalParameterList? params, String name) =>
      params?.parameters.any((p) => p.name?.lexeme == name) ?? false;

  /// Any variable a destructuring pattern introduces — `for (final (i, t) in …)`
  /// binds both `i` and `t`.
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
    // Guarded down to identifiers that stand for themselves. The `methodName` of
    // an invocation is handled above; either side of a `.` belongs to something
    // else — the right-hand side is a member of another object, and the
    // left-hand side is that object, so `session.userName` beside a `session()`
    // method used to be read as a call to it.
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
    if (!isInvocationName && !isPartOfDotted) _follow(node.name, node);
    super.visitSimpleIdentifier(node);
  }

  DispatchStep _stepFrom(MethodInvocation node, DispatchKind kind) {
    final arg = node.argumentList.arguments.whereType<Expression>().firstOrNull;
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
          if (route != null) routeArgs = _routeArgsOf(inner);
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
    for (AstNode? n = node.parent; n != null && n != _root; n = n.parent) {
      if (n is NamedArgument) return n.name.lexeme;
    }
    return null;
  }

  /// `const LogInRoute()` → `LogInRoute`; anything unrecognised → null.
  /// What a route constructor was handed, source-verbatim and without the
  /// `key:` auto_route adds to every generated route — `id: id`. Null when it
  /// takes nothing, so a plain route reads no differently than before.
  String? _routeArgsOf(Expression e) {
    if (e is! InstanceCreationExpression && e is! MethodInvocation) return null;
    final args = e is InstanceCreationExpression
        ? e.argumentList.arguments
        : (e as MethodInvocation).argumentList.arguments;
    final kept = [
      for (final a in args)
        if (!(a is NamedArgument && a.name.lexeme == 'key')) a.toSource(),
    ];
    return kept.isEmpty ? null : kept.join(', ');
  }

  String? _routeTypeOf(Expression e) {
    final src = e.toSource().replaceAll('const ', '').trim();
    final open = src.indexOf('(');
    final name = open < 0 ? src : src.substring(0, open);
    return name.endsWith('Route') ? name : null;
  }

  /// The condition of the nearest enclosing `if`, so a guarded dispatch can be
  /// drawn as an `alt` block. Stops at the callback boundary.
  String? _enclosingCondition(AstNode node) {
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      if (n is FunctionExpression) return null; // left the callback
      if (n is IfStatement) return n.expression.toSource();
    }
    return null;
  }
}

/// Finds the `_Vm(...)` construction and treats each named argument as one
/// user-facing interaction.
///
/// Each argument is read with the file's own function table in hand, so a
/// callback assembled by a helper on the factory is followed rather than
/// missed — see [_DispatchVisitor].
class _VmVisitor extends RecursiveAstVisitor<void> {
  _VmVisitor(this._locals);

  final Map<String, AstNode> _locals;
  final useCases = <UseCase>[];

  /// Every `dispatch*(` call site any use case here accounts for.
  ///
  /// A set and not a count, because the same site legitimately answers for two
  /// fields — see the accounting in [FlowReader.read].
  final attributed = <int>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == '_Vm') {
      for (final a in node.argumentList.arguments.whereType<NamedArgument>()) {
        // A visited set per argument, not per file: two fields may legitimately
        // both go through the same row helper, and each is its own use case.
        final v = _DispatchVisitor(a.argumentExpression, _locals);
        a.argumentExpression.accept(v);
        if (v.steps.isEmpty) continue;
        attributed.addAll(v.callSites);
        useCases.add(UseCase(name: a.name.lexeme, steps: v.steps));
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Reads one action class: name, mixins, async-ness, the field it writes,
/// cascading dispatches, and whether it throws a `UserException`.
class _ActionVisitor extends RecursiveAstVisitor<void> {
  String? className;
  List<String> mixins = const [];
  bool isAsync = false;
  List<StateWrite> writes = const [];
  List<DispatchStep> dispatches = const [];
  bool throwsUserException = false;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    className ??= node.namePart.typeName.lexeme;
    final withClause = node.withClause;
    if (withClause != null) {
      mixins = [for (final m in withClause.mixinTypes) m.toSource()];
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'reduce') {
      isAsync = node.body.isAsynchronous;
      final v = _DispatchVisitor();
      node.body.accept(v);
      dispatches = v.steps;
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // First write wins: an action that branches still writes one substate, and
    // the outermost call is visited first, so a nested copy cannot shadow it.
    if (writes.isEmpty) writes = _writesOf(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    if (node.expression.toSource().contains('UserException')) {
      throwsUserException = true;
    }
    super.visitThrowExpression(node);
  }
}

/// The AppState field [node] writes, or null if it is not a `copyWith` at all.
///
/// freezed offers three shapes and they put the substate name in three
/// different places, so matching only the flat one made every action written
/// with the deep form look as if it touched no state:
///
/// * `state.copyWith(logIn: …)`       → `logIn` — substate is the argument.
/// * `state.copyWith.logIn(email: …)` → `logIn.email` — substate is the method.
/// * `state.logIn.copyWith(email: …)` → `logIn.email` — substate is the target.
///
/// The deep form is the one frx's own templates emit (`add-field --action`,
/// the substate scaffolder), so it is the shape most actions in a generated
/// repo actually have.
List<StateWrite> _writesOf(MethodInvocation node) {
  final fields = node.argumentList.arguments
      .whereType<NamedArgument>()
      .toList();
  final target = node.target;

  if (target is PrefixedIdentifier && target.identifier.name == 'copyWith') {
    return _qualify(node.methodName.name, fields);
  }
  if (node.methodName.name != 'copyWith') return const [];
  if (target is PrefixedIdentifier)
    return _qualify(target.identifier.name, fields);
  // Flat: each argument names a substate, and its value is a whole replacement
  // — there is no field to qualify with. One write per argument, for the reason
  // [_qualify] states for the deep form and this branch used to contradict:
  // `copyWith(session: …, login: …)` writes both, and keeping only the first
  // understated it. `LogInWithEmailAction` is exactly that shape, and its flow
  // doc said it touched the session and not the login draft it clears.
  //
  // **Only on `state` itself.** Every other shape here names the receiver, and
  // this one did not: a reducer's `task.copyWith(title: t, done: true)` was read
  // as a write of two AppState substates called `title` and `done`. Harmless
  // while the branch kept one argument and wrong twice over once it kept all of
  // them — and `visitMethodInvocation` takes the first `copyWith` it sees, so a
  // local one earlier in the body shadowed the real write entirely.
  if (target is! SimpleIdentifier || target.name != 'state') return const [];
  return [for (final f in fields) (substate: f.name.lexeme, field: null)];
}

/// `logIn` + `email` → one [StateWrite] per field. Every field is listed: an
/// action setting two of them writes both, and dropping the rest would
/// understate it. With no named field the write replaces the whole substate.
List<StateWrite> _qualify(String substate, List<NamedArgument> fields) =>
    fields.isEmpty
    ? [(substate: substate, field: null)]
    : [for (final f in fields) (substate: substate, field: f.name.lexeme)];
