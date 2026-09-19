import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../flow/flow_docs.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'watch_processes.dart';

export 'watch_processes.dart'
    show buildRunnerWatchPid, orphanedBuildRunnerWatchPids;

/// The post-write execution stage shared by every mutating command: format the
/// files that were written, then either run build_runner or print the command
/// the developer can run by hand. Centralizing it means the "which package,
/// which build_runner flags, run-or-hint" decision — and the `.dart`-only
/// format filter — live in one place instead of being copied per command.

/// Runs `dart format` on the `.dart` files among [written] (when [enabled]).
///
/// Non-`.dart` paths are skipped: a moved asset (`notes.txt`, …) in the set
/// would otherwise fail the whole batch. A format failure is a warning, not a
/// hard error — the files are already written correctly, just not tidied.
Future<void> formatFiles(
  Iterable<String> written, {
  required bool enabled,
}) async {
  if (!enabled) {
    return;
  }

  final dart = written.where((f) => f.endsWith('.dart')).toList();
  if (dart.isEmpty) {
    return;
  }

  final res = await Process.run('dart', ['format', ...dart]);
  if (res.exitCode != 0) {
    console.err.writeln('⚠ dart format failed:\n${res.stderr}');
  }
}

/// Regenerates `docs/flows/` after a command changed what it describes.
///
/// The export is a pure function of the sources the command just edited, so
/// leaving it stale would make `frx doctor` report drift that frx itself caused
/// — and make you run a second command to undo it. Same category as
/// `dart format`: normalize the derived artifact where it was derived.
/// `frx doctor` stays the safety net for the drift frx cannot observe: a
/// connector edited by hand.
///
/// Silent no-op when the repo has not opted in (no `docs/flows/` directory) or
/// when nothing changed. A failure here is a warning, not an error: the command
/// itself already succeeded, and doctor will report the stale docs.
///
/// [report] off — a `--json` run — moves the ✓ line to stderr: stdout is the
/// changeset a consumer parses, and this line printed ahead of it made every
/// apply in a repo with `docs/flows/` unparseable. Stderr, not silence: the
/// line is true, and the editor shows stderr whatever it does with stdout.
Future<void> refreshFlowDocs(Directory repoRoot, {bool report = true}) async {
  final docs = FlowDocs(FrxWorkspace(repoRoot));
  if (!docs.enabled) {
    return;
  }

  try {
    final changed = docs.write();
    if (changed.isEmpty) {
      return;
    }

    (report ? console.out : console.err).writeln(
      '  ✓ docs/flows refreshed (${changed.length} file(s))',
    );
  } on Object catch (e) {
    // e.g. no AppRouter to read — doctor reports that on its own.
    console.err.writeln('⚠ could not refresh docs/flows: $e');
  }
}

/// A build_runner plan: the [packageRoot] to run in, the [commands] to run in
/// sequence (e.g. a lone `build`, or `clean` then `build`), and the [nextHint]
/// describing what they regenerate — printed when the developer opts out.
class BuildStep {
  const BuildStep({
    required this.packageRoot,
    required this.commands,
    required this.nextHint,
  });

  /// A single `build_runner build` (optionally with extra [args]) — the common
  /// case.
  BuildStep.build(
    this.packageRoot, {
    required this.nextHint,
    List<String> args = const [],
  }) : commands = [
         ['run', 'build_runner', 'build', ...args],
       ];

  /// `build_runner clean` and then `build` — what a package needs after an
  /// input in *another* package was deleted.
  ///
  /// An incremental build cannot drop a removed input it does not own: `app`'s
  /// build would try to delete the now-missing `ui` page from an asset graph it
  /// cannot write to, and crash. The `clean` first drops the stale graph so the
  /// rebuild never references it.
  const BuildStep.cleanBuild(this.packageRoot, {required this.nextHint})
    : commands = const [
        ['run', 'build_runner', 'clean'],
        ['run', 'build_runner', 'build'],
      ];

  final String packageRoot;
  final List<List<String>> commands;
  final String nextHint;
}

/// The repository [step] belongs to, or null when it cannot be found.
///
/// The workspace and not the package: a watch started in `business/` is this
/// repo's build even when the step is about `app/`.
///
/// Found by walking up for the marker rather than by taking the package's
/// parent. `packageRootOf` falls back to a file's own directory when it finds
/// no pubspec, and one level up from *that* is a directory somewhere inside
/// `lib/` — against which a watch running at the repo root reads as another
/// repository's, and frx builds over a live watch instead of standing down.
/// Null when the walk fails, which [buildRunnerWatchPid] reads as "stand down
/// for anything", the safe direction.
String? _workspaceOf(BuildStep step) {
  try {
    return FrxWorkspace.locate(startDir: step.packageRoot).root.path;
  } on Object {
    return null;
  }
}

