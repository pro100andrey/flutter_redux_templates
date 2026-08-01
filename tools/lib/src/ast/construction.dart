/// Reading a `Foo(...)` out of an unresolved parse tree.
///
/// The hazard this exists to hold: **parse-only cannot tell a constructor from
/// a function call.** `Foo()` arrives as a [MethodInvocation] and `const Foo()`
/// as an [InstanceCreationExpression] — one construction, two node types — and
/// a named constructor `Foo.bar()` is a `MethodInvocation` whose *target* is
/// the type. Keying on one node type silently skips every other form, and the
/// forms are not rare: the non-const call is the common one.
///
/// It had two independent implementations before this, which had already
/// drifted apart in a way that mattered. `nav_source` refused any invocation
/// with a target, so it could not see `Foo.named(...)` at all;
/// `routes_source` accepted the target as the type, so it could — and read
/// `AutoRoute.guarded(...)` as an `AutoRoute`, which is what its caller needed.
/// Both behaviours are correct for their caller and neither is correct alone,
/// so both are available here: [typeName] and [fullName].
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// A construction expression, however the parser classified it.
class Construction {
  const Construction({
    required this.fullName,
    required this.arguments,
    required this.constKeyword,
    required this.nameOffset,
  });

  /// Exactly what is written before the arguments — `AutoRoute`,
  /// `AutoRoute.guarded`, `Foo<int>`. The reliable one.
  final String fullName;

  final ArgumentList arguments;

  /// The `const` in front of it, when there is one — and only when it is
  /// `const`. `new` is also a keyword in that slot and is *not* reported here:
  /// a caller removes this token because adding a runtime argument makes the
  /// expression non-const, and removing a `new` instead would be a silent
  /// no-op dressed as a fix.
  final Token? constKeyword;

  /// Where [fullName] starts, so a `const` can be spliced out up to it.
  ///
  /// Taken from the node, not computed as `arguments.offset - fullName.length`
  /// — that arithmetic is wrong the moment a type has arguments, because
  /// `Foo<int>()` reports its name as `Foo` while eight characters precede the
  /// paren.
  final int nameOffset;

  /// The type being constructed, as far as an unresolved parse can tell:
  /// everything before the first `<` or top-level `.`.
  ///
  /// Type arguments are dropped, so `Foo<int>()` and `const Foo<int>()` both
  /// answer `Foo`. They did not always: analyzer keeps a `MethodInvocation`'s
  /// type arguments in a separate field and folds an `InstanceCreation`'s into
  /// the type, so reading the name off each node gave `Foo` for one form and
  /// `Foo<int>` for the other — one construction, two answers, which is the
  /// bug class this whole module exists to close.
  ///
  /// `AutoRoute` for all of `AutoRoute(…)`, `const AutoRoute(…)` and
  /// `AutoRoute.guarded(…)`. It is a *guess* in two ways that resolution would
  /// settle and frx cannot:
  ///
  ///  * `a.b()` is indistinguishable from a named constructor and a method
  ///    call on a receiver — `controller.dispose()` reads as type `controller`;
  ///  * an import prefix looks the same as a type — `p.Foo()` reads as type
  ///    `p`, constructor `Foo`.
  ///
  /// Match it against a type name you expect. Never treat it as proof a type
  /// was constructed.
  String get typeName {
    final end = _splitPoint;
    return end == -1 ? fullName : fullName.substring(0, end);
  }

  /// The named constructor, when the source names one — `guarded` in
  /// `AutoRoute.guarded(…)`, null in `AutoRoute(…)`. Subject to the same two
  /// ambiguities as [typeName].
  String? get constructorName {
    final dot = _dotAtDepthZero;
    return dot == -1 ? null : fullName.substring(dot + 1);
  }

  /// Index of the first `<` or top-level `.`, or -1 when the name is bare.
  int get _splitPoint {
    final angle = fullName.indexOf('<');
    final dot = _dotAtDepthZero;
    if (angle == -1) return dot;
    if (dot == -1) return angle;
    return angle < dot ? angle : dot;
  }

  /// Index of the first `.` that is not inside type arguments, or -1.
  ///
  /// Depth-aware because `Foo<a.B>()` has a dot that separates nothing —
  /// splitting on it would report the type as `Foo<a`.
  int get _dotAtDepthZero {
    var depth = 0;
    for (var i = 0; i < fullName.length; i++) {
      switch (fullName[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
        case '.':
          if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The `name:` argument's expression, or null when it is not passed.
  Expression? namedArgument(String name) => namedArgumentIn(arguments, name);

  /// Reads [node] as a construction, or null when it is not one.
  ///
  /// [fullName] is read off the source rather than reassembled, because
  /// analyzer cannot split `const AutoRoute.guarded(…)` for us: unresolved, it
  /// cannot tell that `guarded` is a constructor rather than a type in a
  /// library called `AutoRoute`, so it reports the whole thing as the type and
  /// leaves `constructorName.name` null.
  static Construction? of(AstNode? node) => switch (node) {
    InstanceCreationExpression() => Construction(
      fullName: node.constructorName.toSource(),
      arguments: node.argumentList,
      constKeyword: node.keyword?.lexeme == 'const' ? node.keyword : null,
      nameOffset: node.constructorName.offset,
    ),
    // `Foo(...)` — no target, so the method name is the whole name. The type
    // arguments come from their own field and have to be put back: without
    // them `fullName` is not what is written, and [nameOffset] plus its length
    // lands in the middle of `Foo<int>`.
    MethodInvocation(target: null) => Construction(
      fullName:
          '${node.methodName.name}${node.typeArguments?.toSource() ?? ''}',
      arguments: node.argumentList,
      constKeyword: null,
      nameOffset: node.methodName.offset,
    ),
    // `Foo.bar(...)` — a named constructor, or a method call on a receiver.
    // See [typeName].
    MethodInvocation(target: final target?) => Construction(
      fullName:
          '${target.toSource()}.${node.methodName.name}'
          '${node.typeArguments?.toSource() ?? ''}',
      arguments: node.argumentList,
      constKeyword: null,
      nameOffset: target.offset,
    ),
    _ => null,
  };
}

/// The `name:` argument's expression in [args], or null when it is not passed.
///
/// `NamedArgument`, not `NamedExpression` — analyzer 14 renamed it, and the
/// old name still exists for something else.
Expression? namedArgumentIn(ArgumentList args, String name) => args.arguments
    .whereType<NamedArgument>()
    .where((e) => e.name.lexeme == name)
    .map((e) => e.argumentExpression)
    .firstOrNull;
