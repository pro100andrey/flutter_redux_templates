import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';
import 'package:tools/src/redux/ast_edit.dart';

import 'support/parses.dart';

/// The first [T] in [src], so a case can be written as the snippet it is about
/// instead of as offsets.
T _firstOf<T extends AstNode>(String src) {
  final finder = _Finder<T>();
  parseString(content: src, throwIfDiagnostics: false).unit.accept(finder);
  return finder.found!;
}

class _Finder<T extends AstNode> extends GeneralizingAstVisitor<void> {
  T? found;

  @override
  void visitNode(AstNode node) {
    if (found != null) return;
    if (node is T) {
      found = node;
      return;
    }
    super.visitNode(node);
  }
}

void main() {
  group('applyEdits', () {
    test('applies disjoint edits highest-offset-first', () {
      const src = 'abcdef';
      final out = applyEdits(src, [
        Edit.insert(0, '<'),
        Edit.replace(2, 4, 'CD'),
        Edit.insert(6, '>'),
      ]);
      expect(out, '<abCDef>');
    });

    test('a single insert lands at the offset', () {
      expect(applyEdits('ac', [Edit.insert(1, 'b')]), 'abc');
    });
  });

  group('insertIntoList', () {
    /// Splices [element] into the first collection literal in [src] and returns
    /// the edited source, so each case can be checked by parsing the result
    /// rather than by matching an exact spacing.
    String intoList(String src, String element) {
      final list = _firstOf<ListLiteral>(src);
      return applyEdits(src, [
        insertIntoList(
          elements: list.elements,
          closer: list.rightBracket,
          element: element,
        ),
      ]);
    }

    /// The same for the named parameters of the first factory constructor.
    String intoParams(String src, String element, {String? before}) {
      final params = _firstOf<ConstructorDeclaration>(src).parameters;
      return applyEdits(src, [
        insertIntoList(
          elements: params.parameters,
          closer: params.rightDelimiter ?? params.rightParenthesis,
          element: element,
          before: params.parameters
              .where((p) => p.name?.lexeme == before)
              .firstOrNull,
        ),
      ]);
    }

    test('appends after a last element that has no trailing comma', () {
      // The whole reason this helper exists: `dart format` collapses a short
      // list onto one line, dropping the trailing comma, and inserting at `]`
      // would fuse the new element onto the old one.
      expect(intoList('var x = [a];', 'b'), 'var x = [a, b];');
      expectParses(intoList('var x = [a];', 'b'));
    });

    test('appends after a last element that has one', () {
      expect(intoList('var x = [\n  a,\n];', 'b'), 'var x = [\n  a, b,\n];');
    });

    test('an empty list inserts before the closer', () {
      expect(intoList('var x = [];', 'a'), 'var x = [a,];');
    });

    test('`before` inserts ahead of an element that must stay last', () {
      const src = 'class S { const factory S({int a, int wait}) = _S; }';
      final out = intoParams(src, 'int b', before: 'wait');
      expect(out, contains('int a, int b, int wait'));
      expectParses(out);
    });

    test('falls back to appending when the anchor is absent', () {
      // The AppState wire hits this when the state has no `wait` field. It used
      // to insert at the delimiter and emit `int aint b` — which does not parse.
      const src = 'class S { const factory S({int a}) = _S; }';
      final out = intoParams(src, 'int b', before: 'wait');
      expect(out, contains('int a, int b'));
      expectParses(out);
    });

    test('an empty collection inserts before the closer', () {
      // Reachable for a literal; a parameter list cannot be empty-but-braced
      // (`S({})` is a syntax error), so only collections take this branch.
      expectParses(
        applyEdits('var x = [];', [
          insertIntoList(
            elements: _firstOf<ListLiteral>('var x = [];').elements,
            closer: _firstOf<ListLiteral>('var x = [];').rightBracket,
            element: 'a',
          ),
        ]),
      );
    });
  });

  group('importInsertion', () {
    List<ImportDirective> importsOf(String src) => parseString(
      content: src,
      throwIfDiagnostics: false,
    ).unit.directives.whereType<ImportDirective>().toList();

    test('keeps a package import sorted within the package section', () {
      const src =
          "import 'package:a/a.dart';\n"
          "import 'package:c/c.dart';\n";
      final edit = importInsertion(importsOf(src), 'package:b/b.dart');
      expect(applyEdits(src, [edit]), contains("package:a/a.dart"));
      final out = applyEdits(src, [edit]);
      expect(
        out.indexOf('package:b'),
        allOf(
          greaterThan(out.indexOf('package:a')),
          lessThan(out.indexOf('package:c')),
        ),
      );
    });

    test('a relative import sorts among the relative section', () {
      const src =
          "import 'package:a/a.dart';\n\n"
          "import 'a_foo.dart';\n"
          "import 'c_foo.dart';\n";
      final out = applyEdits(src, [
        importInsertion(importsOf(src), 'b_foo.dart'),
      ]);
      expect(
        out.indexOf('b_foo'),
        allOf(
          greaterThan(out.indexOf('a_foo')),
          lessThan(out.indexOf('c_foo')),
        ),
      );
    });
  });

  group('removeListItem', () {
    ({String src, AstNode node}) firstParam(String cls) {
      final unit = parseString(content: cls, throwIfDiagnostics: false).unit;
      final c = unit.declarations.whereType<ClassDeclaration>().first;
      final body = c.body as BlockClassBody;
      final ctor = body.members.whereType<ConstructorDeclaration>().first;
      return (src: cls, node: ctor.parameters.parameters.first);
    }

    test('removes a whole own-line element without leaving a blank line', () {
      const src = '''
class C {
  C({
    required int a,
    required int b,
  });
}
''';
      final f = firstParam(src);
      final out = applyEdits(f.src, [removeListItem(f.src, f.node)]);
      expect(out, isNot(contains('int a')));
      expect(out, contains('int b'));
      expect(out, isNot(contains('\n\n  });')));
    });
  });
}
