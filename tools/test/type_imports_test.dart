import 'package:test/test.dart';
import 'package:tools/src/scaffold/artifact_templates.dart';
import 'package:tools/src/scaffold/type_imports.dart';
import 'package:tools/src/util/casing.dart';

import 'support/parses.dart';

/// The one place that answers "what does a generated file have to import to
/// name this type?" — and the property that keeps every template honest about
/// asking it.
void main() {
  group('TypeImports', () {
    test('a plain type needs nothing', () {
      expect(TypeImports.forType('String?'), isEmpty);
      expect(TypeImports.forType('List<int>'), isEmpty);
    });

    test('an immutable collection needs the package', () {
      for (final type in ['IList<String>', 'IMap<String, int>', 'ISet<int>']) {
        expect(TypeImports.forType(type), [
          TypeImports.fastImmutableCollections,
        ], reason: type);
      }
    });

    test('a nullable immutable collection still needs it', () {
      expect(TypeImports.forType('IList<String>?'), [
        TypeImports.fastImmutableCollections,
      ]);
    });

    test('a const constructor in a --default needs it', () {
      // `add-field x tags:List<String>? --default 'IListConst([])'` is odd but
      // legal; the expression is what names the package, not the type.
      expect(TypeImports.forAll(['List<String>?', 'IListConst([])']), [
        TypeImports.fastImmutableCollections,
      ]);
    });

    test('a longer name that merely starts the same does not', () {
      // Guards the trailing \b: an unrelated `IListView` must not drag the
      // package in, or every generated file would carry an unused import.
      expect(TypeImports.forType('IListView<String>'), isEmpty);
    });

    test('nulls are skipped, so an absent --default needs no branch', () {
      expect(TypeImports.forAll(['String?', null]), isEmpty);
      expect(TypeImports.forAll([null, 'IList<int>']), [
        TypeImports.fastImmutableCollections,
      ]);
    });

    test('the same import is not repeated', () {
      expect(TypeImports.forAll(['IList<int>', 'IMap<String, int>']), [
        TypeImports.fastImmutableCollections,
      ]);
    });
  });

  group('a template imports what it names', () {
    // The general property the per-file assertions only approximate: whatever
    // types a generated file mentions, something in it has to supply them.
    // `expectParses` cannot see this — `support/parses.dart` says so — which is
    // how `fieldSetter` shipped `final IList<String> tags;` with no import.
    void expectSelfSufficient(String source, {required String reason}) {
      expectParses(source, reason: reason);
      for (final import in TypeImports.forAll([source])) {
        expect(
          source,
          contains("import '$import';"),
          reason: '$reason names a type from $import but does not import it',
        );
      }
    }

    test('fieldSetter, for every type that carries an import', () {
      for (final type in [
        'String?',
        'int?',
        'IList<String>',
        'IMap<String, int>?',
        'ISet<int>',
      ]) {
        expectSelfSufficient(
          ArtifactTemplates.fieldSetter(
            Casing.parse('log_in'),
            Casing.parse('tags'),
            type,
          ),
          reason: 'fieldSetter($type)',
        );
      }
    });

    test('fieldSetter keeps the package import above the relative ones', () {
      // `dart fix --code=directives_ordering` would move it anyway, but the
      // scaffolders are expected to emit already-ordered source.
      final src = ArtifactTemplates.fieldSetter(
        Casing.parse('log_in'),
        Casing.parse('tags'),
        'IList<String>',
      );
      expect(
        src.indexOf('package:fast_immutable_collections'),
        lessThan(src.indexOf("import '../../app_state.dart';")),
      );
    });
  });
}
