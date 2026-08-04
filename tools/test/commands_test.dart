import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// The commands that had no test.
///
/// Fifteen of twenty-seven were never executed by the suite — `add-nav`,
/// `add-tabs`, `graph`, every `list-*`, and the whole simple-scaffolder family
/// — because covering one meant a subprocess against a snapshot. With the
/// console behind a sink they are function calls, so this file exists at all.
///
/// The `--json` producers get the most attention: they are the CLI's wire
/// format for the VS Code extension, and both sides used to assert the shape
/// independently from the same mental model.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<Map<String, Object?>> json(List<String> args) async {
    final r = await runInProcess(fx, args);
    expect(r.exitCode, 0, reason: '${args.join(' ')}\n${r.stderr}');
    return jsonDecode(r.stdout) as Map<String, Object?>;
  }

  group('list-substates', () {
    test('--json names every wired substate with its file', () async {
      final out = await json(['list-substates', '--json']);
      final rows = (out['substates'] as List).cast<Map<String, Object?>>();
      expect(
        rows.map((r) => r['field']),
        containsAll(['connectivity', 'logIn']),
      );
      for (final r in rows.where((r) => r['file'] != null)) {
        expect(
          File(r['file']! as String).existsSync(),
          isTrue,
          reason: '${r['field']} points at a file that is not there',
        );
      }
    });

    test('the table names the same substates as the JSON', () async {
      // The two renderings drifting apart is the failure worth pinning: the
      // table is what a human reads and the JSON is what the editor reads.
      final rows =
          ((await json(['list-substates', '--json']))['substates'] as List)
              .cast<Map<String, Object?>>();
      final table = await runInProcess(fx, ['list-substates']);
      for (final r in rows) {
        expect(table.stdout, contains(r['field'] as String));
      }
    });
  });

  group('list-routes', () {
    test('--json names every registered route and its path', () async {
      final out = await json(['list-routes', '--json']);
      final rows = (out['routes'] as List).cast<Map<String, Object?>>();
      expect(rows.map((r) => r['route']), contains('LogInRoute'));
      expect(
        rows.firstWhere((r) => r['route'] == 'LogInRoute')['path'],
        '/log-in',
      );
    });
  });

  group('list-widget-dirs', () {
    test('--json reports an empty repo as no folders, not as a failure', () {
      // The fixture has `ui/lib/widgets/.keep` and no .dart anywhere, which is
      // deliberately the empty case: a folder with no widget in it is not an
      // established home.
      return expectLater(
        json(['list-widget-dirs', '--json']).then((o) => o['dirs']),
        completion(isEmpty),
      );
    });
  });

  group('list-mixins', () {
    test('--json carries the catalogue the editor filters on', () async {
      final out = await json(['list-mixins', '--json']);
      final rows = (out['mixins'] as List).cast<Map<String, Object?>>();
      expect(rows, hasLength(greaterThan(5)));
      final retry = rows.firstWhere((m) => m['name'] == 'retry');
      expect(retry['clause'], 'Retry');
      expect(retry['summary'], isNotEmpty);
      // `conflictsWith` arrives with implications folded in — that is what lets
      // the picker filter by set membership instead of re-deriving the rule.
      expect(retry['conflictsWith'], contains('debounce'));
    });

    test('it reads nothing from disk, so --root can be anywhere', () async {
      final r = await runInProcess(fx, [
        'list-mixins',
        '--json',
        '--root',
        Directory.systemTemp.path,
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
    });
  });

  group('graph', () {
    test('--json joins substates, actions and pages into one graph', () async {
      final out = await json(['graph', '--json']);
      final nodes = (out['nodes'] as List).cast<Map<String, Object?>>();
      final kinds = nodes.map((n) => n['kind']).toSet();
      expect(kinds, contains('substate'));
      expect(kinds, contains('page'));
      expect(out['edges'], isA<List>());
      // Every edge points at a node that exists — the property a consumer
      // relies on and nothing checked.
      final ids = nodes.map((n) => n['id']).toSet();
      for (final e in (out['edges'] as List).cast<Map<String, Object?>>()) {
        expect(ids, contains(e['from']), reason: 'dangling from: $e');
        expect(ids, contains(e['to']), reason: 'dangling to: $e');
      }
    });

    test(
      '--focus on an unknown id is a usage error, not an empty graph',
      () async {
        final r = await runInProcess(fx, [
          'graph',
          '--json',
          '--focus',
          'nope',
        ]);
        expect(r.exitCode, isNot(0));
      },
    );

    test('--focus takes a symbol, not only a node id', () async {
      // Through the same resolver `frx which` and the editor's F2 use — a second
      // implementation of "what does LogInRoute mean" is how conventions fork.
      for (final token in ['page:logIn', 'LogInRoute', 'LogInPageConnector']) {
        final out = await json(['graph', '--json', '--focus', token]);
        expect(
          (out['focus']! as Map<String, Object?>)['node'],
          'page:logIn',
          reason: token,
        );
      }
    });

    test('--focus takes a bare artifact name', () async {
      final out = await json(['graph', '--json', '--focus', 'log_in']);
      final focus = out['focus']! as Map<String, Object?>;
      expect(focus['node'], anyOf('page:logIn', 'substate:logIn'));
    });

    test('the applied bound is stated in both modes', () async {
      final out = await json([
        'graph',
        '--json',
        '--focus',
        'page:logIn',
        '--depth',
        '1',
      ]);
      final focus = out['focus']! as Map<String, Object?>;
      expect(focus['depth'], 1);
      expect(focus['truncated'], isA<bool>());

      final text = await runInProcess(fx, [
        'graph',
        '--focus',
        'page:logIn',
        '--depth',
        '1',
      ]);
      expect(text.stdout, contains('depth 1'));
    });

    test('an inbound walk is unbounded unless a depth is given', () async {
      final out = await json([
        'graph',
        '--json',
        '--focus',
        'page:logIn',
        '--direction',
        'inbound',
      ]);
      expect((out['focus']! as Map<String, Object?>)['depth'], isNull);
      expect((out['focus']! as Map<String, Object?>)['truncated'], isFalse);
    });

    test('--depth all is the unbounded spelling for any direction', () async {
      final out = await json([
        'graph',
        '--json',
        '--focus',
        'page:logIn',
        '--depth',
        'all',
      ]);
      expect((out['focus']! as Map<String, Object?>)['depth'], isNull);
    });

    test('the text mode names what it found rather than counting it', () async {
      // "3 substates, 7 reads" answers no question a reader of this command has
      // — least of all "what breaks if I touch this".
      final r = await runInProcess(fx, ['graph']);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(r.stdout, contains('logIn'));
      expect(r.stdout, contains('→'), reason: 'edges are named from → to');
    });

    test('--direction and --depth need a --focus to apply to', () async {
      for (final flag in [
        ['--direction', 'inbound'],
        ['--depth', '2'],
      ]) {
        final r = await runInProcess(fx, ['graph', ...flag]);
        expect(r.exitCode, 64, reason: flag.join(' '));
      }
    });
  });

  group('which', () {
    test('--json resolves a generated name back to its artifact', () async {
      final out = await json(['which', 'LogInPageConnector', '--json']);
      expect(out['kind'], 'page');
      expect(out['name'], 'log_in');
      expect(out['suffix'], 'PageConnector');
    });

    test('a name nothing wires is kind:null and exit 0, not a failure', () async {
      // Not an oversight — the editor depends on it. `queries.which` reads
      // `m && m.kind ? m : null`, and its `_json` helper turns a non-zero exit
      // into null before that runs. Exiting non-zero here would make "I looked
      // and it is not an artifact" indistinguishable from "frx broke", and F2
      // rename would fall back to Dart-Code either way — silently.
      final r = await runInProcess(fx, ['which', 'NoSuchThing', '--json']);
      expect(r.exitCode, 0);
      expect(jsonDecode(r.stdout), {'kind': null});
    });
  });

  group('add-tabs', () {
    test(
      'scaffolds the shell and every tab, and wires the nested route',
      () async {
        final r = await runInProcess(fx, [
          'add-tabs',
          'account',
          '-t',
          'profile',
          '-t',
          'settings',
          '--no-format',
        ]);
        expect(r.exitCode, 0, reason: r.stderr);
        for (final rel in [
          'ui/lib/pages/profile_page.dart',
          'ui/lib/pages/settings_page.dart',
          'app/lib/connectors/profile_page_connector.dart',
          'app/lib/connectors/account_page_connector.dart',
        ]) {
          expect(File(fx.path(rel)).existsSync(), isTrue, reason: rel);
        }
        final router = fx.read('app/lib/navigation/app_router.dart');
        expect(router, contains('AccountRoute.page'));
        expect(router, contains('ProfileRoute.page'));
      },
    );

    test('fewer than two tabs is a usage error', () async {
      final r = await runInProcess(fx, ['add-tabs', 'account', '-t', 'only']);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('at least two'));
    });

    test('a dry run writes nothing', () async {
      final r = await runInProcess(fx, [
        'add-tabs',
        'account',
        '-t',
        'a',
        '-t',
        'b',
        '--dry-run',
      ]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('Dry run'));
      expect(File(fx.path('ui/lib/pages/a_page.dart')).existsSync(), isFalse);
      expect(
        fx.read('app/lib/navigation/app_router.dart'),
        isNot(contains('AccountRoute')),
      );
    });
  });

  group('add-nav', () {
    test('refuses a destination with no connector', () async {
      final r = await runInProcess(fx, ['add-nav', 'log_in', 'nowhere']);
      expect(r.exitCode, 70);
      expect(r.stderr, contains('NowherePageConnector'));
    });

    test(
      'refuses a destination whose connector exists but is unrouted',
      () async {
        // The check that makes the scaffold compile: auto_route generates no
        // route class for an unregistered page, so there is nothing to push.
        // Ordered after the connector check, which is why this needs a connector
        // on disk to reach it at all.
        File(fx.path('app/lib/connectors/stray_page_connector.dart'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('@RoutePage()\nclass StrayPageConnector {}\n');
        final r = await runInProcess(fx, ['add-nav', 'log_in', 'stray']);
        expect(r.exitCode, 70);
        expect(r.stderr, contains('not registered'));
      },
    );

    test('refuses a page navigating to itself', () async {
      final r = await runInProcess(fx, ['add-nav', 'log_in', 'log_in']);
      expect(r.exitCode, 64);
    });

    test('wires the hop, and re-running it is a no-op that says so', () async {
      // The suite reached `add-nav` only through its three refusals, so the
      // one thing it is for — five edits across two packages, and the skip
      // that keeps a second run from registering a second hop — was covered by
      // nobody.
      // Through `add-page`, because a hop is only wirable into a connector frx
      // wrote: the `_Vm`/`_Factory` pair is where the callback goes, and the
      // fixture's hand-written stubs have neither.
      for (final page in ['account', 'profile']) {
        expect(
          (await runInProcess(fx, ['add-page', page, '--no-format'])).exitCode,
          0,
        );
      }
      final connector = fx.file(
        'app/lib/connectors/account_page_connector.dart',
      );
      final first = await runInProcess(fx, [
        'add-nav',
        'account',
        'profile',
        '--no-format',
      ]);
      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(first.stdout, contains('ProfileRoute'));
      // Five edits across two packages: the view-model field, the dispatch that
      // fills it, the argument handed to the page, and the page's own parameter
      // and field.
      expect(connector.readAsStringSync(), contains('onTapProfile'));
      expect(connector.readAsStringSync(), contains('GoAction.push'));
      expect(
        fx.read('ui/lib/pages/account_page.dart'),
        contains('onTapProfile'),
      );

      final wired = connector.readAsStringSync();
      final again = await runInProcess(fx, [
        'add-nav',
        'account',
        'profile',
        '--no-format',
      ]);
      expect(again.exitCode, 0, reason: again.stderr.toString());
      expect(again.stdout, contains('already has `onTapProfile`'));
      expect(
        connector.readAsStringSync(),
        wired,
        reason: 'the second run registered the hop again',
      );
    });

    test('refuses a --via that is not a Dart identifier', () async {
      // It becomes a field on the view-model and a parameter on the page.
      final r = await runInProcess(fx, [
        'add-nav',
        'log_in',
        'home',
        '--via',
        'on tap!',
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('identifier'));
    });
  });

  group('the simple scaffolders', () {
    // The commands whose whole output is new files. `add-retrofit` and
    // `add-theme-extension` were the two no test had ever run: they write into
    // `http_client/lib/api` and `ui/lib/theme/extensions`, neither of which the
    // fixture lays down, so they also pin that a scaffolder creates the
    // directory it targets.
    const cases = <(String, List<String>, String)>[
      (
        'add-service',
        ['add-service', 'clock'],
        'business/lib/redux/services/clock/clock.dart',
      ),
      ('add-model', ['add-model', 'user'], 'models/lib/user.dart'),
      (
        'add-enum',
        ['add-enum', 'status', '--value', 'idle', '--value', 'busy'],
        'models/lib/status.dart',
      ),
      (
        'add-connector',
        ['add-connector', 'avatar'],
        'app/lib/connectors/avatar_connector.dart',
      ),
      (
        'add-retrofit',
        ['add-retrofit', 'catalog'],
        'http_client/lib/api/catalog.dart',
      ),
      (
        'add-theme-extension',
        ['add-theme-extension', 'spacing'],
        'ui/lib/theme/extensions/spacing.dart',
      ),
    ];

    for (final (name, args, expected) in cases) {
      test('$name writes what it says it wrote', () async {
        final r = await runInProcess(fx, [...args, '--no-format']);
        expect(r.exitCode, 0, reason: r.stderr);
        // The plan and the disk have to agree — the plan is what the editor
        // parses to decide which file to open.
        expect(r.stdout, contains('create'));
        expect(
          File(fx.path(expected)).existsSync(),
          isTrue,
          reason:
              '$name said it created files; $expected is not there.\n'
              '${r.stdout}',
        );
      });

      test('$name refuses to clobber without --force', () async {
        expect((await runInProcess(fx, [...args, '--no-format'])).exitCode, 0);
        final again = await runInProcess(fx, [...args, '--no-format']);
        expect(again.exitCode, 70);
        expect(again.stderr, contains('already exists'));

        final forced = await runInProcess(fx, [
          ...args,
          '--no-format',
          '--force',
        ]);
        expect(forced.exitCode, 0, reason: forced.stderr);
      });
    }
  });

  group('add-substate guards the folder, not the files', () {
    // A substate is regenerated as a unit, so its guard is on the directory
    // rather than on each file the write engine checks — a different guard,
    // reaching the same exit code the editor retries on, and tested by nobody.
    setUp(() async {
      expect(
        (await runInProcess(fx, [
          'add-substate',
          'cart',
          '--no-format',
        ])).exitCode,
        0,
      );
    });

    test(
      'a second run refuses at 70, and --force replaces the folder',
      () async {
        final again = await runInProcess(fx, [
          'add-substate',
          'cart',
          '--no-format',
        ]);
        expect(again.exitCode, 70);
        expect(again.stderr, contains('already exists'));
        expect(again.stderr, contains('--force'));

        final forced = await runInProcess(fx, [
          'add-substate',
          'cart',
          '--kind',
          'table',
          '--force',
          '--no-format',
        ]);
        expect(forced.exitCode, 0, reason: forced.stderr.toString());
        // The folder is replaced, not merged: the value kind's setter must not
        // survive into a table-kind substate.
        expect(
          fx
              .file('business/lib/redux/cart/actions/set_value_action.dart')
              .existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a dry run over an existing folder plans instead of refusing',
      () async {
        final planned = await runInProcess(fx, [
          'add-substate',
          'cart',
          '--dry-run',
        ]);
        expect(planned.exitCode, 0, reason: planned.stderr.toString());
        expect(planned.stdout, contains('overwrite'));
      },
    );
  });

  group('exit codes are the contract the editor reads', () {
    // scaffold.ts retries with --force on 70, and artifact.ts distinguishes 64
    // from a real failure. Both would misbehave silently if these moved.
    test('70 means "it is already there"', () async {
      expect((await runInProcess(fx, ['add-service', 'clock'])).exitCode, 0);
      expect((await runInProcess(fx, ['add-service', 'clock'])).exitCode, 70);
    });

    test('64 means "you used it wrong"', () async {
      expect((await runInProcess(fx, ['add-service'])).exitCode, 64);
      expect((await runInProcess(fx, ['add-field', 'log_in'])).exitCode, 64);
    });

    test('a usage error explains itself on stderr, not stdout', () async {
      // `--json` consumers parse stdout; a diagnostic mixed into it breaks the
      // parse rather than being reported.
      final r = await runInProcess(fx, ['add-service']);
      expect(r.stderr, isNotEmpty);
      expect(r.stdout, isEmpty);
    });
  });

  group('the in-process runner matches the real binary', () {
    // The sink is a test double, and this repo's recurring failure is a double
    // that behaves differently from the thing it stands for — the QuickPick
    // stub that fired synchronously, the fixture router that could not have
    // produced the route names it asserted. So: run the same command both
    // ways and require the same answer.
    for (final args in [
      ['list-substates'],
      ['list-substates', '--json'],
      ['list-routes', '--json'],
      ['list-mixins', '--json'],
      ['graph', '--json'],
      ['which', 'LogInRoute', '--json'],
    ]) {
      test(args.join(' '), () async {
        final inProc = await runInProcess(fx, args);
        final subProc = await runFrx(fx, args);
        expect(inProc.exitCode, subProc.exitCode);
        expect(inProc.stdout, subProc.stdout as String);
        expect(inProc.stderr, subProc.stderr as String);
      });
    }

    test('a usage error too, including which stream it lands on', () async {
      final inProc = await runInProcess(fx, ['add-service']);
      final subProc = await runFrx(fx, ['add-service']);
      expect(inProc.exitCode, subProc.exitCode);
      expect(inProc.stdout, subProc.stdout as String);
      expect(inProc.stderr, subProc.stderr as String);
    });
  });
}
