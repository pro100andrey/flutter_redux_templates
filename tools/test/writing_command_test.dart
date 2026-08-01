import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/commands/writing_command.dart';
import 'package:tools/src/engine/build_step.dart';
import 'package:tools/src/engine/changeset.dart';
import 'package:tools/src/util/console.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// "A command that writes files" as a module rather than a convention.
///
/// Exercised through a command built on it, not in isolation: the thing worth
/// pinning is what a *command* gets for free — the flags it did not declare, the
/// tail it did not write, and the batch seam it does not know about.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  /// Runs [command] through frx's own runner, so the exit codes and the `✗`
  /// rendering under test are the real ones — a bare [CommandRunner] has
  /// neither, and `refuse` would escape as an unhandled crash.
  Future<Ran> run(Command<int> command, List<String> args) async {
    final captured = CapturedConsole();
    final runner = FrxRunner()..addCommand(command);
    final code = await withConsole(
      captured,
      () => runner.runFrx([command.name, ...args, '--root', fx.root.path]),
    );
    return (exitCode: code, stdout: captured.output, stderr: captured.errors);
  }

  group('the flags a command does not declare', () {
    test('every writing command takes format, json and root', () {
      final parser = _Probe().argParser;
      expect(parser.options.keys, containsAll(['format', 'json', 'root']));
      // `--format` defaults on: a written file lands formatted unless asked
      // otherwise.
      expect(parser.options['format']!.defaultsTo, isTrue);
    });

    test('the optional ones are opt-in, and off by default', () {
      expect(_Probe().argParser.options.keys, isNot(contains('build-runner')));
      expect(_Probe().argParser.options.keys, isNot(contains('diff')));
      expect(_Codegen().argParser.options.keys, contains('build-runner'));
    });

    test('a command declaring a flag the base owns is a hard error', () {
      // `args` throws on a duplicate, which is the point: the invariant is
      // structural rather than checked by a test that walks the registry.
      expect(_Redeclares.new, throwsA(isA<ArgumentError>()));
    });
  });

  group('the tail a command does not write', () {
    test('writes the planned files and reports the count', () async {
      final res = await run(_Probe(), []);
      expect(res.exitCode, 0);
      expect(res.stdout, contains('Probe "thing"'));
      expect(res.stdout, contains('Wrote 1 file(s).'));
      expect(File(p.join(fx.root.path, 'probe.txt')).existsSync(), isTrue);
    });

    test('--dry-run writes nothing', () async {
      final res = await run(_Probe(), ['--dry-run']);
      expect(res.exitCode, 0);
      expect(File(p.join(fx.root.path, 'probe.txt')).existsSync(), isFalse);
    });

    test(
      'refuses to overwrite without --force, with the shared exit code',
      () async {
        File(p.join(fx.root.path, 'probe.txt')).writeAsStringSync('mine\n');
        final res = await run(_Probe(), []);
        // 70 is the contract the editor reads: `scaffold.ts` retries with --force.
        expect(res.exitCode, 70);
        expect(res.stderr, contains('already exists'));
        expect(
          File(p.join(fx.root.path, 'probe.txt')).readAsStringSync(),
          'mine\n',
        );
      },
    );

    test('--force overwrites', () async {
      File(p.join(fx.root.path, 'probe.txt')).writeAsStringSync('mine\n');
      expect((await run(_Probe(), ['--force'])).exitCode, 0);
      expect(
        File(p.join(fx.root.path, 'probe.txt')).readAsStringSync(),
        contains('written by the probe'),
      );
    });

    test('--json emits the changeset and nothing else', () async {
      final res = await run(_Probe(), ['--json']);
      final json = jsonDecode(res.stdout) as Map<String, dynamic>;
      expect(json['command'], 'probe');
      expect(json['applied'], isTrue);
      expect(json['changes'], isA<List<dynamic>>());
      // The header and the file list are for a human; stdout has to stay
      // parseable.
      expect(res.stdout, isNot(contains('Probe "thing"')));
    });

    test("the command's own narration lands between plan and result", () async {
      final res = await run(_Probe(), []);
      expect(
        res.stdout.indexOf('the probe says so'),
        greaterThan(res.stdout.indexOf('Files:')),
      );
      expect(
        res.stdout.indexOf('the probe says so'),
        lessThan(res.stdout.indexOf('Wrote')),
      );
    });
  });

  group('the plan, without applying it', () {
    // The payoff of handing a plan back rather than performing it: what a
    // command decided is readable without a process, a workspace teardown or a
    // captured stdout. Nothing here writes a file.
    test('says what it would change, and applies nothing', () async {
      final repo = FrxWorkspace(fx.root);
      final plan = await _Probe().planFor(repo, _noArgs);
      expect(plan.header, 'Probe "thing"');
      expect(
        plan.changes.changes.single,
        isA<WriteFile>().having((c) => p.basename(c.path), 'path', 'probe.txt'),
      );
      expect(File(p.join(fx.root.path, 'probe.txt')).existsSync(), isFalse);
    });

    test('a refusal is reachable without running the command', () async {
      expect(
        () => _Refuses().planFor(FrxWorkspace(fx.root), _noArgs),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('refusing', () {
    test('names what to fix, exits 70, and writes nothing', () async {
      final res = await run(_Refuses(), []);
      expect(res.exitCode, 70);
      expect(res.stderr, contains('✗ nothing doing here'));
      expect(res.stdout, isEmpty);
    });
  });

  group('inside a batch', () {
    test('the write stages into the enclosing transaction, undoably', () async {
      final transaction = WriteTransaction();
      final file = File(p.join(fx.root.path, 'probe.txt'));

      await withTransaction(transaction, () => run(_Probe(), []));
      expect(file.existsSync(), isTrue);
      expect(transaction.written, contains(file.path));
      // The per-intent report the batch merges into one.
      expect(transaction.reports, hasLength(1));

      // A batch fails or lands as one: intent five failing takes the first four
      // back with it.
      transaction.rollback();
      expect(file.existsSync(), isFalse);
    });

    test('the codegen step is handed over rather than run', () async {
      final transaction = WriteTransaction();
      await withTransaction(transaction, () => run(_Codegen(), []));
      // Codegen is outside the transaction and runs once after it, not once
      // per intent.
      expect(transaction.buildSteps, hasLength(1));
      transaction.rollback();
    });

    test('the report goes to the transaction, for the batch to merge', () async {
      // Narration is silenced by the batch's own `withConsole`, not here; what
      // the base owes the transaction is the per-intent report it merges into
      // one.
      final transaction = WriteTransaction();
      await withTransaction(transaction, () => run(_Probe(), ['--json']));
      expect(transaction.reports, hasLength(1));
      transaction.rollback();
    });
  });
}

/// Empty results, for the tests that read a plan rather than run a command.
final _noArgs = ArgParser().parse(const []);

/// A command that writes one file, so the base's tail has something to carry.
class _Probe extends WritingCommand {
  @override
  String get name => 'probe';

  @override
  String get description => 'Writes a probe file.';

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async =>
      WritePlan(
        changes: Changeset([
          WriteFile(
            p.join(repo.root.path, 'probe.txt'),
            'written by the probe',
          ),
        ]),
        header: 'Probe "thing"',
        narrate: () => console.out.writeln('  • the probe says so'),
      );
}

/// Opts into the codegen flag, and hands back a build step.
class _Codegen extends WritingCommand {
  @override
  String get name => 'codegen';

  @override
  String get description => 'Writes a file that needs generating.';

  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final target = p.join(repo.root.path, 'business', 'lib', 'gen.dart');
    return WritePlan(
      changes: Changeset([WriteFile(target, '// needs generating\n')]),
      header: 'Codegen "thing"',
      build: (written) => BuildStep.build(
        FrxWorkspace.packageRootOf(written.first),
        nextHint: 'generate code',
      ),
    );
  }
}

/// Refuses, to pin the one way of saying so.
class _Refuses extends WritingCommand {
  @override
  String get name => 'refuses';

  @override
  String get description => 'Always refuses.';

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async =>
      refuse('nothing doing here');
}

/// Redeclares a flag the base already owns.
class _Redeclares extends WritingCommand {
  @override
  String get name => 'redeclares';

  @override
  String get description => 'Declares --root a second time.';

  @override
  void describeArgs(ArgParser parser) => parser.addOption('root');

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async =>
      WritePlan(changes: Changeset(), header: 'never');
}
