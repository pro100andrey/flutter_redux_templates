import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture.dart';

/// `remove` for the kinds that wire nothing central.
///
/// Each is scaffolded by its real `add-*` and removed again, because the
/// property under test is that removal takes the whole *set* the scaffolder
/// wrote. That is the difference from `rm`, which the traced runs reached for
/// sixty-odd times across six builds: `rm` deletes the path it is handed, and
/// the halves it leaves — a widget's mirrored preview, a model's `.freezed.dart`
/// — are what stops the package compiling.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Future<void> ok(List<String> args) async {
    final res = await runFrx(fx, args);
    expect(res.exitCode, 0, reason: '${args.join(' ')}\n${res.stderr}');
  }

  test('a widget goes with its mirrored preview', () async {
    await ok(['add-widget', 'TaskTile', '--dir', 'tiles', '--no-format']);
    expect(fx.file('ui/lib/tiles/task_tile.dart').existsSync(), isTrue);
    expect(
      fx.file('ui/lib/previews/tiles/task_tile.dart').existsSync(),
      isTrue,
      reason: 'add-widget writes the preview; the round trip needs it there',
    );

    await ok(['remove', 'TaskTile', '--kind', 'widget', '--apply']);
    expect(fx.file('ui/lib/tiles/task_tile.dart').existsSync(), isFalse);
    expect(
      fx.file('ui/lib/previews/tiles/task_tile.dart').existsSync(),
      isFalse,
      reason:
          'the preview is the half `rm` leaves — it imports a file that is '
          'gone, and the previewer loads the whole mirror tree',
    );
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

  test('a name of no kind reports where it looked', () async {
    final res = await runFrx(fx, ['remove', 'Nope', '--kind', 'model']);
    expect(res.exitCode, 70);
    expect(res.stderr.toString(), contains('models/lib/nope.dart'));
  });
}
