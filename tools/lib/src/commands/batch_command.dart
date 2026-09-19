import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../engine/write_path.dart';
import '../engine/write_report.dart';
import '../refusal.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'batch_declaration.dart';
import 'options.dart';

/// A feature's worth of artifacts, declared once and wired in **one
/// transaction**.
///
/// Building a feature meant several invocations — two substates, three pages,
/// the navigation between them — each its own unit, each potentially running
/// codegen. Atomicity changed what that is worth: a batch is not merely fewer
/// keystrokes, it is **one rollback boundary where eight calls are eight
/// boundaries**, and a failure at the fifth call leaves the first four applied.
///
/// **The input is a declaration of intents** — the commands you would have
/// typed, as data; what one may say, and how it is read, is
/// `batch_declaration.dart`. What is here is running them: one transaction,
/// one report, one codegen per package.
class BatchCommand extends Command<int> {
  BatchCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Report the combined plan without keeping it. The batch is applied '
            'and unwound — see the note in the README.',
      )
      ..addFlag(
        'build-runner',
        abbr: 'b',
        negatable: false,
        help:
            'Run build_runner once after the batch, in each package it wrote.',
      )
      ..addFlag(
        'format',
        defaultsTo: true,
        help: 'Run `dart format` once on everything the batch wrote.',
      )
      ..addFlag('json', negatable: false, help: kMachineHelp)
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'batch';

  @override
  String get description =>
      'Wire a declared list of artifacts in one transaction (file or stdin).';

  @override
  String get invocation => 'frx batch <file.json>|- [--dry-run]';

  @override
  List<String> get aliases => ['bat'];

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException(
        'Give exactly one declaration: a file path, or `-` for standard input.',
      );
    }
    final source = results.rest.single;

    final String raw;
    try {
      raw = source == '-'
          ? await console.stdinText()
          : File(source).readAsStringSync();
    } on Object catch (e) {
      console.err.writeln('✗ could not read the declaration: $e');
      return 70;
    }

    final List<Intent> intents;
    try {
      intents = parseBatchDeclaration(raw);
    } on FormatException catch (e) {
      // Reported before anything runs, so a malformed declaration cannot apply
      // part of itself.
      console.err.writeln('✗ ${e.message}');
      return 64;
    }

    final repo = FrxWorkspace.locate(startDir: results['root'] as String?);
    final dryRun = results.flag('dry-run');
    final asJson = results.flag('json');

    // One boundary for the whole batch.
    final transaction = WriteTransaction();
    _Failure? failure;
    final done = <Intent>[];

    // Each intent's own narration is swallowed: the batch reports the batch,
    // and a `--json` consumer's stdout must carry one object. The captured
    // output is what the failure report quotes.
    final captured = CapturedConsole();
    await withConsole(
      captured,
      () => withTransaction(transaction, () async {
        for (final intent in intents) {
          // Every way an intent can refuse is caught here, because the batch
          // owns the unwind: a `FrxRefusal` escaping to the runner's own
          // handler would report the refusal and leave the transaction half
          // applied, with nobody left to roll it back.
          final int code;
          try {
            code =
                await runner!.run([...intent.argv, '--root', repo.root.path]) ??
                0;
          } on UsageException catch (e) {
            failure = _Failure(intent, 64, e.message);
            return;
          } on FrxRefusal catch (e) {
            failure = _Failure(intent, 70, e.message);
            return;
          } on Object catch (e) {
            failure = _Failure(intent, 70, '$e');
            return;
          }
          if (code != 0) {
            failure = _Failure(intent, code, captured.errors);
            return;
          }
          done.add(intent);
        }
      }),
    );

    if (failure case final failed?) {
      _reportRollback(transaction.rollback());
      console.err
        ..writeln(
          '✗ intent ${done.length + 1} of ${intents.length} failed '
          '(exit ${failed.code}): ${failed.intent.description}',
        )
        ..writeln('  ${failed.reason}')
        ..writeln(
          '  Nothing was written. Intents apply in the order written, so a '
          'prerequisite has to come before what needs it.',
        );
      return failed.code;
    }

    final report = WriteReport.batch(name, transaction.reports);

    if (dryRun) {
      // The batch really was applied, and is now unwound. Planning each intent
      // against the untouched tree would be a different question: `add-nav`
      // refuses a destination that is not registered, so intent five's plan
      // does not exist until intents one to four have happened.
      final planned = _plannedBuild(transaction);
      _reportRollback(transaction.rollback());
      console.out.writeln(
        asJson
            ? report.render(applied: false, build: planned)
            : '${_humanPlan(intents, report, repo)}\n'
                  'Dry run — nothing kept.',
      );
      return 0;
    }

    // Outside the transaction — the same pair `apply` runs for one changeset.
    await settle(
      transaction,
      format: results.flag('format'),
      repoRoot: repo.root,
      report: !asJson,
    );
    final built = await _runBuilds(
      transaction,
      enabled: results.flag('build-runner'),
      report: !asJson,
    );

    console.out.writeln(
      asJson
          ? report.render(applied: true, build: built)
          : '${_humanPlan(intents, report, repo)}\n'
                '✓ ${intents.length} intent(s), '
                '${transaction.written.length} file(s) written.',
    );
    return 0;
  }

  /// The build step as a planned result, so the two states are one shape.
  BuildReport? _plannedBuild(WriteTransaction transaction) {
    final step = _byPackage(transaction).values.firstOrNull;
    return step == null ? null : plannedBuild(step);
  }

  /// One step per package: two substates in `business` are one build, not two.
  Map<String, BuildStep> _byPackage(WriteTransaction transaction) {
    final byPackage = <String, BuildStep>{};
    for (final step in transaction.buildSteps) {
      byPackage.putIfAbsent(step.packageRoot, () => step);
    }
    return byPackage;
  }

  /// Runs each package's build once, and reports the first that mattered.
  Future<BuildReport?> _runBuilds(
    WriteTransaction transaction, {
    required bool enabled,
    required bool report,
  }) async {
    final byPackage = _byPackage(transaction);
    if (byPackage.isEmpty) {
      return null;
    }
    final steps = byPackage.values.toList();
    // `ran` and `handedToWatch` are aggregated rather than taken from the first
    // package, because they are the load-bearing fields: reporting the first
    // package's outcome would say nothing was handed to a watch while another
    // package's build had been. `package` and `command` name the first — the
    // human report lists every one, and the README says so.
    var ran = false;
    var handedToWatch = false;
    int? watchPid;
    for (final step in steps) {
      final built = await runBuild(step, enabled: enabled, report: report);
      ran |= built.ran;
      handedToWatch |= built.handedToWatch;
      watchPid ??= built.watchPid;
    }
    return (
      package: steps.first.packageRoot,
      command: buildCommandLine(steps.first),
      ran: ran,
      handedToWatch: handedToWatch,
      watchPid: watchPid,
    );
  }

  /// The human plan: what each intent was, and what the batch touched.
  /// The intents, then what they did — in the CLI's own plan vocabulary.
  ///
  /// Rendered from [WriteReport.human] rather than from the transaction's flat
  /// `written`/`removed` lists, which carry no operation: every change came out
  /// as `write`, including the overwrites, edits and moves that every
  /// single-command plan names properly. See [WriteReport.human].
  String _humanPlan(
    List<Intent> intents,
    WriteReport report,
    FrxWorkspace repo,
  ) {
    final out = StringBuffer()..writeln('Batch (${intents.length} intent(s)):');
    for (final intent in intents) {
      out.writeln('  • ${intent.description}');
    }
    return (out
          ..writeln()
          ..write(report.human(from: repo.root.path)))
        .toString();
  }

  void _reportRollback(List<String> errors) {
    for (final e in errors) {
      console.err.writeln('  ! $e');
    }
  }
}

/// The intent that stopped the batch, and what it said.
class _Failure {
  _Failure(this.intent, this.code, String captured)
    : reason = _lastLine(captured);

  final Intent intent;
  final int code;

  /// What the intent said before it gave up — the last line of its stderr,
  /// which is where every command's refusal lands.
  final String reason;

  static String _lastLine(String captured) {
    final lines = const LineSplitter()
        .convert(captured)
        .where((l) => l.trim().isNotEmpty);
    return lines.isEmpty ? 'no reason given' : lines.last.trim();
  }
}
