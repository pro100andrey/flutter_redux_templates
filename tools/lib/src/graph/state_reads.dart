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
Set<StateRead> stateReadsIn(AstNode node) {
  final v = _StateReadVisitor();
  node.accept(v);
  return v.reads;
}

class _StateReadVisitor extends RecursiveAstVisitor<void> {
  final reads = <StateRead>{};

  static const _receivers = {'state', '_state'};

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
