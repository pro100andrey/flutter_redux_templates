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

  group('a WaitingAction whose cleanup never runs', () {
    // Measured on a real store before any of this was written: an action
    // `with WaitingAction, NonReentrant` finishes and
    // `isWaitingForType<T>()` stays true for the rest of the session — a
    // permanently disabled button, from a clause the analyzer is happy with.
    // Nothing in Dart, in async_redux or in the audit said a word.

    /// A `common/action.dart` whose `WaitingAction` behaves as the template's
    /// does: cleans up, and passes the chain on.
    void writeChainingBase() {
      fx.file('business/lib/redux/common/action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(r"""
mixin WaitingAction on ReduxAction<AppState> {
  @override
  Future<void> before() async {
    dispatchSync(WaitAction.add(this));
    await super.before();
  }

  @override
  void after() {
    super.after();
    dispatchSync(WaitAction.remove(this));
  }
}
""");
    }

    void writeAction(String withClause) {
      fx.file('business/lib/redux/theme/actions/load_theme_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'class LoadThemeAction extends Action with $withClause {\n'
          '  @override\n'
          '  Future<AppState?> reduce() async => null;\n'
          '}\n',
        );
    }

    test('a mixin that ends the chain placed after it is reported', () async {
      writeChainingBase();
      writeAction('WaitingAction, NonReentrant');
      final fs = await findings();
      expect(
        fs.any(
          (f) =>
              '${f['message']}'.contains(
                'LoadThemeAction applies NonReentrant after WaitingAction',
              ) &&
              f['severity'] == 'error',
        ),
        isTrue,
        reason: fs.toString(),
      );
    });

    test('the order add-action emits is not reported', () async {
      writeChainingBase();
      writeAction('NonReentrant, WaitingAction');
      final fs = await findings();
      expect(
        fs.where((f) => '${f['message']}'.contains('WaitingAction')),
        isEmpty,
        reason: fs.toString(),
      );
    });

    test('BlockingAction after WaitingAction is not reported', () async {
      // Required by Dart — `mixin BlockingAction on WaitingAction` — and
      // harmless: it declares no `after()`, so it ends nothing. A check that
      // read the rule as "WaitingAction must be last" would report every
      // blocking action in the template.
      writeChainingBase();
      writeAction('WaitingAction, BlockingAction');
      final fs = await findings();
      expect(
        fs.where((f) => '${f['message']}'.contains('LoadThemeAction')),
        isEmpty,
        reason: fs.toString(),
      );
    });

    test('an action that writes its own after() is reported', () async {
      // No ordering involved: the clause is right and the base mixin chains.
      // A class member beats the whole `with` clause, so this `after()` is the
      // only one Dart runs — measured, the barrier stays up for good.
      writeChainingBase();
      fx.file('business/lib/redux/theme/actions/load_theme_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'class LoadThemeAction extends Action '
          'with NonReentrant, WaitingAction {\n'
          '  @override\n'
          '  void after() {}\n'
          '}\n',
        );
      final fs = await findings();
      expect(
        fs.any(
          (f) =>
              '${f['message']}'.contains(
                'LoadThemeAction overrides after() without calling '
                'super.after()',
              ) &&
              f['severity'] == 'error',
        ),
        isTrue,
        reason: fs.toString(),
      );
    });

    test('an action whose own hook chains is not reported', () async {
      writeChainingBase();
      fx.file('business/lib/redux/theme/actions/load_theme_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'class LoadThemeAction extends Action '
          'with NonReentrant, WaitingAction {\n'
          '  @override\n'
          '  void after() => super.after();\n'
          '}\n',
        );
      final fs = await findings();
      expect(
        fs.where((f) => '${f['message']}'.contains('LoadThemeAction')),
        isEmpty,
        reason: fs.toString(),
      );
    });

    test('an action with no WaitingAction is reported too', () async {
      // Where this rule started was `WaitingAction`, and stopping there left
      // the same defect unreported one mixin over: `NonReentrant` releases its
      // key in `after()`, so an action that writes a bare `after()` leaks the
      // key that stops it ever being dispatched again. No barrier involved.
      writeChainingBase();
      fx.file('business/lib/redux/theme/actions/load_theme_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'class LoadThemeAction extends Action with NonReentrant {\n'
          '  @override\n'
          '  void after() {}\n'
          '}\n',
        );
      final fs = await findings();
      expect(
        fs.any(
          (f) => '${f['message']}'.contains(
            'LoadThemeAction overrides after() without calling super.after(), '
            'which ends the chain ahead of its own mixins: NonReentrant',
          ),
        ),
        isTrue,
        reason: fs.toString(),
      );
    });

    test('an action whose mixins own no such hook is left alone', () async {
      // `Retry` works through `wrapReduce`, so there is no `after()` chain for
      // the class to end and nothing to report. A rule that fired on any
      // override would report every action that legitimately writes one.
      writeChainingBase();
      fx.file('business/lib/redux/theme/actions/load_theme_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'class LoadThemeAction extends Action with Retry {\n'
          '  @override\n'
          '  void after() {}\n'
          '}\n',
        );
      final fs = await findings();
      expect(
        fs.where((f) => '${f['message']}'.contains('LoadThemeAction')),
        isEmpty,
        reason: fs.toString(),
      );
    });

    test('a base mixin that swallows the chain is reported', () async {
      // The other half, and the one frx cannot fix by generating differently:
      // `add-action` puts WaitingAction last, which is only correct while the
      // project's own WaitingAction passes the chain on.
      fx.file('business/lib/redux/common/action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(r"""
mixin WaitingAction on ReduxAction<AppState> {
  @override
  void after() => dispatchSync(WaitAction.remove(this));
}
""");
      final fs = await findings();
      expect(
        fs.any(
          (f) =>
              '${f['message']}'.contains(
                'WaitingAction.after() does not call super.after()',
              ) &&
              f['severity'] == 'error',
        ),
        isTrue,
        reason: fs.toString(),
      );
    });
  });

  group('two spellings of one selector', () {
    test('two getters with one body are reported', () async {
      // What `add-selector` declining a taken name leaves behind: it refuses to
      // overwrite, says so, and the reader gets added by hand under another
      // name. Both are then correct, and together they are one fact spelled
      // twice — which nothing recorded, so nothing said.
      fx
          .file('business/lib/redux/selectors.dart')
          .writeAsStringSync(
            fx
                .read('business/lib/redux/selectors.dart')
                .replaceFirst(
                  'String? get email => _state.logIn.email;',
                  'String? get email => _state.logIn.email;\n'
                      '  String? get address => _state.logIn.email;',
                ),
          );
      final fs = await findings();
      expect(
        fs.any(
          (f) =>
              '${f['message']}'.contains('SelectLogIn') &&
              '${f['message']}'.contains('have the same body') &&
              f['severity'] == 'warn',
        ),
        isTrue,
        reason: fs.toString(),
      );
    });

    test('a facade with no duplicate is quiet', () async {
      final fs = await findings();
      expect(
        fs.where((f) => '${f['message']}'.contains('have the same body')),
        isEmpty,
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
      //
      // The wiring files are not part of that bargain and never were. The audit
      // reaches them *by name* — `AppState`, the router, the store's change
      // log, the selectors facade — because a check about the facade has one
      // file to read and knows which. Counting them here would make the ratio
      // report on something other than the sweep, and the two move in opposite
      // directions: adding a named-file check is cheap and would look like the
      // sweep getting worse.
      const addressed = {
        'app_state.dart',
        'app_router.dart',
        'store.dart',
        'selectors.dart',
      };
      final all = [
        for (final pkg in const ['app', 'business', 'ui'])
          for (final f in ix.filesUnder(
            Directory(p.join(fx.root.path, pkg, 'lib')),
          ))
            if (!addressed.contains(p.basename(f.path))) f,
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
