import 'package:test/test.dart';
import 'package:tools/src/scaffold/page_scaffold.dart';
import 'package:tools/src/scaffold/substate_scaffold.dart';
import 'package:tools/src/scaffold/tabs_scaffold.dart';
import 'package:tools/src/util/casing.dart';

import 'support/parses.dart';

/// The generators that had no test of their own at all.
///
/// `add-tabs` was never invoked by any test, and the page and substate
/// scaffolders were reached only through the CLI, where `dart format` happens
/// to reject unparseable output — accidental coverage that vanishes on any
/// path returning before the format step.
void main() {
  final name = Casing.parse('user_profile');

  group('PageScaffold', () {
    test('emits a page that parses', () {
      expectParses(PageScaffold(name).page());
    });

    test('emits a connector that parses', () {
      expectParses(PageScaffold(name).connector());
    });

    test('route params reach both halves and still parse', () {
      final scaffold = PageScaffold(
        name,
        params: [(name: 'id', type: 'int'), (name: 'tab', type: 'String?')],
      );
      expectParses(scaffold.page());
      expectParses(scaffold.connector());
      expect(scaffold.page(), contains('int id'));
    });
  });

  group('TabsScaffold', () {
    test('emits a shell that parses', () {
      final out = TabsScaffold(name, [
        Casing.parse('feed'),
        Casing.parse('settings'),
      ]).shell();
      expectParses(out);
      expect(out, contains('FeedRoute()'));
    });

    test('a single tab parses too', () {
      // A one-element list is where the comma-safe class of bug shows up.
      expectParses(TabsScaffold(name, [Casing.parse('feed')]).shell());
    });
  });

  group('SubstateScaffold', () {
    for (final kind in SubstateKind.values) {
      test('every file of a ${kind.name} substate parses', () {
        final files = SubstateScaffold(name, kind: kind).files();
        expect(files, isNotEmpty);
        files.forEach((path, source) => expectParses(source, reason: path));
      });

      test('the ${kind.name} selector block parses once wrapped', () {
        // `selectorBlock()` is the one raw string inside the code_builder
        // scaffolder — `dart_style` never sees it, so nothing else would catch
        // a malformed getter here until `selectors.dart` failed to compile.
        final block = SubstateScaffold(name, kind: kind).selectorBlock().block;
        expectParses(block, reason: '${kind.name} selector block');
      });
    }
  });
}
