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

  Future<List<String>> findings() async {
    final r = await runInProcess(fx, ['doctor', '--json']);
    return [
      for (final f
          in ((jsonDecode(r.stdout) as Map)['findings'] as List)
              .cast<Map<String, Object?>>())
        '${f['message']}',
    ];
  }

  Future<Iterable<String>> aboutEquality() async =>
      (await findings()).where((m) => m.contains('outside the equality'));

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
