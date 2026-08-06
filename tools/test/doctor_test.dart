import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';
import 'package:tools/src/audit/checks.dart';
import 'package:tools/src/audit/finding.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

import 'support/fixture.dart';

/// `frx doctor --json` tags each finding with the remedy `--fix` would apply,
/// so the editor can offer a quick-fix.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<List<Map<String, dynamic>>> findings() async {
    final res = await runFrx(fx, ['doctor', '--json']);
    final parsed = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    return (parsed['findings'] as List).cast<Map<String, dynamic>>();
  }

  test('a missing freezed part is fixable via build_runner', () async {
    // The fixture states declare `part '..._state.freezed.dart'` but those
    // generated files don't exist.
    final fs = await findings();
    expect(
      fs.any((f) => f['fix'] == 'build_runner'),
      isTrue,
      reason: fs.toString(),
    );
  });

  test('an orphan substate folder is fixable via orphan removal', () async {
    // A state file whose type isn't composed into AppState.
    fx.file('business/lib/redux/ghost/models/ghost_state.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class GhostState {}\n');
    final fs = await findings();
    expect(
      fs.any(
        (f) => f['fix'] == 'orphan' && '${f['message']}'.contains('ghost'),
      ),
      isTrue,
      reason: fs.toString(),
    );
  });

  test('report-only findings carry a null fix', () async {
    // Route with no connector: HomeRoute is registered; delete its connector.
    fx.file('app/lib/connectors/home_page_connector.dart').deleteSync();
    final fs = await findings();
    final routeFinding = fs.firstWhere(
      (f) => '${f['message']}'.contains('HomeRoute'),
      orElse: () => {},
    );
    expect(routeFinding['fix'], isNull);
  });

  test('--json carries no process-state finding', () async {
    // Every other finding is a function of the file tree, which is why the
    // editor re-audits on file events. A finding about a running process
    // appears and vanishes with no file changing, so the status chip would
    // keep showing it long after it stopped being true — as it did.
    final res = await runFrx(fx, ['doctor', '--json']);
    expect(res.stdout, isNot(contains('build_runner watch')));
  });

  /// The state file is the only evidence a folder under `redux/` is a substate.
  /// Once it is gone the folder was invisible to the orphan check *and*
  /// undeletable by `remove`, whose guard keys on the same file — so it sat
  /// there, untracked by git and reported by nothing.
  group('a substate folder whose state file is gone', () {
    Directory carcass(String name, {List<String> holding = const []}) {
      final dir = Directory(fx.path('business/lib/redux/$name'));
      for (final sub in ['models', 'actions']) {
        Directory(p.join(dir.path, sub)).createSync(recursive: true);
      }
      for (final f in holding) {
        fx.file('business/lib/redux/$name/$f')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('// left behind\n');
      }
      return dir;
    }

    test('an empty one is reported and is fixable', () async {
      carcass('my_profile');
      final fs = await findings();
      final f = fs.firstWhere(
        (f) => '${f['message']}'.contains('my_profile'),
        orElse: () => {},
      );
      expect(f['severity'], 'warn', reason: fs.toString());
      expect(f['fix'], 'orphan');
      expect('${f['message']}', contains('empty artifact folder'));
      // Nothing on disk to squiggle — `--fix` is the only way to act on it.
      expect(f['file'], isNull);
    });

    test('--fix takes the whole branch away', () async {
      final dir = carcass('my_profile');
      final res = await runFrx(fx, ['doctor', '--fix']);
      expect(dir.existsSync(), isFalse, reason: res.stdout as String);
      expect(
        (await findings()).any((f) => '${f['message']}'.contains('my_profile')),
        isFalse,
      );
    });

    test(
      'one still holding a file is reported but never auto-deleted',
      () async {
        // Deleting somebody's leftover action is the decision a fix must not
        // make: the same reason a placement finding carries none.
        final dir = carcass(
          'my_profile',
          holding: ['actions/set_name_action.dart'],
        );
        final fs = await findings();
        final f = fs.firstWhere(
          (f) => '${f['message']}'.contains('my_profile'),
          orElse: () => {},
        );
        expect(f['fix'], isNull, reason: fs.toString());
        expect('${f['message']}', contains('1 file(s) remain'));
        expect('${f['file']}', endsWith('set_name_action.dart'));

        await runFrx(fx, ['doctor', '--fix']);
        expect(
          dir.existsSync(),
          isTrue,
          reason: 'the fix must leave code alone',
        );
      },
    );

    test('a folder that is not a substate is left alone', () async {
      // `common/`, `models/` and `services/` are shared, hold no state file by
      // design, and must never be read as a carcass — let alone deleted.
      for (final shared in ['common', 'models', 'services']) {
        Directory(
          fx.path('business/lib/redux/$shared'),
        ).createSync(recursive: true);
      }
      final fs = await findings();
      for (final shared in ['common', 'models', 'services']) {
        expect(
          fs.every((f) => !'${f['message']}'.contains('redux/$shared')),
          isTrue,
          reason: fs.toString(),
        );
      }
    });

    test('a wired substate is not a carcass', () async {
      // The regression that would matter most: the check runs on every folder
      // the orphan scan walks, so a healthy one must stay silent.
      final fs = await findings();
      expect(
        fs.every((f) => !'${f['message']}'.contains('artifact folder')),
        isTrue,
        reason: fs.toString(),
      );
    });
  });

  group('the registry', () {
    // The audit is a list it walks, so one check can be run — and read — on its
    // own. Before, every one of these answers cost a subprocess and arrived
    // mixed in with six other checks' findings.
    Check checkNamed(String id) => auditChecks.firstWhere((c) => c.id == id);

    test('a check runs on its own, reporting only its own findings', () {
      // Plant something a *different* check reports. Asserting on a tree where
      // the other checks are silent anyway proves nothing about isolation —
      // every finding would be the substate check's by default.
      File(p.join(fx.root.path, 'business/lib/redux/log_in/stray.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('extension type SelectStray(AppState _s) {}\n');
      final repo = FrxWorkspace(fx.root);

      bool mentionsStray(List<Finding> fs) =>
          fs.any((f) => f.message.contains('SelectStray'));

      final substatesOnly = <Finding>[];
      checkNamed('substates').run(repo, substatesOnly);
      final placementOnly = <Finding>[];
      checkNamed('placement').run(repo, placementOnly);

      expect(substatesOnly, isNotEmpty, reason: 'the fixture has substates');
      expect(mentionsStray(substatesOnly), isFalse);
      expect(mentionsStray(placementOnly), isTrue);
      expect(mentionsStray(audit(repo)), isTrue);
    });

    test('every check id is unique', () {
      expect(
        auditChecks.map((c) => c.id).toSet(),
        hasLength(auditChecks.length),
      );
    });

    test('only the process-state check is gated', () {
      // The gate exists because such a finding appears and vanishes with no
      // file changing, and the editor re-audits on file events. Anything else
      // acquiring the flag would silently vanish from `--json`.
      expect(auditChecks.where((c) => c.needsProcessState).map((c) => c.id), [
        'orphaned-watch',
      ]);
    });

    test('a remedy names itself once', () {
      // The wire values the editor keys its quick-fixes on.
      expect(const BuildRunnerFix('business').id, 'build_runner');
      expect(const OrphanFix('log_in').id, 'orphan');
      expect(const FlowDocsFix().id, 'flow-docs');
    });
  });

  group('reading the tree once', () {
    // The audit used to walk app/lib, ui/lib and business/lib twice apiece —
    // once for ungenerated parts, once for the placement rules — and parse the
    // router three times: its own route check, plus readAuthArea and readRoutes
    // reached through the docs check.
    late SourceIndex ix;
    late FrxWorkspace repo;

    setUp(() {
      ix = SourceIndex();
      repo = FrxWorkspace(fx.root);
      withSourceIndex(ix, () => audit(repo));
    });

    test('the router is parsed once', () {
      expect(
        ix.parsesOf(
          File(p.join(fx.root.path, 'app/lib/navigation/app_router.dart')),
        ),
        1,
      );
    });

    test('no file is parsed twice', () {
      final twice = [
        for (final pkg in const ['app', 'business', 'ui'])
          for (final f in ix.filesUnder(
            Directory(p.join(fx.root.path, pkg, 'lib')),
          ))
            if (ix.parsesOf(f) > 1)
              '\${p.basename(f.path)} ×\${ix.parsesOf(f)}',
      ];
      expect(twice, isEmpty);
    });

    test('each package lib is walked once', () {
      // Per directory, on the index the audit actually ran against. Counting a
      // *second* audit's extra walks would only prove the cache works — a first
      // audit that swept app/lib twice under two different listing keys would
      // sail straight through that, and did.
      for (final pkg in const ['app', 'business', 'ui']) {
        expect(
          ix.walksOf(Directory(p.join(fx.root.path, pkg, 'lib'))),
          1,
          reason: '$pkg/lib',
        );
      }
    });

    test('the pre-filter keeps most of the tree unparsed', () {
      // The placement rules look at every file in three packages and parse the
      // handful that could match. If that stopped being true the audit would
      // still be correct and would have stopped being affordable — so the bar
      // is "most", not "at least one".
      final all = [
        for (final pkg in const ['app', 'business', 'ui'])
          ...ix.filesUnder(Directory(p.join(fx.root.path, pkg, 'lib'))),
      ];
      final parsed = all.where((f) => ix.parsesOf(f) > 0).length;
      expect(all, isNotEmpty);
      expect(
        parsed * 2,
        lessThan(all.length),
        reason: '$parsed of ${all.length} parsed',
      );
    });
  });
}
