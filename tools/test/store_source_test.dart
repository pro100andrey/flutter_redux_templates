import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/redux/store_source.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// The persistor's change log — one line per `AppState` field, feeding the
/// `Δ connectivity, logIn` the action logger prints.
///
/// frx wired the `AppState` field and the selectors facade and did not know this
/// list existed, so a substate it created was invisible to the trace from the
/// moment it was created, and a renamed one kept printing its old name.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  /// Writes an observer holding [fields], in the shape the template ships.
  void store(
    List<String> fields, {
    String prev = 'prev',
    String next = 'next',
  }) {
    fx.file('business/lib/redux/store.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
class _StateChangeObserver {
  void observe(AppState $prev, AppState $next) {
    pending.changed = <String>[
${fields.map((f) => "      if ($prev.$f != $next.$f) '$f',").join('\n')}
    ];
  }
}
''');
  }

  StoreSource source() => StoreSource(fx.file('business/lib/redux/store.dart'));

  group('what counts as the block', () {
    test('a list of field comparisons is it', () {
      store(['connectivity', 'logIn']);
      expect(source().changed()?.map((e) => e.field), [
        'connectivity',
        'logIn',
      ]);
    });

    test('the names around it are the project\'s to choose', () {
      // Keying on `pending.changed` or on `prev`/`next` would tie frx to
      // identifiers a clone is free to rename.
      store(['logIn'], prev: 'was', next: 'now');
      expect(source().changed()?.single.field, 'logIn');
    });

    test('a list that only rhymes is not it', () {
      fx.file('business/lib/redux/store.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
final xs = <String>[
  if (prev.logIn != next.logIn) 'logIn',
  if (a.b != c.d) 'mixed',
];
''');
      expect(source().changed(), isNull);
    });

    test('no file, and an empty list, are both "no block"', () {
      expect(source().changed(), isNull);
      store(const []);
      expect(source().changed(), isNull);
    });

    test('a label that disagrees with its field is read, not rejected', () {
      // The shape a rename leaves behind. Recognising it is the whole point:
      // rejecting it would make the drift invisible again.
      store(['logIn']);
      final f = fx.file('business/lib/redux/store.dart');
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst("'logIn'", "'old'"),
      );
      final entry = source().changed()!.single;
      expect(entry.field, 'logIn');
      expect(entry.label, 'old');
      expect(entry.agrees, isFalse);
    });
  });

  group('editing it', () {
    test('an entry lands last, which is AppState order', () {
      store(['connectivity', 'logIn']);
      expect(source().wire(field: 'cart').source, contains("'cart'"));
      expect(
        source().changed()!.last.field,
        'logIn',
        reason: 'reading again must not see the unwritten edit',
      );
    });

    test('wiring one that is already there changes nothing', () {
      store(['logIn']);
      expect(source().wire(field: 'logIn').unchanged, isTrue);
    });

    test('unwiring matches a stale label as well as the field', () {
      // Removing `logIn` must also take away the line still *printing* `logIn`
      // after a rename moved its field.
      store(['logIn']);
      final f = fx.file('business/lib/redux/store.dart');
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst("'logIn'", "'wasLogIn'"),
      );
      expect(source().unwire(field: 'wasLogIn').unchanged, isFalse);
    });

    test('relabel moves only the label it was told about', () {
      const content = '''
void observe() {
  pending.changed = <String>[
    if (prev.signIn != next.signIn) 'logIn',
    if (prev.theme != next.theme) 'appearance',
  ];
}
''';
      final out = StoreSource.relabel(content, was: 'logIn', field: 'signIn');
      expect(out, contains("if (prev.signIn != next.signIn) 'signIn'"));
      expect(
        out,
        contains("'appearance'"),
        reason: 'a label a project chose on purpose is not frx\'s to change',
      );
    });

    test('every edit is a no-op when there is no block', () {
      expect(source().wire(field: 'cart').unchanged, isTrue);
      expect(source().unwire(field: 'cart').unchanged, isTrue);
      expect(StoreSource.relabel('', was: 'a', field: 'b'), '');
    });
  });

  group('the commands wire it', () {
    test('add-substate adds the entry, remove takes it away', () async {
      store(['connectivity', 'logIn']);
      final added = await runInProcess(fx, ['add-substate', 'cart']);
      expect(added.exitCode, 0, reason: added.stderr.toString());
      expect(added.stdout, contains("changed: 'cart'"));
      expect(source().changed()!.map((e) => e.field), contains('cart'));

      final removed = await runInProcess(fx, ['remove', 'cart', '--apply']);
      expect(removed.exitCode, 0, reason: removed.stderr.toString());
      expect(source().changed()!.map((e) => e.field), isNot(contains('cart')));
    });

    test('the entry order follows AppState field order', () async {
      // The coupling `wire` relies on: AppState appends a new field before
      // `wait`, so the newest substate is the last one this list tracks. Nothing
      // enforces it across the two modules, so it is asserted here rather than
      // left in a doc comment.
      store(['connectivity', 'logIn']);
      for (final name in ['cart', 'basket']) {
        expect((await runInProcess(fx, ['add-substate', name])).exitCode, 0);
      }
      final appStateOrder = [
        for (final line
            in fx.read('business/lib/redux/app_state.dart').split('\n'))
          if (RegExp(r'^\s*required \w+State (\w+),').hasMatch(line))
            RegExp(r'^\s*required \w+State (\w+),').firstMatch(line)!.group(1),
      ];
      expect(
        source().changed()!.map((e) => e.field).toList(),
        appStateOrder,
        reason: 'the change log and AppState disagree about order',
      );
    });

    test('a project without the block gets no entry and no note', () async {
      // Opt-in, like the docs export.
      final r = await runInProcess(fx, ['add-substate', 'cart']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      expect(r.stdout, isNot(contains('store.dart')));
      expect(
        File(fx.path('business/lib/redux/store.dart')).existsSync(),
        isFalse,
      );
    });
  });

  group('the audit reports drift, and only warns', () {
    Future<List<Map<String, Object?>>> findings() async {
      final r = await runInProcess(fx, ['doctor', '--json']);
      return ((jsonDecode(r.stdout) as Map)['findings'] as List)
          .cast<Map<String, Object?>>();
    }

    Future<Map<String, Object?>?> about(String needle) async =>
        (await findings())
            .where((f) => '${f['message']}'.contains(needle))
            .firstOrNull;

    test('an entry AppState no longer composes', () async {
      store(['connectivity', 'logIn', 'ghost']);
      final f = await about('"ghost"');
      expect(f, isNotNull);
      expect(f!['severity'], 'warn');
      expect(f['fix'], isNull, reason: 'the block belongs to the project');
    });

    test('a substate with no entry', () async {
      store(['connectivity']);
      expect((await about('AppState.logIn'))?['severity'], 'warn');
    });

    test('two lists of the same shape are refused, not guessed at', () async {
      // Measured before this was closed: a decoy declared above the observer
      // took `add-substate`'s entry, and the audit then reported every real
      // substate missing from a list that was never the change log.
      store(['connectivity', 'logIn']);
      final f = fx.file('business/lib/redux/store.dart');
      f.writeAsStringSync(
        'void decoy(Foo a, Foo b) {\n'
        "  flags = <String>[if (a.dark != b.dark) 'dark'];\n"
        '}\n${f.readAsStringSync()}',
      );
      final ambiguous = await about('more than one list');
      expect(ambiguous, isNotNull);
      expect(ambiguous!['severity'], 'warn');
      expect(
        await about('missing from the change log'),
        isNull,
        reason: 'it must not report against a list it could not identify',
      );

      final added = await runInProcess(fx, ['add-substate', 'cart']);
      expect(added.exitCode, 0, reason: added.stderr.toString());
      expect(
        f.readAsStringSync(),
        isNot(contains("'cart'")),
        reason: 'nothing is written when frx cannot tell which list is it',
      );
    });

    test('a block bound through a local is still the block', () {
      // `final changed = <String>[…]; pending.changed = changed;` had no block
      // at all — indistinguishable from opting out — and a lone rhyming
      // assignment elsewhere then silently became one.
      fx.file('business/lib/redux/store.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
void observe(AppState prev, AppState next) {
  final changed = <String>[
    if (prev.logIn != next.logIn) 'logIn',
  ];
  pending.changed = changed;
}
''');
      expect(source().changed()?.single.field, 'logIn');
      expect(source().ambiguous, isFalse);
    });

    test('a returned list of the same shape is not the block', () {
      // The block is a value *given* to the pending record. A helper that
      // returns one is the commonest way to rhyme with it.
      fx.file('business/lib/redux/store.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
List<String> diff(Foo a, Foo b) => <String>[
  if (a.dark != b.dark) 'dark',
];
''');
      expect(source().changed(), isNull);
      expect(source().ambiguous, isFalse);
    });

    test('a label that no longer matches its field', () async {
      store(['connectivity', 'logIn']);
      final file = fx.file('business/lib/redux/store.dart');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst("'logIn'", "'signIn'"),
      );
      final f = await about('prints "signIn"');
      expect(f, isNotNull);
      expect(f!['severity'], 'warn');
    });

    test('a project with no block is not asked about one', () async {
      expect(await about('change log'), isNull);
      store(const []);
      expect(await about('change log'), isNull);
    });

    test('a complete block says nothing', () async {
      store(['connectivity', 'logIn']);
      expect(await about('change log'), isNull);
      expect(await about('AppState.logIn'), isNull);
    });
  });
}
