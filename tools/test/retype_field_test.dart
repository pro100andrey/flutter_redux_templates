import 'package:test/test.dart';

import 'support/fixture.dart';

/// `add-field --force` on a field that already exists: rewrite its declaration
/// rather than answering "already present".
///
/// The gap this closes was created by closing another one. `add-substate --kind
/// table` scaffolds `IMap<int, Object>` because the element type is not known
/// when the slice is made, and tightening it to `IMap<int, Task>` was hand work
/// — fine while a state file could be hand-edited. Once the guard refused that
/// channel there was no way left, and a traced run shipped `Object` because of
/// it: the agent tried `Write`, then `Edit`, was refused both times, probed
/// `add-field`, and found it silently did nothing.
void main() {
  late Fixture fx;

  setUp(() {
    fx = Fixture.create();
    // A model to retype *to*, so the import resolution has a file to find.
    fx.file('models/lib/task.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class Task {}\n');
  });
  tearDown(() => fx.dispose());

  Future<void> ok(List<String> args) async {
    final res = await runFrx(fx, args);
    expect(res.exitCode, 0, reason: '${args.join(' ')}\n${res.stderr}');
  }

  test(
    'without --force the field is left alone, and the way out is named',
    () async {
      await ok(['add-field', 'log_in', 'note:String?', '--no-format']);
      final res = await runFrx(fx, [
        'add-field',
        'log_in',
        'note:int?',
        '--no-format',
      ]);
      expect(res.exitCode, 0);
      expect(
        res.stdout.toString(),
        contains('--force'),
        reason: 'a no-op has to say what would not be one',
      );
      expect(
        fx.read('business/lib/redux/log_in/models/log_in_state.dart'),
        contains('String? note'),
        reason: 'nothing changed without --force',
      );
    },
  );

  test('--force rewrites the declaration', () async {
    await ok(['add-field', 'log_in', 'note:String?', '--no-format']);
    await ok(['add-field', 'log_in', 'note:int?', '--force', '--no-format']);
    final state = fx.read('business/lib/redux/log_in/models/log_in_state.dart');
    expect(state, contains('int? note'));
    expect(state, isNot(contains('String? note')));
  });

  test('the selector getter follows, so the two cannot disagree', () async {
    await ok(['add-field', 'log_in', 'note:String?', '--no-format']);
    await ok(['add-field', 'log_in', 'note:int?', '--force', '--no-format']);
    final selectors = fx.read('business/lib/redux/selectors.dart');
    expect(selectors, contains('int? get note'));
    expect(
      selectors,
      isNot(contains('String? get note')),
      reason: 'a facade claiming String over an int field does not compile',
    );
  });

  test('a type this project defines brings its import', () async {
    // The half that made the retype useless on its own: `IMap<int, Task>`
    // without `package:models/task.dart` is a file that does not compile, and
    // the guard refuses the hand edit that would add it.
    await ok(['add-field', 'log_in', 'picked:Object?', '--no-format']);
    await ok(['add-field', 'log_in', 'picked:Task?', '--force', '--no-format']);
    final state = fx.read('business/lib/redux/log_in/models/log_in_state.dart');
    expect(state, contains('Task? picked'));
    expect(
      state,
      contains("import 'package:models/task.dart';"),
      reason: 'the models package name is read from its pubspec, not assumed',
    );
  });

  test('retyping to the same type changes nothing', () async {
    await ok(['add-field', 'log_in', 'note:String?', '--no-format']);
    final before = fx.read(
      'business/lib/redux/log_in/models/log_in_state.dart',
    );
    await ok(['add-field', 'log_in', 'note:String?', '--force', '--no-format']);
    expect(
      fx.read('business/lib/redux/log_in/models/log_in_state.dart'),
      before,
      reason: '--force is not a reason to rewrite what already agrees',
    );
  });

  test('a default is rewritten with the type it belongs to', () async {
    await ok([
      'add-field',
      'log_in',
      'count:int',
      '--default',
      '0',
      '--no-format',
    ]);
    await ok([
      'add-field',
      'log_in',
      'count:double',
      '--default',
      '0.0',
      '--force',
      '--no-format',
    ]);
    final state = fx.read('business/lib/redux/log_in/models/log_in_state.dart');
    expect(state, contains('@Default(0.0) double count'));
    expect(state, isNot(contains('@Default(0) int count')));
  });

  test('--force refuses to drop a default it was not told about', () async {
    // The silent one. Retyping rebuilds the declaration from this invocation, so
    // an `@Default(0)` the old one carried and the new one does not is written
    // away — changing what `AppState.initial()` produces for every reader, with
    // nothing in the report saying so. A nullable target does not require
    // `--default`, which is exactly where it slipped through.
    await ok([
      'add-field',
      'log_in',
      'count:int',
      '--default',
      '0',
      '--no-format',
    ]);

    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'count:int?',
      '--force',
      '--no-format',
    ]);
    expect(res.exitCode, 64, reason: res.stdout.toString());
    expect(res.stderr.toString(), contains('@Default'.replaceAll('@', '')));
    expect(
      fx.read('business/lib/redux/log_in/models/log_in_state.dart'),
      contains('@Default(0) int count'),
      reason: 'refused, so nothing was rewritten',
    );

    // Saying so explicitly is the way through — either keeping it or changing it.
    await ok([
      'add-field',
      'log_in',
      'count:int?',
      '--default',
      '0',
      '--force',
      '--no-format',
    ]);
    expect(
      fx.read('business/lib/redux/log_in/models/log_in_state.dart'),
      contains('@Default(0) int? count'),
    );
  });

  test('a type this project defines reaches the setter action too', () async {
    // The setter was the one file of the three that never got the project-type
    // lookup: the state file and the facade both did. `final Task? picked;` in a
    // file importing only app_state.dart is an undefined name.
    await ok([
      'add-field',
      'log_in',
      'picked:Task?',
      '--action',
      '--no-format',
    ]);
    expect(
      fx.read('business/lib/redux/log_in/actions/set_picked_action.dart'),
      contains("import 'package:models/task.dart';"),
    );
  });

  test('--force does not invent a field that is not there', () async {
    // It is still `add-field`: an absent field is added, not refused, and the
    // flag changes nothing about that path.
    await ok([
      'add-field',
      'log_in',
      'fresh:String?',
      '--force',
      '--no-format',
    ]);
    expect(
      fx.read('business/lib/redux/log_in/models/log_in_state.dart'),
      contains('String? fresh'),
    );
  });
}
