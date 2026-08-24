/// Reading a `with` clause as a *chain*, not a set.
///
/// Dart gives a class one `after()` — the last mixin's. Every mixin before it
/// gets its own `after()` run only if the ones after it call `super.after()`.
/// So the order of a `with` clause and the presence of a `super` call are one
/// fact, and the audit needs both halves of it:
///
///     class LoadAction extends Action with WaitingAction, NonReentrant {}
///
/// compiles, analyzes clean, and never lowers the wait barrier, because
/// `NonReentrant.after()` releases its lock and returns.
///
/// Both readings are syntactic, which is the bound worth naming: frx parses
/// without resolution, so a mixin here is the name as written. That is exact for
/// the question asked — whether *this* source puts *this* name after that one —
/// and blind to a mixin reached through an alias or an intermediate base.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'source_index.dart';

/// A class, the mixins it applies, and the hooks it overrides itself.
class MixinApplication {
  const MixinApplication(this.className, this.mixins, this.hooks);

  final String className;

  /// Bare mixin names in written order — `Retry<AppState>` reads as `Retry`,
  /// because the chain is about which mixin, not how it is parameterised.
  final List<String> mixins;

  /// `before()`/`after()` the class declares in its own body.
  ///
  /// The end of the chain, ahead of every mixin: a class member wins over the
  /// whole `with` clause. So a correctly-ordered clause over a correctly
  /// chaining mixin is still dead if the action writes its own `after()` and
  /// forgets `super.after()` — measured, and no more visible than the ordering
  /// bug was.
  final List<HookOverride> hooks;

  /// Every mixin applied after [name], or empty when [name] is absent or last.
  ///
  /// The direction that matters: these are the ones whose `after()` runs
  /// *instead of* [name]'s, not the ones [name] shadows.
  Iterable<String> after(String name) {
    final at = mixins.indexOf(name);
    return at < 0 ? const [] : mixins.skip(at + 1);
  }
}

/// One `before()`/`after()` override, on a mixin or on a class.
class HookOverride {
  const HookOverride(this.name, {required this.chainsSuper});

  /// `before` or `after`.
  final String name;

  /// Whether the body calls `super.<name>()` anywhere — including `await
  /// super.before()` and an `=> super.after()` arrow body.
  final bool chainsSuper;
}

abstract final class MixinChainReader {
  /// Every class in [file] that applies at least one mixin.
  ///
  /// Only those: a class with no `with` clause has no chain to end, because
  /// `ReduxAction.before()` and `after()` are empty.
  static List<MixinApplication> applicationsIn(File file) => [
    for (final c in sourceIndex.unitFor(file).declarations)
      if (c is ClassDeclaration && c.withClause != null)
        MixinApplication(c.namePart.typeName.lexeme, [
          for (final m in c.withClause!.mixinTypes)
            m.toSource().split('<').first.trim(),
        ], _hooksIn(c.body.members)),
  ];

  /// The lifecycle hooks the mixin called [name] in [file] overrides, or an
  /// empty list when the file declares no such mixin.
  ///
  /// Only `before` and `after`: they are the two async_redux calls once per
  /// action with no return value to thread, which is what makes a missing
  /// `super` invisible rather than a type error.
  static List<HookOverride> hooksOf(File file, String name) {
    for (final d in sourceIndex.unitFor(file).declarations) {
      if (d is! MixinDeclaration) continue;
      // `name`/`body.members`, not the `namePart` spelling `declarations.dart`
      // uses for a class: analyzer 14 gives a mixin a plain name token.
      if (d.name.lexeme != name) continue;
      return _hooksIn(d.body.members);
    }
    return const [];
  }

  /// The `before()`/`after()` declarations among [members], with whether each
  /// passes the chain on.
  static List<HookOverride> _hooksIn(Iterable<ClassMember> members) => [
    for (final member in members)
      if (member is MethodDeclaration &&
          const {'before', 'after'}.contains(member.name.lexeme))
        HookOverride(
          member.name.lexeme,
          // A visitor, not a `contains('super.after(')` over the source: a
          // comment explaining why the call is *missing* would otherwise read
          // as the call being present, which is the one direction of error
          // that hides the bug.
          chainsSuper: _CallsSuper(member.name.lexeme).found(member.body),
        ),
  ];
}

/// Whether a body contains `super.<name>(…)`.
class _CallsSuper extends RecursiveAstVisitor<void> {
  _CallsSuper(this.name);

  final String name;
  bool _found = false;

  bool found(FunctionBody body) {
    body.accept(this);
    return _found;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target is SuperExpression && node.methodName.name == name) {
      _found = true;
    }
    super.visitMethodInvocation(node);
  }
}
