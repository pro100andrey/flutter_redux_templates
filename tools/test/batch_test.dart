import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/util/console.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';
import 'support/shape.dart';

/// A feature's worth of artifacts, declared once and wired in **one
/// transaction**.
///
/// The properties worth pinning are the ones a batch exists for: that a failure
/// at the fifth intent leaves nothing of the first four, that the order written is
/// the order applied, and that what a batch refuses it refuses with a reason.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  late Directory outside;

  setUp(() => outside = Directory.systemTemp.createTempSync('frx_batch_'));
  tearDown(() => outside.deleteSync(recursive: true));

  /// Writes a declaration file **outside** the fixture and returns its path.
  ///
  /// Outside because the tests compare the tree byte for byte, and a declaration
  /// sitting inside it would be a change the batch did not make.
  String declare(List<Map<String, Object?>> intents) {
    final file = File(p.join(outside.path, 'feature.json'))
      ..writeAsStringSync(jsonEncode({'intents': intents}));
    return file.path;
  }

  /// A file for a malformed-declaration case, likewise outside the fixture.
  String malformed(String body) {
    final file = File(p.join(outside.path, 'bad.json'))
      ..writeAsStringSync(body);
    return file.path;
  }

  /// Every path under the fixture, files as bytes and directories as null.
  Map<String, List<int>?> tree() {
    final out = <String, List<int>?>{};
    for (final e in fx.root.listSync(recursive: true, followLinks: false)) {
      out[p.relative(e.path, from: fx.root.path)] = e is File
          ? e.readAsBytesSync()
          : null;
    }
    return out;
  }

  Future<Ran> batch(List<String> args) => runInProcess(fx, ['batch', ...args]);

  group('one transaction', () {
    test('a whole feature is wired in written order', () async {
      final r = await batch([
        declare([
          {
            'command': 'add-substate',
            'args': ['cart'],
            'options': {'kind': 'table'},
          },
          {
            'command': 'add-page',
            'args': ['checkout'],
            'options': {'public': true},
          },
          {
            'command': 'add-action',
            'args': ['checkout'],
            'options': {'state': 'cart', 'kind': 'waiting'},
          },
        ]),
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(
        fx.file('business/lib/redux/cart/models/cart_state.dart').existsSync(),
        isTrue,
      );
      expect(fx.file('ui/lib/pages/checkout_page.dart').existsSync(), isTrue);
      expect(
        fx.read('app/lib/navigation/app_router.dart'),
        contains('CheckoutRoute'),
      );
      expect(r.stdout, contains('3 intent(s)'));
    });

    test('a failure at the last intent leaves nothing of the first', () async {
      // The whole point: eight invocations are eight rollback boundaries, and a
      // failure at the fifth leaves the first four applied.
      final before = tree();
      final r = await batch([
        declare([
          {
            'command': 'add-substate',
            'args': ['cart'],
          },
          {
            'command': 'add-page',
            'args': ['checkout'],
          },
          // `add-action` refuses a substate that is not there.
          {
            'command': 'add-action',
            'args': ['save'],
            'options': {'state': 'nowhere'},
          },
        ]),
      ]);
      expect(r.exitCode, isNot(0));
      expect(tree(), before, reason: 'the tree is byte-identical');
    });

    test('the failure names the intent and what it needed', () async {
      final r = await batch([
        declare([
          {
            'command': 'add-action',
            'args': ['save'],
            'options': {'state': 'nowhere'},
          },
        ]),
      ]);
      expect(r.stderr, contains('intent 1 of 1'));
      expect(r.stderr, contains('add-action save'));
      expect(r.stderr, contains('Nothing was written'));
      expect(
        r.stderr,
        contains('order written'),
        reason: 'the author is told what to fix, not just that it broke',
      );
    });

    test('the ordering case: the action after its substate, not before', () async {
      // Ordered wrongly it fails; ordered rightly the same intents succeed. That
      // asymmetry is the reason topological sorting was rejected — silently
      // reordering would hide a prerequisite that belongs to the architecture,
      // not to frx's internals.
      final wrong = await batch([
        declare([
          {
            'command': 'add-action',
            'args': ['save'],
            'options': {'state': 'cart'},
          },
          {
            'command': 'add-substate',
            'args': ['cart'],
          },
        ]),
      ]);
      expect(wrong.exitCode, isNot(0));
      expect(
        Directory(fx.path('business/lib/redux/cart')).existsSync(),
        isFalse,
      );

      final right = await batch([
        declare([
          {
            'command': 'add-substate',
            'args': ['cart'],
          },
          {
            'command': 'add-action',
            'args': ['save'],
            'options': {'state': 'cart'},
          },
        ]),
      ]);
      expect(right.exitCode, 0, reason: right.stderr);
      expect(
        fx
            .file('business/lib/redux/cart/actions/save_action.dart')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('the declaration', () {
    test('is read from standard input too', () async {
      final captured = CapturedConsole(
        input: jsonEncode({
          'intents': [
            {
              'command': 'add-substate',
              'args': ['cart'],
            },
          ],
        }),
      );
      final code = await withConsole(
        captured,
        () => FrxRunner().runFrx(['batch', '-', '--root', fx.root.path]),
      );
      expect(code, 0, reason: captured.errors);
      expect(
        fx.file('business/lib/redux/cart/models/cart_state.dart').existsSync(),
        isTrue,
      );
    });

    test('malformed JSON is reported without applying anything', () async {
      final before = tree();
      final r = await batch([malformed('{ this is not json')]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('not valid JSON'));
      expect(tree(), before);
    });

    test('an empty or shapeless declaration says what is wrong', () async {
      for (final (body, complaint) in [
        ('{"intents": []}', 'nothing to wire'),
        ('{"intents": {}}', 'must be a list'),
        ('[]', 'must be an object'),
        ('{"intents": [{"args": ["x"]}]}', 'no "command"'),
        (
          '{"intents": [{"command": "add-page", "args": "x"}]}',
          'list of strings',
        ),
      ]) {
        final r = await batch([malformed(body)]);
        expect(r.exitCode, 64, reason: body);
        expect(r.stderr, contains(complaint), reason: body);
      }
    });

    test('a missing file is reported, not crashed on', () async {
      final r = await batch([p.join(outside.path, 'nope.json')]);
      expect(r.exitCode, 70);
      expect(r.stderr, contains('could not read the declaration'));
    });
  });

  group('what a batch refuses', () {
    test('rename and removal, each with its reason', () async {
      for (final (command, reason) in [
        ('rename', 'rewrites references'),
        ('remove', 'deletes artifacts'),
      ]) {
        final r = await batch([
          declare([
            {
              'command': command,
              'args': ['a', 'b'],
            },
          ]),
        ]);
        expect(r.exitCode, 64, reason: command);
        expect(r.stderr, contains(reason), reason: command);
        expect(
          r.stderr,
          contains('different class of risk'),
          reason: 'refused with a reason rather than silently ignored',
        );
      }
    });

    test('a command that is not a creation command', () async {
      final r = await batch([
        declare([
          {'command': 'doctor'},
        ]),
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('not a creation command'));
    });

    test('the wizard, pointing at what to declare instead', () async {
      final r = await batch([
        declare([
          {'command': 'new'},
        ]),
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('interactive wizard'));
    });

    test('an intent carrying a flag that belongs to the batch', () async {
      // The dry-run gate is the batch's. A per-intent one would mean the batch
      // was partly a rehearsal.
      for (final flag in ['dry-run', 'json', 'build-runner']) {
        final r = await batch([
          declare([
            {
              'command': 'add-substate',
              'args': ['cart'],
              'options': {flag: true},
            },
          ]),
        ]);
        expect(r.exitCode, 64, reason: flag);
        expect(r.stderr, contains('belongs to the batch'), reason: flag);
      }
    });

    test('the same flag spelled into args, however it is spelled', () async {
      // Checking `options` alone left the gate wide open: a `--dry-run` written
      // positionally reached the command just the same, and the batch reported
      // success having written nothing.
      final before = tree();
      for (final smuggled in [
        '--dry-run',
        '--json',
        '--no-format',
        '--build-runner',
      ]) {
        final r = await batch([
          declare([
            {
              'command': 'add-substate',
              'args': ['cart', smuggled],
            },
          ]),
        ]);
        expect(r.exitCode, 64, reason: smuggled);
        expect(r.stderr, contains('belongs to the batch'), reason: smuggled);
        expect(tree(), before, reason: smuggled);
      }
    });
  });

  group('the dry run', () {
    test('emits one combined plan in the machine write format', () async {
      final r = await batch([
        declare([
          {
            'command': 'add-substate',
            'args': ['cart'],
          },
          {
            'command': 'add-page',
            'args': ['checkout'],
          },
        ]),
        '--dry-run',
        '--json',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      final out = jsonDecode(r.stdout) as Map<String, Object?>;
      expect(out['command'], 'batch');
      expect(out['applied'], isFalse);
      final changes = (out['changes'] as List).cast<Map<String, Object?>>();
      // One object for the whole batch: a batch applied completely or not at all,
      // so several results would suggest a partial state that cannot happen.
      expect(
        changes.map((c) => c['path']).join(' '),
        allOf(contains('cart_state.dart'), contains('checkout_page.dart')),
      );
      expect(changes.every((c) => c.containsKey('op')), isTrue);
    });

    test('keeps nothing — the tree is as it was', () async {
      final before = tree();
      final r = await batch([
        declare([
          {
            'command': 'add-substate',
            'args': ['cart'],
          },
          {
            'command': 'add-page',
            'args': ['checkout'],
          },
        ]),
        '--dry-run',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(r.stdout, contains('nothing kept'));
      expect(tree(), before);
    });

    test(
      'plans an intent that only exists once an earlier one has run',
      () async {
        // Planning each intent against the untouched tree could not do this:
        // `add-action` refuses a substate that is not there yet.
        final r = await batch([
          declare([
            {
              'command': 'add-substate',
              'args': ['cart'],
            },
            {
              'command': 'add-action',
              'args': ['save'],
              'options': {'state': 'cart'},
            },
          ]),
          '--dry-run',
          '--json',
        ]);
        expect(r.exitCode, 0, reason: r.stderr);
        final changes =
            ((jsonDecode(r.stdout) as Map<String, Object?>)['changes'] as List)
                .cast<Map<String, Object?>>();
        expect(
          changes.map((c) => c['path']).join(' '),
          contains('save_action.dart'),
          reason: 'the second intent was planned against the first one applied',
        );
      },
    );
  });

  test('the applied result is one object with the marker flipped', () async {
    final intents = [
      {
        'command': 'add-substate',
        'args': ['cart'],
      },
    ];
    final planned = await batch([declare(intents), '--dry-run', '--json']);
    final applied = await batch([declare(intents), '--json']);
    expect(applied.exitCode, 0, reason: applied.stderr);

    expectSameShape(
      jsonDecode(planned.stdout) as Map<String, Object?>,
      jsonDecode(applied.stdout) as Map<String, Object?>,
    );
  });

  test('codegen runs once for the batch, not once per intent', () async {
    // Two intents whose artifacts need generating in the same package. Without
    // `--build-runner` the hint is printed, which is what tells us how many
    // builds a batch would have run.
    final r = await batch([
      declare([
        {
          'command': 'add-substate',
          'args': ['cart'],
        },
        {
          'command': 'add-substate',
          'args': ['orders'],
        },
      ]),
    ]);
    expect(r.exitCode, 0, reason: r.stderr);
    // One build step for the batch. Counted as the number of package directories
    // named, not as occurrences of "build_runner": around a live watch the report
    // says the words twice for the one step it stood down from.
    expect(
      RegExp(r'cd \S*business').allMatches(r.stdout).length,
      lessThanOrEqualTo(1),
      reason: 'one build step for the batch',
    );
  });
}
