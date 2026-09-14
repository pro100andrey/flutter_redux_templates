/// Finding selector *reads* by shape, so a mention in a comment or a string
/// cannot be one.
///
/// The only edges that point *into* a selector come from here, and so the only
/// way to ask which ones nothing reads — which is the direction that invites
/// deleting working code when it is wrong.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../model/selector_shape.dart';

/// A dotted chain — `context.session.token`, `_state.logIn.email`.
///
/// The selector ids [node] calls, given an index of call site → node id.
///
/// Walks the AST rather than scanning source text. Text scanning counted a
/// selector named in a comment or quoted in a string as a read, which made
/// "something reads this" untrustworthy in exactly the direction that hides
/// dead code — and the files are parsed here anyway.
///
/// Two call shapes, because a selector is reached two ways:
/// `<substate>.<getter>` for the ones hanging off a substate, and a bare
/// `<getter>` for a composite declared on `Select` itself.
///
/// Still deliberately generous about the bare shape: a composite's name can
/// collide with a local of the same name, which files a selector as used when
/// it is not. That direction costs a missed cleanup; the other one — reporting
/// a live selector as dead — invites someone to delete working code.
///
/// [facades] are the names in the enclosing file that hold the facade itself —
/// see [facadesIn]. A read through one of those has a segment in front of it
/// that is neither a substate nor a view-model, and without them it is refused.
Set<String> selectorUsesIn(
  AstNode node,
  Map<String, String> index, {
  Set<String> facades = const {},
}) {
  final visitor = _SelectorUseVisitor(index, facades);
  node.accept(visitor);
  return visitor.used;
}

/// The names in [unit] that hold a selector facade — a variable, a field, a
/// parameter, and the facade types themselves.
///
/// **Why the chain rule cannot do without this.** `chats.unreadTotal` is a
/// selector read because the receiver heads the chain, which is how a class
/// mixing in `Selectors` reaches one. Put the facade in a variable first —
///
///     final selectors = _Reader(state);
///     final unread = selectors.chats.unreadTotal;
///
/// — and the same read has a segment in front of it, which
/// [_SelectorUseVisitor] accepted only when it was the literal `select` of the
/// spine that no longer exists. `app_tray.dart` reads `SelectChats.unreadTotal`
/// exactly that way and nothing else in the application does, so the selector
/// was reported as read by nobody: a live selector on the dead list, which is
/// the one direction that invites deleting working code.
///
/// Bound by *type*, never by name. A receiver is a facade because what it holds
/// mixes in `Selectors` — which is also why `vm.logIn.email` and
/// `_state.logIn.email` stay refused, and why widening the rule to "any
/// receiver" was not the fix: a substate's field and its selector are spelled
/// the same, so `state.session.token` would have counted as a read of
/// `SelectSession.token` and hidden every genuinely dead selector behind the
/// substate it reads.
///
/// Syntactic, like the rest of the graph: a name is bound to a facade when it
/// is *declared* as one or *constructed* from one in this unit. A facade
/// arriving from another file with no type annotation is not seen, and that
/// costs a missed cleanup rather than a wrong deletion.
Set<String> facadesIn(CompilationUnit unit) {
  final types = {SelectorShape.mixinType, SelectorShape.facadeType};

  final supertypes = _supertypesIn(unit);
  // `class A with Selectors {}` is a facade, and so is `class B extends A {}`.
  // Repeated until nothing new goes in — on any real unit that is one pass and
  // the check that stops it, and it is bounded by the class count either way.
  for (var changed = true; changed;) {
    changed = false;
    for (final entry in supertypes.entries) {
      if (types.contains(entry.key)) {
        continue;
      }
      if (entry.value.any(types.contains)) {
        types.add(entry.key);
        changed = true;
      }
    }
  }

  final names = _FacadeNameVisitor(types);
  unit.accept(names);
  // The types as well: `_Reader(state).chats.unreadTotal` names no variable at
  // all, and the head of that chain is the type.
  return {...types, ...names.names};
}

/// Every class and mixin in a unit and what it is built from, so [facadesIn]
/// can ask which of them reach `Selectors`.
///
/// Read off `unit.declarations` rather than by a visitor: a class or a mixin is
/// a top-level member and nothing else, so walking the whole tree could only
/// ever find what the declaration list already holds.
Map<String, List<String>> _supertypesIn(CompilationUnit unit) {
  final out = <String, List<String>>{};
  for (final decl in unit.declarations) {
    if (decl is ClassDeclaration) {
      out[decl.namePart.typeName.lexeme] = [
        ?decl.extendsClause?.superclass.name.lexeme,
        ...?decl.withClause?.mixinTypes.map((t) => t.name.lexeme),
        ...?decl.implementsClause?.interfaces.map((t) => t.name.lexeme),
      ];
    } else if (decl is MixinDeclaration) {
      out[decl.name.lexeme] = [
        ...?decl.onClause?.superclassConstraints.map((t) => t.name.lexeme),
        ...?decl.implementsClause?.interfaces.map((t) => t.name.lexeme),
      ];
    }
  }
  return out;
}

