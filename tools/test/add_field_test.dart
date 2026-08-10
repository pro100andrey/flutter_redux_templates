import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx add-field` splices a field into an existing @freezed state class.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String state() =>
      fx.read('business/lib/redux/log_in/models/log_in_state.dart');

  test('adds a nullable field to the state factory', () async {
    final res = await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    // Comma-safe: the new field must be a separate parameter, not fused onto
    // the existing one (`valueString? nickname`).
    expect(state(), contains('String? value, String? nickname'));
  });

  test('a non-nullable field with --default gets @Default', () async {
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'count:int',
      '--default',
      '0',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(state(), contains('@Default(0) int count'));
  });

  test('a non-nullable field without --default is a usage error', () async {
    final res = await runFrx(fx, ['add-field', 'log_in', 'count:int']);
    expect(res.exitCode, 64);
    expect(res.stderr, contains('needs --default'));
  });

  test(
    'an IList type pulls in the fast_immutable_collections import',
    () async {
      final res = await runFrx(fx, [
        'add-field',
        'log_in',
        'tags:IList<String>',
        '--default',
        'IListConst([])',
      ]);
      expect(res.exitCode, 0, reason: res.stderr.toString());
      expect(state(), contains('fast_immutable_collections'));
      expect(state(), contains('IList<String> tags'));
    },
  );

  test('adding the same field twice is idempotent', () async {
    await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    final before = state();
    final res = await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('already present'));
    expect(state(), before);
  });

  test('--action scaffolds a Set<Field>Action setter', () async {
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'nickname:String?',
      '--action',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    final setter = fx.file(
      'business/lib/redux/log_in/actions/set_nickname_action.dart',
    );
    expect(setter.existsSync(), isTrue);
    final src = setter.readAsStringSync();
    expect(src, contains('class SetNicknameAction extends Action'));
    expect(src, contains('state.copyWith.logIn(nickname: nickname)'));
  });

  test('--action imports the package its field type comes from', () async {
    // The two axes this suite tested separately: `IList` + import was checked
    // on the state file and on selectors.dart, and `--action` was checked with
    // a `String?`. Crossing them is what caught a setter that declared
    // `final IList<String> tags;` with nothing importing IList.
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'tags:IList<String>',
      '--default',
      'IListConst([])',
      '--action',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    final src = fx
        .file('business/lib/redux/log_in/actions/set_tags_action.dart')
        .readAsStringSync();
    expect(src, contains('final IList<String> tags;'));
    expect(
      src,
      contains(
        "import 'package:fast_immutable_collections/"
        "fast_immutable_collections.dart';",
      ),
    );
  });

  test('a union case brings the file its union is named after', () async {
    // The hole the name-based lookup left: `add-model Result -c success` writes
    // `Result`, and the case class only as the redirect target
    //
    //   const factory Result.success() = ResultSuccess;
    //
    // so `ResultSuccess` is reached through `result.dart` and there is no
    // `result_success.dart` to find. Measured before the fix: the field landed
    // in all three files with nothing importing its type.
    await runFrx(fx, ['add-model', 'Result', '-c', 'loading', '-c', 'success']);
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'last:ResultSuccess?',
      '--action',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());

    expect(state(), contains('ResultSuccess? last'));
    expect(state(), contains("import 'package:models/result.dart';"));
    expect(
      fx.read('business/lib/redux/selectors.dart'),
      contains("import 'package:models/result.dart';"),
    );
    expect(
      fx
          .file('business/lib/redux/log_in/actions/set_last_action.dart')
          .readAsStringSync(),
      contains("import 'package:models/result.dart';"),
    );
  });

  test('a type no file in models supplies brings no import', () async {
    // The other side of the same lookup: a capitalised name that is not a model
    // must not pull in whatever file happens to mention it.
    final res = await runFrx(fx, ['add-field', 'log_in', 'when:DateTime?']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(state(), contains('DateTime? when'));
    expect(state(), isNot(contains('package:models/')));
  });

  test('--action never clobbers an existing setter', () async {
    final setter = fx.file(
      'business/lib/redux/log_in/actions/set_nickname_action.dart',
    );
    setter
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// hand-written setter\n');

    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'nickname:String?',
      '--action',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('already exists'));
    expect(setter.readAsStringSync(), '// hand-written setter\n');
  });

  test('--diff prints a unified diff of the edit', () async {
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'nickname:String?',
      '--diff',
      '--dry-run',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('--- a/'));
    expect(res.stdout, contains('@@'));
    // The changed factory line appears as an addition.
    expect(
      res.stdout,
      contains(
        '+  const factory LogInState({String? value, String? nickname})',
      ),
    );
    // Dry run — the file is untouched.
    expect(state(), isNot(contains('nickname')));
  });

  test('an unknown substate is a clean error', () async {
    final res = await runFrx(fx, ['add-field', 'nope', 'x:String?']);
    expect(res.exitCode, 70);
    expect(res.stderr, contains('nope'));
  });

  test('an unknown substate is a clean error under --force too', () async {
    // `--force` asks the state file what the field currently defaults to, and
    // that read used to happen *above* the guard: the same typo exited 255 with
    // a PathNotFoundException instead of 70 with the sentence. A guard that
    // holds for only some flag combinations is not a guard.
    final res = await runFrx(fx, ['add-field', 'nope', 'x:String?', '--force']);
    expect(res.exitCode, 70, reason: res.stderr.toString());
    expect(res.stderr, contains('nope'));
    expect(res.stderr, isNot(contains('Unhandled exception')));
  });

  String selectors() => fx.read('business/lib/redux/selectors.dart');

  test('the field gets a selector getter, typed like the field', () async {
    final res = await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(
      selectors(),
      contains('String? get nickname => _state.logIn.nickname;'),
    );
  });

  test('--no-selector leaves selectors.dart alone', () async {
    final before = selectors();
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'nickname:String?',
      '--no-selector',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(selectors(), before);
  });

  test('a dry run writes no selector either', () async {
    final before = selectors();
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'nickname:String?',
      '--dry-run',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(selectors(), before);
  });

  test('re-adding an existing field leaves one getter', () async {
    await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    final res = await runFrx(fx, ['add-field', 'log_in', 'nickname:String?']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect('get nickname'.allMatches(selectors()).length, 1);
  });

  test('an IList selector brings its import into selectors.dart', () async {
    // The getter lands in a different library than the state it reads. The
    // state file gets the fast_immutable_collections import; without it here
    // too, `IList` is undefined and selectors.dart stops compiling.
    final res = await runFrx(fx, [
      'add-field',
      'log_in',
      'tags:IList<String>',
      '--default',
      'IListConst([])',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(selectors(), contains('IList<String> get tags'));
    expect(selectors(), contains('fast_immutable_collections'));
  });

  test('the import is added once, not per field', () async {
    await runFrx(fx, [
      'add-field',
      'log_in',
      'tags:IList<String>',
      '--default',
      'IListConst([])',
    ]);
    await runFrx(fx, [
      'add-field',
      'log_in',
      'ids:IList<int>',
      '--default',
      'IListConst([])',
    ]);
    // Counting the directive, not the word — it appears twice inside one
    // `package:fast_immutable_collections/fast_immutable_collections.dart`.
    expect(
      "import 'package:fast_immutable_collections"
          .allMatches(selectors())
          .length,
      1,
      reason: selectors(),
    );
  });
}
