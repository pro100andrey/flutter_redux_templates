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

      test('the action payload cannot collide with the facade', () {
        // `Action` mixes in `Selectors`, so a public `items` field on
        // `AddItemsAction` overrode `Selectors.items` and the analyzer refused
        // it. A leading underscore is not a name a substate can have.
        final source = SubstateScaffold(
          Casing.parse('items'),
          kind: SubstateKind.table,
        ).files().entries.firstWhere((e) => e.key.contains('add_')).value;

        expect(source, contains('final IList<Object> _items;'));
        expect(source, isNot(contains('this.items')));
      });

      test('a table reducer reads through the facade', () {
        final source = SubstateScaffold(
          Casing.parse('tasks'),
          kind: SubstateKind.table,
        ).files().entries.firstWhere((e) => e.key.contains('add_')).value;

        expect(source, contains('tasks.table.addAll(byId)'));
        expect(
          source,
          isNot(contains('state.tasks.table')),
          reason: 'the facade read is the only one `frx graph` can see',
        );
      });

      test('unless the substate name is one the reducer already binds', () {
        // `byId` is the reducer's own local and `state` comes from the base
        // class; a substate named for either shadows the facade getter, and
        // `byId.table` would resolve to the local `IMap` rather than the slice.
        for (final taken in const ['byId', 'state']) {
          final source = SubstateScaffold(
            Casing.parse(taken),
            kind: SubstateKind.table,
          ).files().entries.firstWhere((e) => e.key.contains('add_')).value;

          expect(
            source,
            contains('state.$taken.table.addAll(byId)'),
            reason:
                '"$taken" is in scope inside reduce(), so the bare read is it',
          );
          expectParses(source, reason: taken);
        }
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
