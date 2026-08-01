import 'package:args/command_runner.dart';
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/commands/frx_command.dart';
import 'package:tools/src/scaffold/artifact_templates.dart';
import 'package:tools/src/util/casing.dart';

/// A throwaway command that just exposes what [NameArg.requireName] parsed.
class _Probe extends Command<int> with NameArg {
  Casing? captured;

  @override
  String get name => 'probe';
  @override
  String get description => 'probe';

  @override
  String get invocation => 't probe <thing>';

  @override
  List<String> get positionals => const ['thing'];

  @override
  Future<int> run() async {
    captured = requireName();
    return 0;
  }
}

void main() {
  _optionWiringTests();
  late _Probe probe;
  late CommandRunner<int> runner;

  setUp(() {
    probe = _Probe();
    runner = CommandRunner<int>('t', 't')..addCommand(probe);
  });

  test('parses a single positional name to a Casing', () async {
    await runner.run(['probe', 'user profile']);
    expect(probe.captured?.snake, 'user_profile');
  });

  test('no positional argument → UsageException', () {
    expect(runner.run(['probe']), throwsA(isA<UsageException>()));
  });

  test('two positional arguments → UsageException', () {
    expect(runner.run(['probe', 'a', 'b']), throwsA(isA<UsageException>()));
  });

  test('an invalid name → UsageException naming the argument', () {
    expect(
      runner.run(['probe', '2bad']),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Invalid thing'), contains('2bad')),
        ),
      ),
    );
  });
}

void _optionWiringTests() {
  /// Every command the runner registers, including subcommands.
  Iterable<Command<int>> allCommands(Iterable<Command<int>> from) sync* {
    for (final c in from) {
      yield c;
      yield* allCommands(c.subcommands.values.cast());
    }
  }

  group('option wiring', () {
    final commands = allCommands(FrxRunner().commands.values.cast()).toList();

    test('every allowedHelp key is a value the option accepts', () {
      // The invariant that catches an edit landing in the wrong option: after
      // one did, `--kind` advertised the mixin names while still accepting
      // only sync/async/waiting — and `--mixin` had been swallowed whole.
      for (final c in commands) {
        for (final entry in c.argParser.options.entries) {
          final option = entry.value;
          final allowedHelp = option.allowedHelp;
          if (allowedHelp == null) continue;
          expect(
            option.allowed ?? const <String>[],
            containsAll(allowedHelp.keys),
            reason: '${c.name} --${entry.key}',
          );
        }
      }
    });

    test('a --json command also takes --root', () {
      // The editor reads every machine-readable command through one helper
      // that appends `--json --root <root>`. A command that emits JSON but
      // refuses `--root` is unreachable from there — and the failure is quiet,
      // because the caller treats "could not read" as "nothing to offer".
      //
      // Kept after the writing commands moved onto a base that declares both
      // together, because that base is not the only way into this parser.
      // Every `list-*`, `doctor`, `graph`, `flow` and `which` reads rather than
      // writes, and `batch` and `rename` write without extending it — all of
      // them declare `--json` and `--root` by hand, and any of them can drop
      // one.
      //
      // The exemption is the rule's own reason read backwards: a command that
      // does not act on an existing repository has no root to be given, and
      // cannot be reached by the helper that would supply one.
      const noRepositoryToRoot = {'create'};

      for (final c in commands) {
        if (!c.argParser.options.containsKey('json')) continue;
        if (noRepositoryToRoot.contains(c.name)) continue;
        expect(
          c.argParser.options,
          contains('root'),
          reason: '${c.name} emits --json',
        );
      }
    });

    test('every writing command also takes --json', () {
      // The counterpart of the check above, and the one the write format needs:
      // eight reading commands emitted machine output and no writing command
      // did, which is backwards for an agent — reading source is what it
      // already does well.
      //
      // "Writing command" is read off `--format`, which is exactly the set that
      // changes files (`frx new` is the stated exception: it is a dialogue, and
      // it prints the flag-driven command it would run so a non-interactive
      // caller uses that instead).
      //
      // Kept for the same reason as the check above, and for two commands in
      // particular: `rename` and `batch` declare `--format` themselves, so the
      // pairing the base guarantees for everything else is still theirs to get
      // right.
      for (final c in commands) {
        if (!c.argParser.options.containsKey('format')) continue;
        expect(
          c.argParser.options,
          contains('json'),
          reason: '${c.name} writes files',
        );
      }
    });

    test('a command\'s usage line names the arguments it declares', () {
      // The arity message is derived from `positionals`, and the usage line
      // printed beside it is hand-written. They said different things before
      // there was a declaration at all — `add-nav` answered "give exactly two
      // pages" under a usage line reading `<from> <to>` — and nothing checked.
      for (final c in commands) {
        if (c is! NameArg) continue;
        for (final arg in c.positionals) {
          expect(
            c.invocation,
            contains('<' + arg + '>'),
            reason:
                '${c.name} declares <$arg> but its invocation does not '
                'mention it',
          );
        }
      }
    });

    test('add-action still takes every mixin the catalogue declares', () {
      // `--mixin` is registered in the same cascade as `--kind`; an edit to
      // one can delete the other, and nothing downstream notices until a user
      // runs the command.
      final addAction = commands.firstWhere((c) => c.name == 'add-action');
      final mixin = addAction.argParser.options['mixin'];
      expect(mixin, isNotNull, reason: '--mixin is registered');
      expect(mixin!.isMultiple, isTrue, reason: 'repeatable');
      expect(mixin.allowed, containsAll(ActionMixin.values.map((m) => m.name)));
      expect(addAction.argParser.options['kind']?.allowed, [
        'sync',
        'async',
        'waiting',
      ]);
    });

    test('the parser accepts a real invocation with mixins', () {
      final addAction = commands.firstWhere((c) => c.name == 'add-action');
      final parsed = addAction.argParser.parse([
        '--state',
        'logIn',
        '--kind',
        'async',
        '-m',
        'noDialog',
        '-m',
        'retry',
      ]);
      expect(parsed['mixin'], ['noDialog', 'retry']);
    });
  });
}
