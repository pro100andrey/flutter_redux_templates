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

    // Keyed by canonical path: a region reachable through two slots is one
    // region, and a cycle between two connectors is a stack overflow.
    final seen = <String>{};

    void walk(File file, String? owner) {
      if (!seen.add(p.canonicalize(file.path))) return;

      final unit = sourceIndex.unitFor(file);

      final vm = _VmVisitor();
      unit.accept(vm);

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

/// Collects every `dispatch*(...)` inside whatever it is pointed at.
///
/// [_root] bounds the upward walks (condition / trigger) so they never escape
/// the subtree we were handed.
class _DispatchVisitor extends RecursiveAstVisitor<void> {
  _DispatchVisitor([this._root]);

  final AstNode? _root;
  final steps = <DispatchStep>[];

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
    }
    super.visitMethodInvocation(node);
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
class _VmVisitor extends RecursiveAstVisitor<void> {
  final useCases = <UseCase>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == '_Vm') {
      for (final a in node.argumentList.arguments.whereType<NamedArgument>()) {
        final v = _DispatchVisitor(a.argumentExpression);
        a.argumentExpression.accept(v);
        if (v.steps.isEmpty) continue;
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
