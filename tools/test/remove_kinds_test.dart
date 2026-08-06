import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `remove` for the kinds that wire nothing central.
///
/// Each is scaffolded by its real `add-*` and removed again, because the
/// property under test is that removal takes the whole *set* the scaffolder
/// wrote. That is the difference from `rm`, which the traced runs reached for
/// sixty-odd times across six builds: `rm` deletes the path it is handed, and
/// the halves it leaves — a model's `.freezed.dart`, a service's dispatcher —
/// are what stops the package compiling.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<void> ok(List<String> args) async {
    final res = await runFrx(fx, args);
    expect(res.exitCode, 0, reason: '${args.join(' ')}\n${res.stderr}');
  }

  test('a widget round-trips through the name that created it', () async {
    // `-k view` adds no suffix, so this is the plain case; the suffixed kinds
    // are what `placement_test.dart` walks.
    await ok(['add-widget', 'TaskTile', '--dir', 'tiles', '--no-format']);
    expect(fx.file('ui/lib/tiles/task_tile.dart').existsSync(), isTrue);

    await ok(['remove', 'TaskTile', '--kind', 'widget', '--apply']);
    expect(fx.file('ui/lib/tiles/task_tile.dart').existsSync(), isFalse);
  });

  test('a model goes with its generated siblings', () async {
    await ok(['add-model', 'Task', '--no-format']);
    // build_runner does not run in a fixture, so stand its output in: the
    // property is that a `part of` sibling is not left behind, and what wrote
    // it does not matter.
    fx.file('models/lib/task.freezed.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("part of 'task.dart';\n");
    fx
        .file('models/lib/task.g.dart')
        .writeAsStringSync("part of 'task.dart';\n");

    await ok(['remove', 'Task', '--kind', 'model', '--apply']);
    expect(fx.file('models/lib/task.dart').existsSync(), isFalse);
    expect(
      fx.file('models/lib/task.freezed.dart').existsSync(),
      isFalse,
      reason:
          'a stranded freezed part is `part of` a file that no longer exists',
    );
    expect(fx.file('models/lib/task.g.dart').existsSync(), isFalse);
  });

  test('a model deletion takes only its own siblings', () async {
    // `task.dart` and `task_list.dart` share a prefix; matching on the prefix
    // rather than on the stem would take the neighbour's generated files too.
    await ok(['add-model', 'Task', '--no-format']);
    await ok(['add-model', 'TaskList', '--no-format']);
    fx.file('models/lib/task_list.freezed.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("part of 'task_list.dart';\n");

    await ok(['remove', 'Task', '--kind', 'model', '--apply']);
    expect(fx.file('models/lib/task_list.dart').existsSync(), isTrue);
    expect(
      fx.file('models/lib/task_list.freezed.dart').existsSync(),
      isTrue,
      reason: 'a neighbour that merely shares a prefix must survive',
    );
  });

  test('a service goes with its dispatcher', () async {
    await ok(['add-service', 'Sync', '--no-format']);
    final dir = Directory(fx.path('business/lib/redux/services/sync'));
    expect(dir.listSync().whereType<File>(), hasLength(2));

    await ok(['remove', 'Sync', '--kind', 'service', '--apply']);
    expect(dir.existsSync(), isFalse);
  });

  test(
    'an action is found under its substate without being told which',
    () async {
      await ok([
        'add-action',
        'ArchiveTask',
        '--state',
        'log_in',
        '--no-format',
      ]);
      final file = fx.file(
        'business/lib/redux/log_in/actions/archive_task_action.dart',
      );
      expect(file.existsSync(), isTrue);

      // No --kind: auto-detection has to reach the file kinds, or the reflex this
      // command exists to replace (`rm`) is the only thing left.
      await ok(['remove', 'ArchiveTask', '--apply']);
      expect(file.existsSync(), isFalse);
    },
  );

  test('one action name under two substates is refused, not guessed', () async {
    for (final s in const ['log_in', 'connectivity']) {
      await ok(['add-action', 'Reset', '--state', s, '--no-format']);
    }

    final res = await runFrx(fx, ['remove', 'Reset', '--apply']);
    expect(res.exitCode, 64, reason: res.stderr.toString());
    expect(res.stderr.toString(), contains('--state'));
    expect(
      fx
          .file('business/lib/redux/log_in/actions/reset_action.dart')
          .existsSync(),
      isTrue,
      reason: 'a refused removal must not have deleted either candidate',
    );

    await ok(['remove', 'Reset', '--state', 'log_in', '--apply']);
    expect(
      fx
          .file('business/lib/redux/log_in/actions/reset_action.dart')
          .existsSync(),
      isFalse,
    );
    expect(
      fx
          .file('business/lib/redux/connectivity/actions/reset_action.dart')
          .existsSync(),
      isTrue,
    );
  });

  test("a page's connector is not removable on its own", () async {
    // The fixture ships `home_page_connector.dart` for the wired `home` page.
    // Auto-detection used to resolve `HomePage` to it and delete it silently,
    // leaving the route pointing at nothing — the page's own canonical name is
    // `home`, so the substate/page resolver never saw a conflict to report.
    final connector = fx.file('app/lib/connectors/home_page_connector.dart');
    expect(connector.existsSync(), isTrue);

    for (final args in [
      ['remove', 'HomePage', '--apply'],
      ['remove', 'HomePage', '--kind', 'connector', '--apply'],
    ]) {
      final res = await runFrx(fx, args);
      expect(res.exitCode, 64, reason: '${args.join(' ')} should be refused');
      expect(res.stderr.toString(), contains('--kind page'));
      expect(
        connector.existsSync(),
        isTrue,
        reason: 'refused, so nothing was deleted',
      );
    }
  });

  test('nothing is written without --apply', () async {
    await ok(['add-widget', 'PreviewMe', '--dir', 'tiles', '--no-format']);
    final res = await runFrx(fx, ['remove', 'PreviewMe', '--kind', 'widget']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(
      fx.file('ui/lib/tiles/preview_me.dart').existsSync(),
      isTrue,
      reason: 'the destructive default is preview, for every kind',
    );
  });

  test('a name that reaches two widgets is refused, never picked', () async {
    // The regression this pins was a "helpful" rule: prefer the spelling typed
    // straight over a suffix expansion of it. With a hand-written `pin.dart`
    // already there, `add-widget Pin -k field` writes `pin_form_field.dart` —
    // and `remove Pin --kind widget --apply` then deleted `pin.dart`, a
    // different widget from the one that same name had just created. Under
    // `--apply` that is unrecoverable, and it broke the round-trip property
    // this file exists to hold.
    fx.file('ui/lib/inputs/pin.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class Pin {}\n');
    await ok([
      'add-widget',
      'Pin',
      '--dir',
      'inputs',
      '-k',
      'field',
      '--no-format',
    ]);

    final res = await runFrx(fx, [
      'remove',
      'Pin',
      '--kind',
      'widget',
      '--apply',
    ]);
    expect(res.exitCode, 64, reason: res.stdout.toString());
    expect(
      fx.file('ui/lib/inputs/pin.dart').existsSync(),
      isTrue,
      reason: 'refused, so neither candidate was touched',
    );
    expect(fx.file('ui/lib/inputs/pin_form_field.dart').existsSync(), isTrue);

    // And the refusal has to name both, with the class that reaches each —
    // one of them may not be reachable by name at all, which is worth saying
    // rather than leaving the reader to discover.
    expect(res.stderr.toString(), contains('PinFormField'));
    expect(res.stderr.toString(), contains('pin.dart'));

    // The one that *can* be named is removable by that name.
    await ok(['remove', 'PinFormField', '--kind', 'widget', '--apply']);
    expect(fx.file('ui/lib/inputs/pin_form_field.dart').existsSync(), isFalse);
    expect(fx.file('ui/lib/inputs/pin.dart').existsSync(), isTrue);
  });

  test('a name of no kind reports where it looked', () async {
    final res = await runFrx(fx, ['remove', 'Nope', '--kind', 'model']);
    expect(res.exitCode, 70);
    expect(res.stderr.toString(), contains('models/lib/nope.dart'));
  });

  test('a page-suffixed tab scaffolds one consistent spelling', () async {
    // `add-tabs` handed each --tab name raw to the scaffolder and stemmed to
    // the artifact, so a tab called `BasketPage` produced `class BasketPagePage`
    // inside `basket_page.dart`, a connector importing a `basket_page_page.dart`
    // nobody wrote, and a route registered as `BasketRoute`. Four spellings,
    // exit 0, and a project that does not compile.
    await ok([
      'add-tabs',
      'Main',
      '-t',
      'BasketPage',
      '-t',
      'Profile',
      '--no-format',
    ]);

    final page = fx.file('ui/lib/pages/basket_page.dart');
    expect(page.existsSync(), isTrue, reason: 'the file the artifact names');
    expect(page.readAsStringSync(), contains('class BasketPage extends'));

    final connector = fx.file('app/lib/connectors/basket_page_connector.dart');
    expect(
      connector.readAsStringSync(),
      contains("import 'package:ui/pages/basket_page.dart';"),
      reason: 'the connector has to import the file that was actually written',
    );
    expect(
      fx.read('app/lib/navigation/app_router.dart'),
      contains('BasketRoute'),
      reason: 'and the route has to match the class auto_route will generate',
    );
  });

  group('the name that created it removes it', () {
    // The property the two directions have to share, and the one nothing was
    // testing: `add` derives a path forward from what the user typed, `remove`
    // derives it backward, and they agreed only by having been written to
    // agree. Every kind, with the name a user would actually type.
    final cases = <String, ({List<String> add, List<String> remove})>{
      'model': (
        add: ['add-model', 'Task'],
        remove: ['Task', '--kind', 'model'],
      ),
      'service': (
        add: ['add-service', 'Sync'],
        remove: ['Sync', '--kind', 'service'],
      ),
      'connector': (
        add: ['add-connector', 'Toolbar'],
        remove: ['Toolbar', '--kind', 'connector'],
      ),
      'action': (
        add: ['add-action', 'ArchiveTask', '--state', 'log_in'],
        remove: ['ArchiveTask', '--kind', 'action'],
      ),
      'widget (no suffix)': (
        add: ['add-widget', 'TaskTile', '--dir', 'tiles'],
        remove: ['TaskTile', '--kind', 'widget'],
      ),
      // The kinds whose scaffolder renames what it was handed: `-k field`
      // writes `PinFormField`, `-k action` writes `SubmitButton`. The file on
      // disk is named after the class, not after the argument.
      'widget (--kind field)': (
        add: ['add-widget', 'Pin', '--dir', 'inputs', '--kind', 'field'],
        remove: ['Pin', '--kind', 'widget'],
      ),
      'widget (--kind action)': (
        add: ['add-widget', 'Submit', '--dir', 'buttons', '--kind', 'action'],
        remove: ['Submit', '--kind', 'widget'],
      ),
      // The name a user reaches for having just read the class. `add` never
      // stripped the suffix and `remove` always did, so `ArchiveTaskAction`
      // scaffolded `ArchiveTaskActionAction` in
      // `archive_task_action_action.dart` while removal looked for
      // `archive_task_action.dart`.
      'action (already suffixed)': (
        add: ['add-action', 'ArchiveTaskAction', '--state', 'log_in'],
        remove: ['ArchiveTaskAction', '--kind', 'action'],
      ),
      'connector (already suffixed)': (
        add: ['add-connector', 'ToolbarConnector'],
        remove: ['ToolbarConnector', '--kind', 'connector'],
      ),
      // Missed the first time, on the premise that `service` had no suffix
      // rule. `add-service` writes `class <Name>Service`, so it has one, and
      // `SyncService` scaffolded `SyncServiceService`.
      'service (already suffixed)': (
        add: ['add-service', 'SyncService'],
        remove: ['SyncService', '--kind', 'service'],
      ),
      // `add-enum` and `add-model` write to one directory and `remove --kind
      // model` covers both — untested until now, which is what the ticket asked
      // for rather than what it got.
      'enum': (
        add: ['add-enum', 'Status', '--value', 'pending', '--value', 'done'],
        remove: ['Status', '--kind', 'model'],
      ),
      // The two wired kinds — separate code paths in `remove_command`
      // (`_removeSubstate`, `_removePage`) that "every kind" did not cover.
      // `add-page HomePage` wrote `home_page_page.dart` with connector
      // `HomePagePageConnector` and route `HomePageRoute`, and the round trip
      // could not see it because removal did not strip either: the two
      // directions agreed on the wrong answer.
      'page': (
        add: ['add-page', 'Checkout'],
        remove: ['Checkout', '--kind', 'page'],
      ),
      'page (already suffixed)': (
        add: ['add-page', 'BasketPage'],
        remove: ['BasketPage', '--kind', 'page'],
      ),
      'substate': (
        add: ['add-substate', 'cart'],
        remove: ['cart', '--kind', 'substate'],
      ),
      // The doubled case for pages, which the widget row had and this did not
      // — which is why a double strip (once at the command, once in
      // `PageArtifact`) passed: the class went to `CheckoutPagePage`, the file
      // to `checkout_page.dart` and the route to `CheckoutRoute`, all three
      // disagreeing, at exit 0.
      'page (suffix already doubled)': (
        add: ['add-page', 'CheckoutPagePage'],
        remove: ['CheckoutPagePage', '--kind', 'page'],
      ),
      // The stripping had to be symmetric, not merely present: the scaffolder
      // stripped twice and removal once, so a doubly-suffixed name wrote
      // `submit_button.dart` and was looked for at `submit_button_button.dart`.
      'widget (suffix already doubled)': (
        add: [
          'add-widget',
          'SubmitButtonButton',
          '--dir',
          'buttons',
          '--kind',
          'action',
        ],
        remove: ['SubmitButtonButton', '--kind', 'widget'],
      ),
    };

    /// Every file under the fixture, by repo-relative path.
    Set<String> files() => {
      for (final e in fx.root.listSync(recursive: true).whereType<File>())
        p.relative(e.path, from: fx.root.path),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final before = files();
        await ok([...entry.value.add, '--no-format']);
        final written = files().difference(before);
        expect(
          written,
          isNotEmpty,
          reason: '${entry.value.add.join(' ')} wrote nothing',
        );

        final res = await runFrx(fx, [
          'remove',
          ...entry.value.remove,
          '--apply',
        ]);
        expect(
          res.exitCode,
          0,
          reason:
              'scaffolded with `${entry.value.add.join(' ')}`, so '
              '`frx remove ${entry.value.remove.join(' ')}` has to find it.\n'
              '${res.stderr}',
        );

        // The criterion, not merely "it exited 0": removal takes back exactly
        // what scaffolding wrote. A `remove` that finds the artifact and leaves
        // half of it is the failure `rm` already had.
        expect(
          files().intersection(written),
          isEmpty,
          reason:
              'left behind by `frx remove ${entry.value.remove.join(' ')}`: '
              '${files().intersection(written).join(', ')}',
        );
      });
    }
  });
}
