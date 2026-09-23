import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../redux/ast_edit.dart';

/// Renaming a substate's `AppState` field — `connectivity`, `theme` — in the
/// places that name *the slot*, and nowhere else.
///
/// The type names a rename carries (`ThemeState`, `SelectTheme`) are
/// distinctive: a token spelling one of them is one of them. The field is not.
/// `theme` is a Flutter `MaterialApp` parameter, the conventional name of every
/// `Theme.of(context)` local, and a view-model field in the log-in connector;
/// `connectivity` is the service `dependencies.dart` holds. Renaming every
/// token that spelled it — which is what `rename theme appearance` did — wrote
/// `MaterialApp(appearance: …)` and renamed widget locals, 87 analyzer errors
/// out of a command that reported success.
///
/// Without a resolver the tree cannot say which declaration a name binds to,
/// but it can say enough:
///
/// * a **declaration** named the field is the slot when its declared type is
///   one of the renamed types — `required ThemeState theme` on `AppState`,
///   `SelectTheme get theme` on the facade. Any other declaration of that name
///   is somebody else's, and it *shadows*: a bare reference inside its scope
///   means it, not the slot;
/// * a **bare reference** (`theme.mode` in a connector mixing in `Selectors`)
///   is the slot unless a shadowing declaration encloses it;
/// * a **member access** (`state.theme`, `copyWith.theme(…)`) is the slot
///   unless the file declares the name for itself — `vm.theme` sits beside a
///   view-model with a `theme` field, and nothing short of a resolver tells the
///   two apart, so the file's own declaration wins;
/// * a **named-argument label** is the slot only in an `AppState(…)` call or a
///   `copyWith(…)` — anywhere else (`MaterialApp(theme: …)`, `_Vm(theme: …)`)
///   it names a parameter of something that is not `AppState`.
///
/// What it misses, it leaves, and `dart analyze` names it: an unrenamed access
/// is a compile error pointing at the line, where a wrongly renamed one in a
/// widget is a compile error in a file the rename had no business touching.
class FieldRename {
  const FieldRename({
    required this.from,
    required this.to,
    required this.ownerTypes,
  });

  /// The field as it is spelled now, and as it will be.
  final String from;
  final String to;

  /// The types whose declarations carry the slot — the state class and its
  /// selector type — spelled as they are *before* the rename.
  final Set<String> ownerTypes;

  /// The edits [unit] needs to follow the field.
  List<Edit> of(CompilationUnit unit) {
    final scan = _Scan(from, ownerTypes);
    unit.accept(scan);

    final edits = <Edit>[
      for (final t in scan.renamedDeclarations)
        Edit.replace(t.offset, t.end, to),
    ];
    final declared = {
      ...scan.renamedDeclarations.map((t) => t.offset),
      ...scan.shadows.map((s) => s.nameOffset),
    };
    final fileShadowed = scan.shadows.isNotEmpty;

    for (var token = unit.beginToken; !token.isEof; token = token.next!) {
      if (token.lexeme != from || declared.contains(token.offset)) {
        continue;
      }
      if (token.type != TokenType.IDENTIFIER) {
        continue;
      }

      final previous = token.previous;
      final next = token.next;
      final bool renamed;
      if (next?.lexeme == ':' &&
          (previous?.lexeme == '(' || previous?.lexeme == ',')) {
        final invoked = scan.invokedAround(token.offset);
        renamed =
            invoked == 'AppState' || (invoked == 'copyWith' && !fileShadowed);
      } else if (const {'.', '?.', '..', '?..'}.contains(previous?.lexeme)) {
        final target = previous?.previous;
        renamed =
            !fileShadowed &&
            target?.lexeme != 'current' &&
            // `Foo.theme` is a static member of a type, never the slot.
            !(target?.type == TokenType.IDENTIFIER &&
                _startsUpper(target!.lexeme));
      } else {
        renamed = !scan.shadows.any((s) => s.covers(token.offset));
      }

      if (renamed) {
        edits.add(Edit.replace(token.offset, token.end, to));
      }
    }
    return edits;
  }

