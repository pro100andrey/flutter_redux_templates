import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';
import 'package:tools/src/ast/construction.dart';

/// The one hazard frx keeps tripping over: unresolved, a constructor and a
/// function call are the same thing.
void main() {
  /// Parses `var x = <expr>;` and hands back the expression.
  Expression expressionOf(String source) {
    final unit = parseString(
      content: 'var x = $source;',
      throwIfDiagnostics: false,
    ).unit;
    final decl = unit.declarations
        .whereType<TopLevelVariableDeclaration>()
        .single;
    return decl.variables.variables.single.initializer!;
  }

  Construction? read(String source) => Construction.of(expressionOf(source));

  group('every form of the same construction is read', () {
    test('a bare call — the common one, and a MethodInvocation', () {
      final c = read('AutoRoute(page: X.page)')!;
      expect(c.typeName, 'AutoRoute');
      expect(c.constructorName, isNull);
      expect(c.fullName, 'AutoRoute');
      expect(c.constKeyword, isNull);
    });

    test('a const call — an InstanceCreationExpression', () {
      final c = read('const AutoRoute(page: X.page)')!;
      expect(c.typeName, 'AutoRoute');
      expect(c.constructorName, isNull);
      expect(c.constKeyword, isNotNull, reason: 'the const must be removable');
    });

    test('new, which is still legal Dart', () {
      final c = read('new AutoRoute(page: X.page)')!;
      expect(c.typeName, 'AutoRoute');
      expect(c.constKeyword, isNull);
    });

    test('a named constructor, bare', () {
      // The form nav_source could not see: it refused any invocation with a
      // target, and `AutoRoute.guarded(...)` parses as exactly that.
      final c = read('AutoRoute.guarded(page: X.page)')!;
      expect(c.typeName, 'AutoRoute');
      expect(c.constructorName, 'guarded');
      expect(c.fullName, 'AutoRoute.guarded');
    });

    test('a named constructor, const', () {
      final c = read('const AutoRoute.guarded(page: X.page)')!;
      expect(c.typeName, 'AutoRoute');
      expect(c.constructorName, 'guarded');
      expect(c.constKeyword, isNotNull);
    });

    test('a generic type answers the same whichever form it is written in', () {
      // These disagreed: analyzer keeps a MethodInvocation's type arguments in
      // a separate field and folds an InstanceCreation's into the type, so
      // reading the name off each node gave `Foo` for the bare call and
      // `Foo<int>` for the const one. A caller matching `typeName == 'Foo'`
      // saw one and missed the other.
      for (final source in [
        'Foo<int>()',
        'const Foo<int>()',
        'Foo<int>.bar()',
        'const Foo<int>.bar()',
      ]) {
        expect(read(source)!.typeName, 'Foo', reason: source);
      }
      expect(read('Foo<int>()')!.fullName, 'Foo<int>');
      expect(read('const Foo<int>()')!.fullName, 'Foo<int>');
    });

    test('a dot inside type arguments does not split the name', () {
      // `Foo<a.B>()` has a dot that separates nothing.
      final c = read('Foo<a.B>()')!;
      expect(c.typeName, 'Foo');
      expect(c.constructorName, isNull);
    });
  });

  group('what it is not', () {
    test('a literal is not a construction', () {
      expect(read("'hello'"), isNull);
      expect(read('42'), isNull);
      expect(read('[1, 2]'), isNull);
    });

    test('an identifier with no call is not', () {
      expect(read('AutoRoute'), isNull);
    });
  });

  test('nameOffset lands on the start of the written name', () {
    // What lets a caller splice the `const` out: everything from `nameOffset`
    // back to the keyword can go.
    for (final source in [
      'AutoRoute(a: 1)',
      'const AutoRoute(a: 1)',
      'AutoRoute.guarded(a: 1)',
      'const AutoRoute.guarded(a: 1)',
      'Foo<int>(a: 1)',
      'const Foo<int>(a: 1)',
      'Foo<int>.bar(a: 1)',
    ]) {
      final wrapped = 'var x = $source;';
      final c = read(source)!;
      expect(
        wrapped.substring(c.nameOffset, c.nameOffset + c.fullName.length),
        c.fullName,
        reason: source,
      );
    }
  });

  group('named arguments', () {
    test('reads the expression a name is bound to', () {
      final c = read('AutoRoute(page: HomeRoute.page, initial: true)')!;
      expect(c.namedArgument('page')?.toSource(), 'HomeRoute.page');
      expect(c.namedArgument('initial')?.toSource(), 'true');
    });

    test('an absent name is null, not an error', () {
      final c = read('AutoRoute(page: X.page)')!;
      expect(c.namedArgument('initial'), isNull);
    });

    test('a positional argument is not mistaken for a named one', () {
      final c = read('AutoRoute(page, initial: true)')!;
      expect(c.namedArgument('page'), isNull);
      expect(c.namedArgument('initial')?.toSource(), 'true');
    });
  });

  test(
    'a method call on a receiver reads as a construction, and must not be trusted',
    () {
      // Documented, not defended: `a.b()` is indistinguishable from a named
      // constructor without resolution. A caller matches typeName against a type
      // it expects rather than treating this as proof a type was constructed.
      final c = read('controller.dispose()')!;
      expect(c.typeName, 'controller');
      expect(c.constructorName, 'dispose');
    },
  );
}
