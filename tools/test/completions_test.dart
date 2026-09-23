import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  // __complete resolves substate/route names from the current directory, so run
  // it with cwd = the fixture root (and no injected --root polluting the
  // words).
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

    // install.sh appends `eval "$(frx completions zsh)"` to ~/.zshrc, and a
    // stock macOS zsh never runs compinit: an unguarded `compdef` printed
    // `command not found: compdef` at every new shell. The script registers
    // only where the completion system is loaded, and is silent elsewhere.
    test('the zsh script registers only when compinit has run', () async {
      final script =
          (await runFrxIn(fx, ['completions', 'zsh'])).stdout as String;
      expect(
        script,
        contains(r'if (( $+functions[compdef] )); then compdef _frx frx; fi'),
      );

      final zsh = _which('zsh');
      if (zsh == null) {
        markTestSkipped('zsh is not installed');
        return;
      }
      // -f: no startup files, so no compinit — the stock macOS case.
      final bare = await Process.run(zsh, ['-f', '-c', script]);
      expect(bare.stderr, isEmpty);
      expect(bare.exitCode, 0);

      // And with the completion system loaded, `_frx` is what completes frx.
      final loaded = await Process.run(zsh, [
        '-f',
        '-c',
        [
          'autoload -Uz compinit && compinit -u -D',
          script,
          r'print -r -- ${_comps[frx]}',
        ].join('\n'),
      ]);
      expect(loaded.stderr, isEmpty);
      expect((loaded.stdout as String).trim(), '_frx');
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

    test("completes a command's flags after a dash", () async {
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

/// [name]'s path on PATH, or null. Not on Windows, where no shell this file
/// runs has a script to test.
String? _which(String name) {
  if (Platform.isWindows) {
    return null;
  }
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    final file = File('$dir/$name');
    if (dir.isNotEmpty && file.existsSync()) {
      return file.path;
    }
  }
  return null;
}
