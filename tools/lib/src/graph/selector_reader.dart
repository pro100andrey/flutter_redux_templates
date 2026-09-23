/// Reading the selectors a facade *declares*: the `Select<Pascal>` extension
/// types in `selectors.dart`, and what each getter touches.
///
/// Selectors are what makes deleting an action break something far away:
/// `isWaitingForType<ForgotPasswordAction>()` names the class with no import
/// of its own to follow, so nothing else in the graph records the reference.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../flow/flow_model.dart';
import '../model/selector_shape.dart';
import 'state_reads.dart';

/// One getter on a `Select<Pascal>` extension type — or one method, which is
/// a selector taking arguments and is read the same way; [getter] is then the
/// method's name.
class SelectorGetter {
  SelectorGetter(this.type, this.ownerType, this.getter, this.offset);

  /// The type that *declares* the getter — the node's identity.
  final String type;

  /// The type the getter is *called* on, which is not always [type]: an
  /// `extension X on SelectLogIn` contributes to `SelectLogIn`, so its getters
  /// are reached as `select.logIn.<getter>` however `X` is named.
  final String ownerType;

  final String getter;

  /// The node id this getter is filed under — the declaring type, not the type
  /// it is called on, so two extensions on one selector stay distinct.
  String get id => 'selector:$type.$getter';

  /// Character offset of the getter's name, for the node's line/column.
  final int offset;

  /// What the body reads off the state, down to the field: `session.token`,
  /// or `session` alone when the whole substate is taken. The field is what
  /// lets "who touches `session.token`" be answered on the reading side too —
  /// recorded by substate alone, every selector on a slice read as reading
  /// all of it, and focusing one field of a fifty-field slice returned the
  /// slice.
  final reads = <StateRead>{};

  /// The substates [reads] names.
  Set<String> get readsFields => {for (final r in reads) r.substate};

  final waitsForActions = <String>{};

  /// Bare identifiers in the body, some of which name a getter alongside it.
  final siblings = <String>{};

  /// The getter's body, scanned for the selectors it calls once every selector
  /// is known (a composite can name one declared below it). Held as AST: a
  /// selector quoted in a string is not a read of it.
  FunctionBody? body;
}

/// Every selector declared in [unit], with each one's sibling reads folded
/// in.
///
/// The single entry point, because the fold has to happen after the whole
/// file is visited — an extension can be declared above the type it extends —
/// and a caller that has to remember a second call would eventually not.
List<SelectorGetter> readSelectorGetters(CompilationUnit unit) {
  final v = _SelectorVisitor();
  unit.accept(v);
  // Grouped by owning type rather than by declaration: an
  // `extension X on SelectLogIn` contributes getters *to* `SelectLogIn`, so
  // its siblings are that type's getters and not its own.
  final byOwner = <String, Map<String, SelectorGetter>>{};
  for (final s in v.selectors) {
    (byOwner[s.ownerType] ??= {})[s.getter] = s;
  }

  byOwner.values.forEach(_inheritFromSiblings);
  return v.selectors;
}

/// The `Select<Pascal>` type each hop on the facade's spine returns, and the
/// name of the hop — `SelectLogIn get logIn => …` on `mixin Selectors` is
/// `SelectLogIn` → `logIn`.
///
/// Where a selector type's substate is *stated*. Casing the type name back
/// into a field cannot be trusted to agree with how the field is spelled:
/// `SelectECommerce` read back as `ecommerce`, not `eCommerce`, and every
/// selector on the slice belonged to no substate — reached as a bare name no
/// consumer writes, and reported as read by nothing.
Map<String, String> spineHopsIn(CompilationUnit unit) => {
  for (final d in unit.declarations.whereType<MixinDeclaration>())
    if (d.name.lexeme == SelectorShape.mixinType)
      for (final m in d.body.members.whereType<MethodDeclaration>())
        if (m.isGetter)
          if (m.returnType case NamedType(:final name)
              when SelectorShape.isSelectorType(name.lexeme) &&
                  !SelectorShape.isFacadeSpine(name.lexeme))
            name.lexeme: m.name.lexeme,
};

/// Folds a sibling getter's reads into the one that calls it.
///
/// `bool get isAvailable => token != null;` reads no state of its own, but
/// `token` next to it does — so it reads that substate just the same. Without
/// this it lands in `unresolved` as an unreadable composite, which is worse
/// than a missing edge: a blind-spot list that cries wolf gets ignored, and
/// then the real gaps go with it.
void _inheritFromSiblings(Map<String, SelectorGetter> group) {
  // Bounded by the group size: each pass can only propagate one hop, and a
  // reference cycle simply stops adding anything.
  for (var pass = 0; pass < group.length; pass++) {
    var changed = false;
    for (final s in group.values) {
      for (final name in s.siblings) {
        final other = group[name];
        if (other == null || identical(other, s)) {
          continue;
        }
        changed |= _merge(s.reads, other.reads);
        changed |= _merge(s.waitsForActions, other.waitsForActions);
      }
    }

    if (!changed) {
      break;
    }
  }
}

