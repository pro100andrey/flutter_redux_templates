/// Reading the `Persistor` subclass: which substates it puts back on boot, and
/// which it reads back out to save.
///
/// It changes state without dispatching anything, so every other reader in the
/// graph is blind to it. In this template it is the only thing besides
/// `SetTokenAction` that can put a token in `session` — leaving it out made
/// "who can change `session.token`" answer confidently and incompletely.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// What the persistor touches, without a dispatch to follow.
class PersistorInfo {
  const PersistorInfo({
    required this.className,
    required this.restores,
    required this.reads,
  });

  final String className;

  /// Substates rebuilt in `readState()`.
  final Set<String> restores;

  /// Substates read in `persistDifference()`.
  final Set<String> reads;
}

/// The `Persistor` subclass [unit] declares, or null when it declares none.
///
/// Matched by superclass rather than by a fixed path, so renaming the file
/// does not quietly drop it. A class that merely *mentions* the type — a field
/// typed as one, a word in a comment — is not it.
PersistorInfo? persistorIn(CompilationUnit unit) {
  final v = _PersistorVisitor();
  unit.accept(v);
  final name = v.className;
  if (name == null) {
    return null;
  }
  return PersistorInfo(className: name, restores: v.restores, reads: v.reads);
}

class _PersistorVisitor extends RecursiveAstVisitor<void> {
  String? className;
  final restores = <String>{};
  final reads = <String>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final supertypes = [
      ?node.extendsClause?.superclass.toSource(),
      ...?node.implementsClause?.interfaces.map((i) => i.toSource()),
    ];
    if (!supertypes.any((t) => t.startsWith('Persistor'))) {
      return;
    }
    className = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (className == null) {
      return;
    }
    switch (node.name.lexeme) {
      case 'readState':
        // `AppState.initial().copyWith(theme: …, session: …)` — every named
        // argument is a substate being restored, not just the first.
        final v = _CopyWithArgs();
        node.body.accept(v);
        restores.addAll(v.fields);
      case 'persistDifference':
        // `newState.session`, `lastPersistedState?.theme` — the parameter names
        // come from the signature rather than being assumed, since they are the
        // author's to choose.
        final params =
            node.parameters?.parameters
                .map((p) => p.name?.lexeme)
                .nonNulls
                .toSet() ??
            const <String>{};
        if (params.isEmpty) {
          return;
        }
        // Off the tree, not off the text, for the reason the selector body
        // reader gives: a parameter named in a string literal is not a read of
        // it.
        node.body.accept(_ParamFieldReads(params, reads));
    }
  }
}

/// Fields read off one of [_params] — `newState.session`,
/// `lastPersistedState?.theme`.
///
/// Both spellings, because `?.` is a [PropertyAccess] while `.` on a plain name
/// is a [PrefixedIdentifier], and the persistor uses each.
class _ParamFieldReads extends RecursiveAstVisitor<void> {
  _ParamFieldReads(this._params, this._into);

  final Set<String> _params;
  final Set<String> _into;

  /// Lower-case initial only, as the pattern this replaced required: a field is
  /// not a nested type name.
  void _add(String name) {
    if (name.isNotEmpty && name[0] == name[0].toLowerCase()) {
      _into.add(name);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_params.contains(node.prefix.name)) {
      _add(node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && _params.contains(target.name)) {
      _add(node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }
}

/// Every named argument of every `copyWith(...)` in the visited subtree.
class _CopyWithArgs extends RecursiveAstVisitor<void> {
  final fields = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'copyWith') {
      for (final a in node.argumentList.arguments.whereType<NamedArgument>()) {
        fields.add(a.name.lexeme);
      }
    }
    super.visitMethodInvocation(node);
  }
}
