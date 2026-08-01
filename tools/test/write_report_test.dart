import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/shape.dart';
import 'support/in_process.dart';

/// The machine write format: **one shape in two states**.
///
/// The properties worth pinning are the ones a consumer builds against and
/// cannot re-derive — that the planned and applied results are the same object
/// plus a marker, that a change carries a diff rather than file contents, and
/// that a build handed to a live watch is reported where it happened.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<Map<String, Object?>> write(List<String> args) async {
    final r = await runInProcess(fx, args);
    expect(r.exitCode, 0, reason: '${args.join(' ')}\n${r.stderr}');
    return jsonDecode(r.stdout) as Map<String, Object?>;
  }

  List<Map<String, Object?>> changes(Map<String, Object?> out) =>
      (out['changes'] as List).cast<Map<String, Object?>>();

  group('one shape in two states', () {
    test('the plan and the result differ only by the applied marker', () async {
      // The claim atomicity buys: with no partial state to describe, the result
      // *is* the plan plus a flag, so there is no second format for results.
      final planned = await write([
        'add-page',
        'settings',
        '--dry-run',
        '--json',
      ]);
      final applied = await write(['add-page', 'settings', '--json']);

      expectSameShape(planned, applied);
    });

    test('no version field — the additive-only rule is the contract', () async {
      final out = await write(['add-substate', 'cart', '--dry-run', '--json']);
      expect(out.keys, isNot(contains('version')));
      expect(out.keys, isNot(contains('schemaVersion')));
    });

    test(
      'the dry run wrote nothing, which is what "not applied" means',
      () async {
        await write(['add-page', 'settings', '--dry-run', '--json']);
        expect(
          fx.file('ui/lib/pages/settings_page.dart').existsSync(),
          isFalse,
        );
      },
    );
  });

  group('a change carries its address, its operation and a diff', () {
    test(
      'a creation names the file it will make and diffs against nothing',
      () async {
        final out = await write([
          'add-page',
          'settings',
          '--dry-run',
          '--json',
        ]);
        final page = changes(out).firstWhere(
          (c) => (c['path']! as String).endsWith('settings_page.dart'),
        );
        expect(page['op'], 'create');
        expect(page['path'], fx.path('ui/lib/pages/settings_page.dart'));
        expect(page['diff'], contains('+++ b/ui/lib/pages/settings_page.dart'));
        expect(page['diff'], contains('+class SettingsPage'));
      },
    );

    test('an edit diffs against what the file still holds', () async {
      final out = await write(['add-page', 'settings', '--dry-run', '--json']);
      final router = changes(
        out,
      ).firstWhere((c) => (c['path']! as String).endsWith('app_router.dart'));
      expect(router['op'], 'edit');
      expect(
        router['diff'],
        contains('+++ b/app/lib/navigation/app_router.dart'),
      );
      expect(router['diff'], contains('+'));
    });

    test('no whole-file contents appear anywhere', () async {
      // A payload two source files large per file touched is what the diff
      // exists to avoid — so there is no `content`/`after` field to grow into.
      final out = await write(['add-page', 'settings', '--dry-run', '--json']);
      for (final c in changes(out)) {
        expect(c.keys, isNot(contains('content')));
        expect(c.keys, isNot(contains('after')));
        expect(c.keys, isNot(contains('before')));
      }
    });

    test('a move names both ends and carries no diff', () async {
      expect((await runInProcess(fx, ['add-substate', 'profile'])).exitCode, 0);
      final out = await write([
        'rename',
        'profile',
        'member',
        '--kind',
        'substate',
        '--json',
      ]);
      final move = changes(out).firstWhere((c) => c['op'] == 'move');
      expect(move['from'], contains('profile'));
      expect(move['path'], contains('member'));
      expect(
        move.keys,
        isNot(contains('diff')),
        reason: 'the operation and the two paths already say all of it',
      );
    });

    test('a removal names the folder and the file it drops', () async {
      expect((await runInProcess(fx, ['add-substate', 'cart'])).exitCode, 0);
      final out = await write(['remove', 'cart', '--apply', '--json']);
      final ops = changes(out).map((c) => c['op']).toSet();
      expect(ops, contains('delete-directory'));
      expect(ops, contains('edit'), reason: 'the unwiring edits come with it');
    });
  });

  group('the result reports the process facts of its own command', () {
    test(
      'the codegen step is named, and nothing ran without being asked',
      () async {
        final out = await write(['add-model', 'money', '--json']);
        final build = out['build'] as Map<String, Object?>?;
        expect(build, isNotNull, reason: 'add-model needs codegen');
        expect(build!['package'], contains('models'));
        expect(build['command'], contains('build_runner'));
        expect(build['ran'], isFalse, reason: 'no --build-runner was given');
      },
    );

    test('a build handed to a running watch is named in the result', () async {
      // The rule *machine output describes the file tree* deciding a case: an
      // agent needs the hand-off at the moment it acts, not when it audits
      // later. The watch is a decoy whose command line matches the scan and
      // whose parent (this test process) is alive, so it counts as live —
      // spawning a real one would take over the fixture.
      final script = File(
        p.join(Directory.systemTemp.path, 'build_runner_decoy.sh'),
      )..writeAsStringSync('sleep 30\n');
      final decoy = await Process.start('sh', [script.path, 'watch']);
      addTearDown(() {
        decoy.kill(ProcessSignal.sigkill);
        if (script.existsSync()) script.deleteSync();
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final out = await write(['add-model', 'money', '--json']);
      final build = out['build']! as Map<String, Object?>;
      expect(build['handedToWatch'], isTrue);
      expect(build['ran'], isFalse);
      expect(build['watchPid'], isA<int>());
    }, testOn: 'posix');

    test('a command with no codegen step reports no build', () async {
      // `add-selector` edits the facade and generates nothing.
      final out = await write([
        'add-selector',
        'log_in',
        'isReady',
        '--expr',
        '_state.logIn.email != null',
        '--json',
      ]);
      expect(out.keys, isNot(contains('build')));
    });

    test('the command names itself, so a log of results is readable', () async {
      final out = await write(['add-substate', 'cart', '--dry-run', '--json']);
      expect(out['command'], 'add-substate');
    });
  });

  group('stdout stays parseable', () {
    test('nothing but the JSON line lands on it', () async {
      final r = await runInProcess(fx, ['add-page', 'settings', '--json']);
      expect(r.exitCode, 0);
      expect(
        const LineSplitter().convert(r.stdout).where((l) => l.isNotEmpty),
        hasLength(1),
      );
    });

    test('a refusal says nothing on stdout and exits non-zero', () async {
      // The exit code carries the whole truth, so a consumer that only needs to
      // know whether it worked never parses anything.
      expect((await runInProcess(fx, ['add-page', 'settings'])).exitCode, 0);
      final again = await runInProcess(fx, ['add-page', 'settings', '--json']);
      expect(again.exitCode, 70);
      expect(again.stdout, isEmpty);
      expect(again.stderr, contains('already exists'));
    });

    test('an unresolvable target likewise', () async {
      final r = await runInProcess(fx, [
        'add-field',
        'nope',
        '--state',
        'notThere',
        '--type',
        'String',
        '--json',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.stdout, isEmpty);
    });
  });

  test(
    'an edit that is already there is an empty changeset, not prose',
    () async {
      // "Nothing to do" is a changeset with nothing in it. Said in prose on
      // stdout — which is how `add-nav` used to say it — it corrupts the parse.
      expect(
        (await runInProcess(fx, [
          'add-selector',
          'log_in',
          'isReady',
        ])).exitCode,
        0,
      );
      final out = await write(['add-selector', 'log_in', 'isReady', '--json']);
      expect(changes(out), isEmpty);
      expect(out['applied'], isTrue);
    },
  );

  test('in-process and subprocess emit identical bytes', () async {
    // The dry run is the comparable case: it writes nothing, so the second run
    // sees the same tree as the first.
    final args = ['add-page', 'settings', '--dry-run', '--json'];
    final inProc = await runInProcess(fx, args);
    final subProc = await runFrx(fx, args);
    expect(inProc.exitCode, subProc.exitCode);
    expect(inProc.stdout, subProc.stdout as String);
    expect(inProc.stderr, subProc.stderr as String);
    expect(jsonDecode(inProc.stdout), isA<Map<String, Object?>>());
  });
}
