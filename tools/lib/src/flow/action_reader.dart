/// Reading the action classes off a file: name, mixins, async-ness, the fields
/// each writes, cascading dispatches, and whether it throws a `UserException`.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart' show classesIn;
import 'dispatch_visitor.dart';
import 'flow_model.dart';

/// What the *main* action declared in [unit] does — the first one, which by
/// the naming convention is the one the file is named for.
///
/// [file] names the class when the unit declares none, and is carried for
/// click-to-open in the viewer.
ActionInfo readActionInfo(CompilationUnit unit, File file) =>
    readActionsIn(unit, file).first;

/// Every action class declared in [unit], in source order, each read on its
/// own.
///
/// **One entry per class, not one per file.** A file under `actions/` holds
/// its public action and, often enough, the private steps it dispatches on the
/// way — `_ProbeStarted` beside `ProbeEmbedSpeedAction` — or a second public
/// one that belongs with it, `CloseTaskAction` beside `OpenTaskAction`. Read
/// as one, the file blended them: one class's `with` clause overwrote the
/// other's, every `reduce()` contributed to one `isAsync`, and the dispatches
/// of all of them were credited to the first. Read as one *and keyed on the
/// file*, the graph could not give the second class a node at all, so a
/// dispatch of it was a gap and the class itself was invisible.
///
/// Which classes are actions is decided by shape, not by position: a class is
/// one when it extends something ending in `Action` (`Action`,
/// `ReduxAction<AppState>`) or is itself named `…Action`, and is not abstract.
/// A helper class in the same file is neither, and is left alone. A file where
/// nothing matches falls back to its first class, which is what every reader
/// assumed before, and a file with no class at all — the template's own
/// `mixin … on Action` idiom — yields one entry with [ActionInfo.declaresClass]
/// false so a caller can skip it.
///
/// The list is never empty.
///
/// [composed] is the substates `AppState` composes, when the caller knows
/// them: a `copyWith` on anything else — `payload.todo.copyWith(done: true)`
/// — is a local value being built, not a write, and is left out. Null keeps
/// every write the shapes match.
List<ActionInfo> readActionsIn(
  CompilationUnit unit,
  File file, {
  Set<String>? composed,
}) {
  final classes = classesIn(unit).toList();
  var actions = [
    for (final c in classes)
      if (_isActionClass(c)) c,
  ];
  if (actions.isEmpty && classes.isNotEmpty) {
    actions = [classes.first];
  }

  if (actions.isEmpty) {
    return [
      ActionInfo(
        className: p.basenameWithoutExtension(file.path),
        declaresClass: false,
        file: file.path,
      ),
    ];
  }

  final actionSet = actions.toSet();
  return [
    for (final c in actions) _readClass(c, actionSet, unit, file, composed),
  ];
}

/// Whether [c] is an action by shape — see [readActionsIn].
bool _isActionClass(ClassDeclaration c) {
  if (c.abstractKeyword != null) {
    return false;
  }
  final name = c.namePart.typeName.lexeme;
  if (name.endsWith('Action')) {
    return true;
  }
  final base = c.extendsClause?.superclass.name.lexeme;
  return base != null && base.endsWith('Action');
}

/// Reads [c] together with the rest of its file, minus the other actions.
///
/// The file is the unit of reading, not the class: a reducer that calls a
/// top-level `_signUp()` three lines down throws whatever that throws, and a
/// mixin declared beside the class carries its shared `reduce()`. What is
/// left out is exactly the other action classes, whose members are theirs,
/// and a mixin this class does not apply.
ActionInfo _readClass(
  ClassDeclaration c,
  Set<ClassDeclaration> actions,
  CompilationUnit unit,
  File file,
  Set<String>? composed,
) {
  // Off the declaration, not the visitor: a helper class read along with
  // this one has a `with` clause of its own, and it is not this action's.
  final mixins = [
    for (final m in c.withClause?.mixinTypes ?? const <NamedType>[])
      m.toSource(),
  ];

  final v = _ActionVisitor(composed);
  c.accept(v);
  for (final d in unit.declarations) {
    if (d == c || actions.contains(d)) {
      continue;
    }
    if (d is MixinDeclaration && !mixins.contains(d.name.lexeme)) {
      continue;
    }
    d.accept(v);
  }

  final at = unit.lineInfo.getLocation(c.namePart.typeName.offset);
  return ActionInfo(
    className: c.namePart.typeName.lexeme,
    mixins: mixins,
    isAsync: v.isAsync,
    writes: v.writes,
    dispatches: v.dispatches,
    throwsUserException: v.throwsUserException,
    file: file.path,
    line: at.lineNumber,
    column: at.columnNumber,
  );
}

