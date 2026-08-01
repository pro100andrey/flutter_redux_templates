/// A command that writes files — as a module, not as a convention seventeen
/// commands follow from memory.
///
/// Counted across `lib/src/commands/` before this existed: `--root` declared by
/// hand eighteen times, `--format` nine times with four different help strings,
/// the name-parsing guard thirteen times, and twenty places writing to stderr
/// and returning the failure code by hand rather than through the handler that
/// exists to do exactly that.
///
/// The cross-command invariants were held by a test that walks the registry —
/// `test/frx_command_test.dart` asserts that a command taking `--json` also
/// takes `--root`. That test exists because there was nowhere to put the
/// invariant. Here there is: a command that extends this cannot forget a flag it
/// never declared.
///
/// Every command that writes is built on it — those whose whole output is new
/// files, those that also wire what they wrote into existing source, and
/// `remove`, which takes both away — with one exception: `rename`, which does
/// not use the AST tier either, and whose seam is a question of its own.
library;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../engine/write_path.dart';
import '../workspace/frx_workspace.dart';
import 'frx_command.dart';
import 'options.dart';

/// Which of the optional writing flags a command takes.
///
/// `--format`, `--json` and `--root` are not here: every writing command takes
/// all three, and making them optional is how `list-substates` ended up with its
/// own drifted help text for `--root`.
class WriteFlags {
  const WriteFlags({
    this.dryRun = true,
    this.force = true,
    this.diff = false,
    this.buildRunner = false,
  });

  /// Print the plan and write nothing.
  ///
  /// Off for the destructive commands, which preview by *default* and write on
  /// `--apply` — the inverse, and a difference in stance rather than in
  /// spelling.
  final bool dryRun;

  /// Overwrite files that already exist.
  final bool force;

  /// Print a unified diff of the change. Only for commands that edit an
  /// existing file: a diff of a file that did not exist is its whole content.
  final bool diff;

  /// Run `build_runner` in the artifact's package afterwards.
  final bool buildRunner;
}

/// What a command intends to do, handed back rather than performed.
///
/// A command builds one and stops; the base applies it. That is what makes the
/// interesting half — which files, which edits, what to say about them —
/// reachable in a test without a process, a workspace teardown, or a captured
/// stdout.
class WritePlan {
  const WritePlan({
    required this.changes,
    required this.header,
    this.narrate,
    this.build,
    this.closing,
    this.relativeTo,
    this.previewOnly,
    this.previewNotice = 'Dry run — nothing written.',
  });

  /// The whole change, applied together or not at all.
  final Changeset changes;

  /// The line above the plan — `Substate "LogIn"`.
  final String header;

  /// What this command has to say that the file list does not: which facade it
  /// edited, or that it was already wired and skipped.
  final void Function()? narrate;

  /// The codegen step, derived from what was actually written.
  ///
  /// Null takes the default for a command that declares
  /// [WriteFlags.buildRunner]: generate in the package the first written file
  /// belongs to. Only a command that needs something else says so — `remove`
  /// wants a clean before the build, and the wiring commands know their package
  /// without reading it off a path.
  final DeferredBuild? build;

  /// Replaces the written count when the command has something better to say —
  /// `add-nav` names the callback the developer still has to hook up.
  final String? closing;

  /// Root to print paths relative to.
  final String? relativeTo;

  /// Forces preview mode regardless of `--dry-run`, for the destructive
  /// commands that write only on `--apply`.
  final bool? previewOnly;

  /// What a preview says when there is no machine report to print instead.
  final String previewNotice;
}

/// The base every file-writing command is built on.
abstract class WritingCommand extends Command<int> with NameArg {
  WritingCommand() {
    // In the order the since-deleted flag helper used. Declaring them in the
    // base's own reading order instead moved every migrated command's `--help`,
    // which is how this was noticed — `--diff` is the one addition, and no
    // command the helper served takes it.
    //
    // A command's own options come after, which is where all but `add-widget`
    // already put them; that one's help really did change.
    if (flags.dryRun) {
      argParser.addFlag(
        'dry-run',
        negatable: false,
        // "planned files" is what the seven scaffolders said, and it is false
        // for the three that only edit: `add-field` writes no file at all
        // unless you ask for the setter. One text for thirteen commands has to
        // be true of all thirteen.
        help: 'Show the planned changes without writing.',
      );
    }
    if (flags.force) {
      argParser.addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Overwrite existing files.',
      );
    }
    if (flags.diff) {
      argParser.addFlag(
        'diff',
        negatable: false,
        help: 'Print a unified diff of the change.',
      );
    }
    argParser
      ..addFlag(
        'format',
        defaultsTo: true,
        help: 'Run `dart format` on the changed files.',
      )
      ..addFlag('json', negatable: false, help: kMachineHelp)
      ..addOption('root', help: kRootHelp);
    if (flags.buildRunner) {
      argParser.addFlag(
        'build-runner',
        abbr: 'b',
        negatable: false,
        help: "Run build_runner in the artifact's package after writing.",
      );
    }
    describeArgs(argParser);
  }

  /// Which optional flags this command takes. Override to opt in or out.
  WriteFlags get flags => const WriteFlags();

  /// Adds the command's own options.
  ///
  /// Redeclaring one the base owns throws, which is the invariant made
  /// structural: `args` refuses a duplicate name whichever declaration comes
  /// second. Called last only so the shared flags read first in `--help`.
  void describeArgs(ArgParser parser) {}

  /// What this command would do to [repo].
  ///
  /// Throw [refuse] for anything the user has to fix first. Return the plan for
  /// everything else; applying it is not this method's business.
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results);

  /// Codegen in whichever package the first written file belongs to.
  ///
  /// What every command that only writes new files wants, and what three of
  /// them had each spelled out below a [WriteFlags.buildRunner] that already
  /// said it — one fact declared twice per command.
  static BuildStep _generateWhatWasWritten(List<String> written) =>
      BuildStep.build(
        FrxWorkspace.packageRootOf(written.first),
        nextHint: 'generate code',
      );

  /// Refuses the command, naming what the user has to change.
  ///
  /// The one way to say it. `command_runner` renders a [StateError] as
  /// `✗ <message>` and exits 70; twenty sites used to write to stderr and return
  /// 70 themselves, three of them catching this exception purely to reprint it
  /// with a prefix the central handler does not use.
  Never refuse(String message) => throw StateError(message);

  @override
  Future<int> run() async {
    final results = argResults!;
    final repo = FrxWorkspace.locate(startDir: results['root'] as String?);
    final plan = await planFor(repo, results);
    return runChangeset(
      results,
      plan: plan.changes,
      header: plan.header,
      narrate: plan.narrate,
      // Always, when the command has a workspace in hand: it is a no-op unless
      // the repo opted into the docs export, and leaving each command to judge
      // whether its edit *could* have moved a route is what let `remove`
      // refresh the docs while `add-substate` did not.
      repoRoot: repo.root,
      build: plan.build ?? (flags.buildRunner ? _generateWhatWasWritten : null),
      // Passed through, never defaulted. Paths in the human plan are resolved
      // by the editor against the directory it was invoked in
      // (`queries.ts` → `path.resolve(targetDir, …)`), so a plan printed
      // relative to the repo root instead of the cwd stops opening the file it
      // names — silently, because the string still looks like a path.
      relativeTo: plan.relativeTo,
      closing: plan.closing,
      previewOnly: plan.previewOnly,
      previewNotice: plan.previewNotice,
    );
  }
}