/// What [runBuild] did: the exit code plus the facts a machine consumer needs.
///
/// A record rather than the bare exit code it used to return, because the
/// hand-off to a live watch is reported in the result of the command that
/// triggered it — and only [runBuild] knows whether it happened.
typedef Built = ({int code, bool ran, bool handedToWatch, int? watchPid});

/// Runs [step] when [enabled] (`--build-runner`), streaming each command's
/// output and stopping at the first non-zero exit; otherwise prints the
/// copy-paste hint.
///
/// Both paths stand down when a watch is running: a second build_runner asks
/// the incumbent to exit ("Exiting as requested by another build_runner
/// process"), so building here would kill the developer's watch — and printing
/// the bare hint would talk them into killing it by hand.
///
/// The command is still printed, as a fallback rather than an instruction: a
/// watch can be wedged, and frx cannot tell a working one from a stuck one.
/// [watching] overrides the detection for tests.
///
/// [report] off suppresses every line of frx's own — `--json` consumers parse
/// stdout, and the same facts are in the result they get instead — and sends
/// build_runner's output to stderr, where it stays readable without landing in
/// the parse.
Future<Built> runBuild(
  BuildStep step, {
  required bool enabled,
  bool? watching,
  bool report = true,
}) async {
  final rel = p.relative(step.packageRoot);
  final byHand = buildCommandLine(step);
  final watchPid = watching == null
      ? buildRunnerWatchPid(within: _workspaceOf(step))
      : null;

  if (watching ?? (watchPid != null)) {
    final who = watchPid == null ? '' : ' (pid $watchPid)';
    if (report) {
      console.out
        ..writeln()
        ..writeln(
          enabled
              // --build-runner was an explicit ask, so say plainly that the ask
              // was handed off rather than carried out here.
              ? '⚠ build_runner watch is running$who — handing the build to it '
                    'rather than stopping it.'
              : '⚠ build_runner watch is running$who — not building, that '
                    'would stop it.',
        )
        ..writeln('  If it does not ${step.nextHint}, run:')
        ..writeln('    $byHand');
    }
    return (code: 0, ran: false, handedToWatch: true, watchPid: watchPid);
  }
  if (enabled) {
    if (report) {
      console.out
        ..writeln()
        ..writeln('Running build_runner in $rel …');
    }

    for (final args in step.commands) {
      final code = await streamProcess(
        'dart',
        args,
        step.packageRoot,
        toStderr: !report,
      );
      if (code != 0) {
        return (code: code, ran: true, handedToWatch: false, watchPid: null);
      }
    }
    return (code: 0, ran: true, handedToWatch: false, watchPid: null);
  }

  if (report) {
    console.out
      ..writeln()
      ..writeln('Next: ${step.nextHint}:')
      ..writeln('  $byHand');
  }

  return (code: 0, ran: false, handedToWatch: false, watchPid: null);
}

/// The shell command [step] amounts to, as a consumer would have to type it.
String buildCommandLine(BuildStep step) =>
    'cd ${p.relative(step.packageRoot)} && '
    '${step.commands.map((c) => 'dart ${c.join(' ')}').join(' && ')}';

/// Runs a process inheriting stdio; returns its exit code.
///
/// [toStderr] pipes both of the child's streams to this process's stderr —
/// for a `--json` run, whose stdout is the one object a consumer parses. The
/// child gets no stdin then; a build asked for by a machine has nobody to
/// answer a prompt.
Future<int> streamProcess(
  String exe,
  List<String> args,
  String cwd, {
  bool toStderr = false,
}) async {
  if (!toStderr) {
    final proc = await Process.start(
      exe,
      args,
      workingDirectory: cwd,
      mode: .inheritStdio,
    );
    return proc.exitCode;
  }
  final proc = await Process.start(exe, args, workingDirectory: cwd);
  final forwarded = Future.wait([
    proc.stdout.transform(utf8.decoder).forEach(console.err.write),
    proc.stderr.transform(utf8.decoder).forEach(console.err.write),
  ]);
  final code = await proc.exitCode;
  await forwarded;
  return code;
}
