/// Reading one action class off its file: name, mixins, async-ness, the fields
/// it writes, cascading dispatches, and whether it throws a `UserException`.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import 'dispatch_visitor.dart';
import 'flow_model.dart';

/// What the action declared in [unit] does.
///
/// [file] names the class when the unit declares none, and is carried for
/// click-to-open in the viewer.
ActionInfo readActionInfo(CompilationUnit unit, File file) {
  final v = _ActionVisitor();
  unit.accept(v);
  return ActionInfo(
    className: v.className ?? p.basenameWithoutExtension(file.path),
    declaresClass: v.className != null,
    mixins: v.mixins,
    isAsync: v.isAsync,
    writes: v.writes,
    dispatches: v.dispatches,
    throwsUserException: v.throwsUserException,
    file: file.path,
  );
}

/// Reads one action class: name, mixins, async-ness, the field it writes,
/// cascading dispatches, and whether it throws a `UserException`.
class _ActionVisitor extends RecursiveAstVisitor<void> {
  String? className;
  List<String> mixins = const [];
  var isAsync = false;
  List<StateWrite> writes = const [];
  List<DispatchStep> dispatches = const [];
  var throwsUserException = false;

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
    final v = DispatchVisitor();
    node.body.accept(v);
    if (v.steps.isNotEmpty) {
      dispatches = [...dispatches, ...v.steps];
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // First write wins: an action that branches still writes one substate, and
    // the outermost call is visited first, so a nested copy cannot shadow it.
    if (writes.isEmpty) {
      writes = _writesOf(node);
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
  // kept all of them — and `visitMethodInvocation` takes the first `copyWith`
  // it sees, so a local one earlier in the body shadowed the real write
  // entirely.
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
