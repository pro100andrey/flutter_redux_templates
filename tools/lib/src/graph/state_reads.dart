/// Finding direct reads of the state — `state.session.token` — by shape.
///
/// The one reference the graph had no edge for. A selector's body reads
/// `_state.<substate>`, and the selector reader recorded the substate; a
/// reducer reads `state.console.projectId` on its way to deciding what to
/// write, and nothing recorded that at all. So "what breaks if I touch
/// `console.seq`" missed the action that reads it, and a selector nothing
/// reads was reported dead beside a reducer reading the same field directly —
/// with no way to say "dead selector, live field".
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../flow/flow_model.dart';

/// Every `<state>.<substate>[.<field>]` chain under [node].
///
/// The receiver is an identifier spelled `state` or `_state` — bare, as the
/// reducer's and the factory's getter and the facade's field are; reached as
/// a property, `store.state` in an `onInit` or `context.state`; or called,
/// `StoreProvider.state<AppState>(context)`. What follows it is the substate,
/// and the property read off *that*, when one is, is the field. A method
/// called on the substate reads the whole of it — `state.wait.isWaitingFor…`
/// — except `copyWith`, which is the nested write and the write reader's.
///
/// Names only. Whether `console` is a substate is the caller's to decide —
/// `state.copyWith.console(…)` arrives here as a read of `copyWith`, and the
/// caller drops it because `AppState` composes no such thing.
///
/// **And any name [node] binds to an `AppState`** — a parameter or a local
/// typed `AppState`, or a local initialised from the state:
/// `(AppState s) => s.todos.selected`, `final st = state; st.todos.count`.
/// Read by the spelling `state` alone, both were no read at all, and the
/// fields behind them were reported as read by nothing. Field reads only,
/// through such a name — see the visitor for why. By declaration, as
/// the facade names are (`facadesIn`): a name bound elsewhere and arriving
/// untyped is not seen, which costs a missed read, not an invented one.
Set<StateRead> stateReadsIn(AstNode node) {
  final names = _StateNames();
  node.accept(names);
  final v = _StateReadVisitor({..._StateReadVisitor.spelled, ...names.bound});
  node.accept(v);
  return v.reads;
}

/// The names in a subtree bound to an `AppState` — see [stateReadsIn].
class _StateNames extends RecursiveAstVisitor<void> {
  final bound = <String>{};

  static bool _isAppState(TypeAnnotation? type) =>
      type is NamedType && type.name.lexeme == 'AppState';

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    final name = node.name?.lexeme;
    if (name != null && _isAppState(node.type)) {
      bound.add(name);
    }
    super.visitRegularFormalParameter(node);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    final typed = _isAppState(node.type);
    for (final v in node.variables) {
      if (typed || _isState(v.initializer)) {
        bound.add(v.name.lexeme);
      }
    }
    super.visitVariableDeclarationList(node);
  }

  /// `state`, or `store.state` — the state itself, not a part of it.
  static bool _isState(Expression? e) => switch (e) {
    SimpleIdentifier(:final name) => _StateReadVisitor.spelled.contains(name),
    PrefixedIdentifier(:final identifier) => identifier.name == 'state',
    PropertyAccess(:final propertyName) => propertyName.name == 'state',
    _ => false,
  };
}

class _StateReadVisitor extends RecursiveAstVisitor<void> {
  _StateReadVisitor(this._receivers);

  final reads = <StateRead>{};

  /// How the state is spelled wherever it is not a local of ours.
  static const spelled = {'state', '_state'};

  final Set<String> _receivers;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (!_receivers.contains(node.name)) {
      return;
    }

    // The expression that *is* the state: the identifier itself when bare,
    // else the access or call it is the name of.
    final parent = node.parent;
    final Expression receiver;
    if (parent is PrefixedIdentifier && parent.identifier == node) {
      receiver = parent;
    } else if (parent is PropertyAccess && parent.propertyName == node) {
      receiver = parent;
    } else if (parent is MethodInvocation && parent.methodName == node) {
      receiver = parent;
    } else {
      receiver = node;
    }

    final (substate, access) = _accessOn(receiver);
    if (substate == null) {
      return;
    }

    final (field, _) = _accessOn(access!);
    if (field == null && _isCopyWithTarget(access)) {
      return; // `state.console.copyWith(…)` — a write, not a read
    }
    // Through a name of ours, only down to a field. The shape that binds
    // `AppState` to a parameter most often is an observer comparing two
    // states — `prev.session != next.session`, the template's own action
    // logger — and a whole-slice read counts as a read of every field, so
    // taking those would have kept every field of every slice alive and
    // emptied the dead-field list for good.
    if (field == null && !spelled.contains(node.name)) {
      return;
    }
    reads.add((substate: substate, field: field));
  }

  /// The property read off [target], and the node that read is, or nulls.
  static (String?, Expression?) _accessOn(Expression target) {
    final parent = target.parent;
    if (parent is PrefixedIdentifier && parent.prefix == target) {
      return (parent.identifier.name, parent);
    }
    if (parent is PropertyAccess && parent.target == target) {
      return (parent.propertyName.name, parent);
    }
    return (null, null);
  }

  static bool _isCopyWithTarget(Expression e) {
    final parent = e.parent;
    return parent is MethodInvocation &&
        parent.target == e &&
        parent.methodName.name == 'copyWith';
  }
}
