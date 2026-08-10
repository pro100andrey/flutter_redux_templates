import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// A view-model that compares on fewer fields than it holds.
///
/// The reader for this existed for months with no consumer, reading
/// `equatable`'s `props` getter while every view-model here states its equality
/// in `super(equals: […])` — so it read an empty list eight times out of eight
/// and could never have fired.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  void connector(String body) {
    fx.file('app/lib/connectors/thing_page_connector.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(body);
  }

  Future<List<Map<String, Object?>>> findings() async {
    final r = await runInProcess(fx, ['doctor', '--json']);
    return ((jsonDecode(r.stdout) as Map)['findings'] as List)
        .cast<Map<String, Object?>>();
  }

  /// Findings of this rule, by rule id rather than by a phrase in the message.
  ///
  /// Matching prose meant the helper decided what counted, and it decided
  /// wrongly the moment the message grew a second wording: a real finding about
  /// a field compared only through `ids.length` was filtered out of a test
  /// asserting that very finding.
  Future<Iterable<String>> aboutEquality() async => (await findings())
      .where((f) => f['rule'] == 'field-outside-equality')
      .map((f) => '${f['message']}');

  test('a value field left out of super(equals:) is reported', () async {
    connector('''
class _Vm extends Vm {
  _Vm({required this.email, required this.badge}) : super(equals: [email]);

  final String email;
  final String badge;
}
''');
    final reported = await aboutEquality();
    expect(reported, hasLength(1));
    expect(reported.single, contains('_Vm.badge'));
  });

  group('what is correct here, and must stay unreported', () {
    // Every one of this repository's fields outside equality is one of these.
    // A rule that started flagging one would be reporting working code as a
    // defect, in a template thousands of clones start from.
    const cases = <(String, String)>[
      ('a VoidCallback', 'final VoidCallback onTap;'),
      ('a ValueChanged', 'final ValueChanged<String> onChanged;'),
      (
        'a nullable FormFieldValidator',
        'final FormFieldValidator<T>? validator;',
      ),
      ('a written function type', 'final void Function() navigate;'),
    ];
    for (final (what, field) in cases) {
      test('$what outside equality is the idiom, not a defect', () async {
        connector('''
class _Vm extends Vm {
  _Vm({required this.email, required this.thing}) : super(equals: [email]);

  final String email;
  ${field.replaceFirst(RegExp(r'\w+;$'), 'thing;')}
}
''');
        expect(await aboutEquality(), isEmpty);
      });
    }

    test('a class writing its own == is not reported at all', () async {
      connector('''
class _Vm extends Vm {
  _Vm({required this.rebuild, required this.title}) : super(equals: [title]);

  final bool rebuild;
  final String title;

  /// Does not respect equals contract: is not equal when it should rebuild.
  @override
  bool operator ==(Object other) => !rebuild;
}
''');
      expect(await aboutEquality(), isEmpty);
    });

    test(
      'a computed equals list is left unread rather than half-read',
      () async {
        // The one honest unknown: a spread can carry the very field that looks
        // missing, so reporting the visible part would invent findings.
        connector('''
class _Vm extends Vm {
  _Vm({required this.a, required this.b}) : super(equals: [a, ...more]);

  final String a;
  final String b;
}
''');
        expect(await aboutEquality(), isEmpty);
      },
    );
  });

  group('an element that is not a field name does not silence the class', () {
    // All-or-nothing was right for a spread and wrong for everything else: any
    // element the reader could not name turned the whole list unreadable, and
    // an unreadable list reports nothing. So one `1` in the list excused every
    // field in the class from being compared — the rule was silenced by the
    // kind of edit nobody thinks of as touching a rule.
    //
    // Each case below leaves `ids` genuinely uncompared: two view-models
    // differing only in it are `==`, the connector's rebuild stops there, and
    // the screen keeps showing the old list.
    const cases = <(String, String)>[
      ('an int literal', '[view, 1]'),
      ('a property of another object', '[view, other.hashCode]'),
      ('a string literal', "[view, 'v2']"),
      ('a call', '[view, ids.hashCode.toString()]'),
    ];

    for (final (what, list) in cases) {
      test('$what still leaves ids reported', () async {
        connector('''
class _Vm extends Vm {
  _Vm({required this.view, required this.ids}) : super(equals: $list);

  final String view;
  final List<String> ids;
}
''');
        final reported = await aboutEquality();
        expect(reported, hasLength(1), reason: 'ids is compared by nothing');
        expect(reported.single, contains('_Vm.ids'));
      });
    }

    test('a field sharing a name with somebody else\'s member is not called '
        'derived', () async {
      // `user.id` reads `user`; `id` is a member of it and names nothing here.
      // Recording both made an unrelated field `id` be reported as compared
      // through something derived from it — the finding still true, its wording
      // false, and the wording is the entire reason it was added.
      connector('''
class _Vm extends Vm {
  _Vm({required this.user, required this.id}) : super(equals: [user.id]);

  final String user;
  final String id;
}
''');
      final reported = await aboutEquality();
      expect(reported, hasLength(2), reason: 'neither field is compared');
      // `user` is read, just not compared — `user.id` is derived from it, and
      // that is the wording it earns. `id` is a member of `user` and appears
      // here by coincidence of spelling; calling it derived would point the
      // reader at a line that says nothing about it.
      expect(
        reported.singleWhere((m) => m.contains('_Vm.user')),
        contains('only through'),
      );
      expect(
        reported.singleWhere((m) => m.contains('_Vm.id')),
        contains('outside the equality'),
      );
    });

    test('a field compared only through a property of itself is named as '
        'that, not as absent', () async {
      // `ids.length` is not nothing — the author did reach for `ids`. It is
      // also not a comparison of `ids`: two lists of the same length and
      // different contents are equal by it, which is the failure this rule is
      // about. Saying "is outside the equality" of a field spelled right there
      // in the list reads as the tool being wrong, so it says which it is.
      connector('''
class _Vm extends Vm {
  _Vm({required this.view, required this.ids}) : super(equals: [view, ids.length]);

  final String view;
  final List<String> ids;
}
''');
      final reported = await aboutEquality();
      expect(reported, hasLength(1));
      expect(reported.single, contains('_Vm.ids'));
      expect(
        reported.single,
        contains('only through'),
        reason: 'the message distinguishes a partial comparison from none',
      );
    });
  });

  test(
    'the finding carries no fix — which field belongs is the author\'s call',
    () async {
      connector('''
class _Vm extends Vm {
  _Vm({required this.email, required this.badge}) : super(equals: [email]);

  final String email;
  final String badge;
}
''');
      final r = await runInProcess(fx, ['doctor', '--json']);
      final f = ((jsonDecode(r.stdout) as Map)['findings'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (f) => '${f['message']}'.contains('outside the equality'),
          );
      expect(f['severity'], 'warn');
      expect(f['fix'], isNull);
      expect(f['rule'], 'field-outside-equality');
    },
  );

  test(
    'the rule is silenceable through .frxrc, like a placement rule',
    () async {
      connector('''
class _Vm extends Vm {
  _Vm({required this.email, required this.badge}) : super(equals: [email]);

  final String email;
  final String badge;
}
''');
      expect(await aboutEquality(), isNotEmpty);
      File(
        fx.path('.frxrc'),
      ).writeAsStringSync('{"placement": {"field-outside-equality": false}}');
      expect(await aboutEquality(), isEmpty);
    },
  );
}
