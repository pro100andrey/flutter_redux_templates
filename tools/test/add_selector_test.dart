import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx add-selector` adds a getter to a substate's Select<Pascal> block.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String selectors() => fx.read('business/lib/redux/selectors.dart');

  test(
    'adds a getter reading the state field of the same name by default',
    () async {
      final res = await runFrx(fx, [
        'add-selector',
        'log_in',
        'email',
        '--type',
        'String?',
      ]);
      expect(res.exitCode, 0, reason: res.stderr.toString());
      expect(selectors(), contains('String? get email => _state.logIn.email;'));
    },
  );

  test('--type pulls in the package that supplies it', () async {
    // selectors.dart need not already import what an arbitrary --type names.
    final res = await runFrx(fx, [
      'add-selector',
      'log_in',
      'tags',
      '--type',
      'IList<String>',
      '--expr',
      '_state.logIn.tags',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(
      selectors(),
      contains(
        "import 'package:fast_immutable_collections/"
        "fast_immutable_collections.dart';",
      ),
    );
  });

  test('honours a custom --expr', () async {
    final res = await runFrx(fx, [
      'add-selector',
      'log_in',
      'isSignedIn',
      '--type',
      'bool',
      '--expr',
      '_state.logIn.value != null',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(
      selectors(),
      contains('bool get isSignedIn => _state.logIn.value != null;'),
    );
  });

  test('lands inside the right SelectLogIn block', () async {
    await runFrx(fx, ['add-selector', 'log_in', 'email', '--type', 'String?']);
    final src = selectors();
    // The getter sits between SelectLogIn's opening and the next declaration.
    final block = src.substring(
      src.indexOf('extension type SelectLogIn'),
      src.indexOf('}', src.indexOf('extension type SelectLogIn')),
    );
    expect(block, contains('get email'));
    // The other selector type is untouched.
    expect(src, contains('extension type SelectConnectivity'));
  });

  test('adding the same selector twice is idempotent', () async {
    await runFrx(fx, ['add-selector', 'log_in', 'email', '--type', 'String?']);
    final before = selectors();
    final res = await runFrx(fx, [
      'add-selector',
      'log_in',
      'email',
      '--type',
      'String?',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('already present'));
    expect(selectors(), before);
  });

  test('an unwired substate is a clean error', () async {
    final res = await runFrx(fx, ['add-selector', 'nope', 'x']);
    expect(res.exitCode, 70);
    expect(res.stderr, contains('SelectNope'));
  });
}
