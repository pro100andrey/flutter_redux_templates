import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  // __complete resolves substate/route names from the current directory, so run
  // it with cwd = the fixture root (and no injected --root polluting the words).
  Future<List<String>> complete(List<String> words) async {
    final res = await runFrxIn(fx, ['__complete', '--', ...words]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    return (res.stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
  }

  group('completions <shell>', () {
    // `completions` has no --root option, so use the cwd-based runner that
    // doesn't append one.
    test('bash script wires _frx_complete to __complete', () async {
      final res = await runFrxIn(fx, ['completions', 'bash']);
      expect(res.exitCode, 0);
      expect(res.stdout, contains('complete -o default -F _frx_complete frx'));
      expect(res.stdout, contains('frx __complete --'));
    });

    test('zsh and fish scripts are shell-appropriate', () async {
      expect(
        (await runFrxIn(fx, ['completions', 'zsh'])).stdout,
        contains('compdef _frx frx'),
      );
      expect(
        (await runFrxIn(fx, ['completions', 'fish'])).stdout,
        contains('complete -c frx'),
      );
    });

    test('an unknown shell is a usage error', () async {
      final res = await runFrxIn(fx, ['completions', 'powershell']);
      expect(res.exitCode, 64);
    });
  });

  group('__complete', () {
    test(
      'completes command names, deduped and without the hidden one',
      () async {
        final all = await complete(['']);
        expect(all, containsAll(['add-substate', 'rename', 'doctor', 'which']));
        expect(all, isNot(contains('__complete')));
        expect(all.toSet().length, all.length); // no duplicates
      },
    );

    test('filters commands by prefix', () async {
      final add = await complete(['add-']);
      expect(add, isNotEmpty);
      expect(add.every((c) => c.startsWith('add-')), isTrue);
    });

    test('completes a command\'s flags after a dash', () async {
      final flags = await complete(['add-substate', 'x', '--']);
      expect(flags, contains('--kind'));
      expect(flags, contains('--force'));
    });

    test('completes --kind allowed values', () async {
      final kinds = await complete(['add-substate', 'x', '--kind', '']);
      expect(kinds, containsAll(['value', 'search', 'table']));
    });

    test('completes substate + route names for rename', () async {
      final names = await complete(['rename', '']);
      expect(names, contains('log_in')); // substate
      expect(names, contains('home')); // route
    });

    test('completes only substate names for add-field', () async {
      final names = await complete(['add-field', '']);
      expect(names, contains('log_in'));
      expect(names, isNot(contains('home'))); // a route is not a substate
    });
  });
}