/// Adds [from] to [into], reporting whether anything was new — `Set.addAll`
/// returns void, and the fixpoint loop needs to know when to stop.
bool _merge<T>(Set<T> into, Set<T> from) {
  final before = into.length;
  into.addAll(from);
  return into.length != before;
}

/// Collects the `Select*` extension types and what each getter touches.
class _SelectorVisitor extends RecursiveAstVisitor<void> {
  final selectors = <SelectorGetter>[];

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _collect(node);
    super.visitExtensionTypeDeclaration(node);
  }

  /// A composite selector — `extension SelectComposites on Selectors` — reads
  /// other selectors instead of the state.
  ///
  /// Keyed on what it extends, not on what it is called: the name is free, and
  /// missing these would report every selector a composite reads as read by
  /// nobody. It is an `extension`, not an `extension type`, so the visit above
  /// never sees it.
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _collect(node);
    super.visitExtensionDeclaration(node);
  }

  /// Records the getters [node] declares, if it declares a selector at all.
  ///
  /// The spine's *own* body is skipped — `SelectLogIn get logIn => …` on
  /// `Select` is a hop onto a selector, not one. An `extension … on Select` is
  /// kept: those getters are composites, reached by a bare name. An unnamed
  /// extension is dropped here rather than in [SelectorShape], because the
  /// placement rules can report one without naming it but a graph node cannot
  /// exist without an id.
  void _collect(AstNode node) {
    final decl = SelectorShape.of(node);
    if (decl == null || (decl.declaresOwner && decl.onFacadeSpine)) {
      return;
    }

    final type = decl.name;
    if (type == null) {
      return;
    }

    // Every getter **and method**. `String? byIndex(int i) =>
    // _state.todos.items[i];` is a selector with an argument, and read as
    // getters alone it was not there at all: the field only it reads was
    // reported as read by nothing, and a getter only its body uses as dead —
    // both with a live action calling `todos.byIndex(0)`. A setter or an
    // operator is not a selector, and a static member is not reached through
    // the facade.
    for (final m in decl.members.whereType<MethodDeclaration>()) {
      if (m.isSetter || m.isOperator || m.isStatic) {
        continue;
      }

      final s = SelectorGetter(type, decl.owner, m.name.lexeme, m.name.offset)
        ..reads.addAll(stateReadsIn(m.body));
      m.body.accept(_BodyReader(s));
      s.body = m.body;
      selectors.add(s);
    }
  }
}

/// What one getter's body touches, read off the tree rather than off its text.
///
/// Three regexes over `m.body.toSource()` stood here, and text cannot tell a
/// string literal from code. Reproduced with the product's own commands on a
/// fresh project — `frx add-selector session label -t String -e "'token'"` —
/// after which `SelectSession.label`, whose whole body is the *string*
/// `'token'`, was reported as reading the session slice: the bare-identifier
/// scrape matched `token` inside the quotes and the sibling fold handed it the
/// neighbouring `token` getter's reads. In the same output the reason another
/// selector was dead changed with it, and where such a phantom reader is itself
/// read, a dead selector is reported alive.
///
/// [SelectorGetter.body] already stated the rule — "a selector quoted in a
/// string is not a read of it" — for the half of this reader that was already
/// a visitor (`selectorUsesIn`). This is the other half saying the same thing.
class _BodyReader extends RecursiveAstVisitor<void> {
  _BodyReader(this._into);

  final SelectorGetter _into;

  /// The two spellings of the state receiver. `_state` is the field of an
  /// `extension type Select…`; `state` is the getter on the `Selectors` mixin,
  /// which is what a composite in `extension SelectComposites on Selectors`
  /// has to use — it has no `_state` to reach. The old pattern knew only the
  /// first, so every composite reading state directly was a blind spot.
  ///
  /// The reads themselves are [stateReadsIn]'s; what this reader keeps is
  /// knowing the receiver is not a sibling.
  static const _stateReceivers = {'_state', 'state'};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;

    // The right half of `a.b` — a name reached through something, not one
    // standing on its own. This is what the old "not preceded by a dot"
    // lookbehind expressed.
    if (parent is PrefixedIdentifier && parent.identifier == node) {
      return;
    }

    if (parent is PropertyAccess && parent.propertyName == node) {
      return;
    }

    if (parent is MethodInvocation && parent.methodName == node) {
      _waitedOn(parent);
      return;
    }

    if (_stateReceivers.contains(node.name)) {
      return;
    }

    // Lower-case initial only, which is what keeps a type name out of the
    // sibling set — the same filter the old pattern's `[a-z]` applied.
    final name = node.name;
    if (name.isNotEmpty && name[0] == name[0].toLowerCase()) {
      _into.siblings.add(name);
    }
  }

  /// The action type in `…isWaitingForType<LogInWithEmailAction>()`.
  void _waitedOn(MethodInvocation node) {
    if (node.methodName.name != 'isWaitingForType') {
      return;
    }

    for (final arg
        in node.typeArguments?.arguments ?? const <TypeAnnotation>[]) {
      if (arg is NamedType) {
        _into.waitsForActions.add(arg.name.lexeme);
      }
    }
  }
}
