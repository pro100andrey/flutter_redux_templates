import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx watch --print` resolves the build_runner incantation without running it.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  test('defaults to the whole workspace from the repo root', () async {
    final res = await runFrx(fx, ['watch', '--print']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(
      res.stdout,
      contains(
        'dart run build_runner watch --workspace --delete-conflicting-outputs',
      ),
    );
  });

  test('--package narrows to one package (no --workspace)', () async {
    final res = await runFrx(fx, ['watch', '--package', 'business', '--print']);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, contains('business'));
    expect(res.stdout, isNot(contains('--workspace')));
    expect(res.stdout, contains('build_runner watch'));
  });

  test('--no-delete-conflicting-outputs drops the flag', () async {
    final res = await runFrx(fx, [
      'watch',
      '--no-delete-conflicting-outputs',
      '--print',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(res.stdout, isNot(contains('--delete-conflicting-outputs')));
  });

  test('an unknown --package is a clean error', () async {
    final res = await runFrx(fx, ['watch', '--package', 'nope', '--print']);
    expect(res.exitCode, 70);
    expect(res.stderr, contains('nope'));
  });
}