/// The names bound to one of [types] — declared as one, or assigned one.
class _FacadeNameVisitor extends RecursiveAstVisitor<void> {
  _FacadeNameVisitor(this.types);

  final Set<String> types;
  final names = <String>{};

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    final annotated = _named(node.type);
    for (final v in node.variables) {
      if (annotated || _constructs(v.initializer)) {
        names.add(v.name.lexeme);
      }
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    final name = node.name?.lexeme;
    if (name != null && _named(node.type)) {
      names.add(name);
    }
    super.visitRegularFormalParameter(node);
  }

  bool _named(TypeAnnotation? type) =>
      type is NamedType && types.contains(type.name.lexeme);

  /// Whether [expression] builds a facade. An unresolved parse cannot tell a
  /// constructor from a function call, so `_Reader(state)` arrives as a method
  /// invocation; the name being a facade type is what settles it.
  bool _constructs(Expression? expression) => switch (expression) {
    MethodInvocation(target: null) => types.contains(
      expression.methodName.name,
    ),
    InstanceCreationExpression() => types.contains(
      expression.constructorName.type.name.lexeme,
    ),
    _ => false,
  };
}

/// Finds selector reads by shape, so a mention in a comment or a string cannot
/// be one.
class _SelectorUseVisitor extends RecursiveAstVisitor<void> {
  _SelectorUseVisitor(this.index, this.facades);

  final Map<String, String> index;

  /// What may stand in front of a substate hop — see [facadesIn]. `select` is
  /// in every set of them: a project scaffolded before the spine collapsed
  /// still reaches the facade through it, and it never named anything else.
  final Set<String> facades;

  final used = <String>{};

  bool _isFacade(String name) => name == 'select' || facades.contains(name);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _chain(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _chain(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A composite reached by its bare name — `if (canEnterApp)`. Skipped when
    // it is a segment of a chain, which `_chain` has already judged as a whole.
    final parent = node.parent;
    if (parent is PrefixedIdentifier || parent is PropertyAccess) {
      return;
    }
    final id = index[node.name];
    if (id != null) {
      used.add(id);
    }
  }

  /// Judges a dotted access by where the receiver sits in its chain.
  ///
  /// `logIn.email` is a selector: the receiver heads the chain, which is how a
  /// class mixing in `Selectors` reaches one. `state.select.logIn.email` is the
  /// same selector through the facade. `vm.logIn.email` and
  /// `_state.logIn.email` are not — a view-model field and the substate behind
  /// the selector. Text scanning could not tell the three apart without listing
  /// the receivers to refuse; the position in the chain says it outright.
  void _chain(Expression node) {
    // Only the outermost node of a chain: an inner one is judged with it.
    final parent = node.parent;
    if ((parent is PropertyAccess && parent.target == node) ||
        (parent is PrefixedIdentifier && parent.prefix == node)) {
      return;
    }
    final parts = _segments(node);
    if (parts == null) {
      return;
    }
    for (var i = 0; i + 1 < parts.length; i++) {
      // The receiver either heads the chain, or the facade is in front of it —
      // `…select.logIn.email`, `selectors.logIn.email`.
      if (i > 0 && !_isFacade(parts[i - 1])) {
        continue;
      }
      final id = index['${parts[i]}.${parts[i + 1]}'];
      if (id != null) {
        used.add(id);
      }
    }
    // `state.select.canEnterApp` — a composite behind the facade.
    for (var i = 1; i < parts.length; i++) {
      if (!_isFacade(parts[i - 1])) {
        continue;
      }
      final id = index[parts[i]];
      if (id != null) {
        used.add(id);
      }
    }
  }

  /// The chain as plain names, or null when it is rooted in something that is
  /// not one — `items[0].logIn.email`, `of(context).logIn.email`. Those are
  /// reads frx cannot attribute, and guessing at them is what the graph's
  /// blind-spot discipline exists to avoid.
  List<String>? _segments(Expression node) => switch (node) {
    // `this` is transparent: inside a class mixing in `Selectors`,
    // `this.logIn.email` is the same read as the bare `logIn.email`, and
    // refusing it would report a live selector as dead.
    ThisExpression() => const [],
    SimpleIdentifier() => [node.name],
    PrefixedIdentifier() => [node.prefix.name, node.identifier.name],
    // `_Reader(state).chats.unreadTotal` — the facade built where it is read,
    // which the tray does twice. Only a facade type roots a chain this way;
    // `of(context).logIn.email` stays unreadable, since what `of` returns is
    // exactly what an unresolved parse cannot say.
    MethodInvocation(target: null) =>
      facades.contains(node.methodName.name) ? [node.methodName.name] : null,
    InstanceCreationExpression() =>
      facades.contains(node.constructorName.type.name.lexeme)
          ? [node.constructorName.type.name.lexeme]
          : null,
    // A cascade section (`thing..field = 1`) is a PropertyAccess with no
    // target. Falling back to the node itself recurses on it forever; there is
    // no receiver to name, so the chain is simply unreadable.
    PropertyAccess(target: final target?) => switch (_segments(target)) {
      final head? => [...head, node.propertyName.name],
      _ => null,
    },
    _ => null,
  };
}