/// Reads one action class: async-ness, the field it writes, cascading
/// dispatches, and whether it throws a `UserException`.
class _ActionVisitor extends RecursiveAstVisitor<void> {
  _ActionVisitor(this._composed);

  /// See [readActionsIn].
  final Set<String>? _composed;

  var isAsync = false;
  List<DispatchStep> dispatches = const [];

  /// Every write found, in source order, once each.
  final _writes = <StateWrite>{};

  /// What the action writes: every write found, except a field write of a
  /// substate the action also replaces whole — `state.copyWith(todos:
  /// state.todos.copyWith(query: q))` replaces `todos`, and saying
  /// `todos.query` beside it adds nothing.
  List<StateWrite> get writes {
    final whole = {
      for (final w in _writes)
        if (w.field == null) w.substate,
    };
    return [
      for (final w in _writes)
        if (w.field == null || !whole.contains(w.substate)) w,
    ];
  }
  var throwsUserException = false;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // `isAsync` is a fact about the reducer — whether the action makes the
    // round trip a diagram should show — so it stays keyed on `reduce`.
    if (node.name.lexeme == 'reduce') {
      isAsync = node.body.isAsynchronous;
    }

    // The dispatches are not. An action that dispatches from `before()`,
    // `after()`, or a method a mixin requires it to override cascades exactly
    // as one that dispatches from its reducer, and reading only the reducer
    // left the dispatched action looking like one nothing reaches — reported
    // in the orphan list, which is the one place frx says "you can delete
    // this".
    _collectDispatches(node.body);
    super.visitMethodDeclaration(node);
  }

  /// A top-level function of the file, by the same reasoning one step out:
  /// `void _kick(Action a) => a.dispatch(RefreshAction());` called from
  /// `reduce()` cascades exactly as the call it replaces, and read only off
  /// methods it left `RefreshAction` on the orphan list. A function nested in
  /// a method is already inside that method's body.
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      _collectDispatches(node.functionExpression.body);
    }
    super.visitFunctionDeclaration(node);
  }

  void _collectDispatches(FunctionBody body) {
    final v = DispatchVisitor();
    body.accept(v);
    if (v.steps.isNotEmpty) {
      dispatches = [...dispatches, ...v.steps];
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Every write, not the first. "First write wins" assumed an action writes
    // one substate, and it hid real writes twice over: a local
    // `payload.todo.copyWith(done: true)` ahead of the
    // `state.copyWith.todos(…)` was taken as the write and the real one was
    // dropped, and an action whose branches write different slices kept only
    // the first branch's. A `copyWith` on a value `AppState` does not
    // compose is building a local, and is left out when that is known.
    final composed = _composed;
    for (final w in _writesOf(node)) {
      if (composed == null || composed.contains(w.substate)) {
        _writes.add(w);
      }
    }
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

  if (node.methodName.name != 'copyWith') {
    return const [];
  }

  if (target is PrefixedIdentifier) {
    return _qualify(target.identifier.name, fields);
  }
  // Flat: each argument names a substate, and its value is a whole replacement
  // — there is no field to qualify with. One write per argument, for the reason
  // [_qualify] states for the deep form and this branch used to contradict:
  // `copyWith(session: …, login: …)` writes both, and keeping only the first
  // understated it. `LogInWithEmailAction` is exactly that shape, and its flow
  // doc said it touched the session and not the login draft it clears.
  //
  // **Only on `state` itself.** Every other shape here names the receiver, and
  // this one did not: a reducer's `task.copyWith(title: t, done: true)` was
  // read as a write of two AppState substates called `title` and `done`.
  // Harmless while the branch kept one argument and wrong twice over once it
  // kept all of them — and while `visitMethodInvocation` took the first
  // `copyWith` it saw, a local one earlier in the body shadowed the real
  // write entirely.
  if (target is! SimpleIdentifier || target.name != 'state') {
    return const [];
  }

  return [for (final f in fields) (substate: f.name.lexeme, field: null)];
}

/// `logIn` + `email` → one [StateWrite] per field. Every field is listed: an
/// action setting two of them writes both, and dropping the rest would
/// understate it. With no named field the write replaces the whole substate.
List<StateWrite> _qualify(String substate, List<NamedArgument> fields) =>
    fields.isEmpty
    ? [(substate: substate, field: null)]
    : [for (final f in fields) (substate: substate, field: f.name.lexeme)];