  /// A comment's `[field]` reference renamed; prose that merely uses the word
  /// is left, since "the theme" in a sentence is rarely the slot.
  String inComment(String text) => text.replaceAllMapped(
    RegExp('\\[${RegExp.escape(from)}([\\].])'),
    (m) => '[$to${m[1]}',
  );

  static bool _startsUpper(String s) =>
      s.isNotEmpty && s[0] != s[0].toLowerCase();
}

/// A declaration of the field's name that is not the slot, and the stretch of
/// source where a bare reference means it.
typedef _Shadow = ({int nameOffset, int start, int end});

extension on _Shadow {
  bool covers(int offset) => offset >= start && offset < end;
}

/// One walk over the tree, collecting what the token pass needs: which
/// declarations are the slot, which shadow it and where, and which call each
/// argument list belongs to.
class _Scan extends GeneralizingAstVisitor<void> {
  _Scan(this.name, this.ownerTypes);

  final String name;
  final Set<String> ownerTypes;

  final renamedDeclarations = <Token>[];
  final shadows = <_Shadow>[];
  final _calls = <({int start, int end, String? invoked})>[];

  /// The name of the call whose argument list most tightly encloses [offset].
  String? invokedAround(int offset) {
    ({int start, int end, String? invoked})? best;
    for (final c in _calls) {
      if (offset >= c.start &&
          offset < c.end &&
          (best == null || c.start >= best.start)) {
        best = c;
      }
    }
    return best?.invoked;
  }

  @override
  void visitNode(AstNode node) {
    switch (node) {
      case ArgumentList(:final parent):
        _calls.add((
          start: node.offset,
          end: node.end,
          invoked: switch (parent) {
            MethodInvocation(:final methodName) => methodName.name,
            InstanceCreationExpression(:final constructorName) =>
              constructorName.type.name.lexeme,
            _ => null,
          },
        ));
      case VariableDeclaration(name: final token) when token.lexeme == name:
        final list = node.parent;
        _declared(
          token,
          list is VariableDeclarationList ? list.type : null,
          node,
        );
      case MethodDeclaration(name: final token) when token.lexeme == name:
        _declared(token, node.returnType, node);
      case FunctionDeclaration(name: final token) when token.lexeme == name:
        _declared(token, null, node);
      case FormalParameter(name: final token?) when token.lexeme == name:
        _declared(token, node.type, node);
      case DeclaredIdentifier(name: final token) when token.lexeme == name:
        _declared(token, null, node);
      case DeclaredVariablePattern(name: final token) when token.lexeme == name:
        _declared(token, null, node);
      case CatchClauseParameter(name: final token) when token.lexeme == name:
        _declared(token, null, node);
      default:
        break;
    }
    super.visitNode(node);
  }

  void _declared(Token token, TypeAnnotation? type, AstNode node) {
    if (type is NamedType && ownerTypes.contains(type.name.lexeme)) {
      renamedDeclarations.add(token);
      return;
    }

    final scope = _scopeOf(node);
    shadows.add((
      nameOffset: token.offset,
      start: scope.offset,
      end: scope.end,
    ));
  }

  /// Where a bare reference to a declaration made at [node] means it.
  ///
  /// A class member reaches the whole declaration it belongs to; a parameter
  /// the function it is a parameter of; a local the block around it. Coarse on
  /// purpose — a local shadows its whole block, before its declaration too —
  /// because erring wide leaves a name alone, and a name left alone is the
  /// failure the analyzer reports.
  static AstNode _scopeOf(AstNode node) {
    if (node is FormalParameter) {
      for (var at = node.parent; at != null; at = at.parent) {
        if (at is FormalParameterList) {
          return at.parent ?? at;
        }
      }
    }

    final member =
        node is MethodDeclaration || node.parent?.parent is FieldDeclaration;
    for (var at = node.parent; at != null; at = at.parent) {
      if (member ? at is CompilationUnitMember : _isLocalScope(at)) {
        return at;
      }
      if (at is CompilationUnit) {
        return at;
      }
    }
    return node.root;
  }

  static bool _isLocalScope(AstNode node) =>
      node is Block ||
      node is FunctionBody ||
      node is ForStatement ||
      node is ForElement ||
      node is CatchClause ||
      node is CompilationUnitMember;
}
