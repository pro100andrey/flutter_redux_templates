import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../flow/flow_docs.dart';
import '../workspace/frx_workspace.dart';
import '../util/console.dart';

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
  if (!enabled) return;
  final dart = written.where((f) => f.endsWith('.dart')).toList();
  if (dart.isEmpty) return;
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
Future<void> refreshFlowDocs(Directory repoRoot) async {
  final docs = FlowDocs(FrxWorkspace(repoRoot));
  if (!docs.enabled) return;
  try {
    final changed = docs.write();
    if (changed.isEmpty) return;
    console.out.writeln('  ✓ docs/flows refreshed (${changed.length} file(s))');
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

  final String packageRoot;
  final List<List<String>> commands;
  final String nextHint;
}

/// PID of a `build_runner watch` worth standing down for, or null.
///
/// Found by process scan, not by the lock in `.dart_tool/build/lock/`: an idle
/// watch releases that lock between cycles, so it reads as free most of the
/// time.
///
/// Orphans are skipped. A watch whose terminal or IDE died lingers for hours,
/// regenerating nothing; counting it as live would make frx skip a build that
/// nobody else is going to run — leaving stale generated code behind a message
/// saying it was handled.
///
/// Windows has no `pgrep`; there this reports null and behaviour is unchanged.
int? buildRunnerWatchPid({String? within}) {
  for (final watch in _watchProcesses(needCwd: within != null)) {
    if (watch.orphaned) continue;
    if (!_watches(watch, within)) continue;
    return watch.pid;
  }
  return null;
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
/// Null when the walk fails, which [_watches] reads as "stand down for
/// anything", the safe direction.
String? _workspaceOf(BuildStep step) {
  try {
    return FrxWorkspace.locate(startDir: step.packageRoot).root.path;
  } on Object {
    return null;
  }
}

/// Whether [watch] is watching the tree at [within] — true for every watch when
/// no tree is named.
///
/// **A watch in another repository is not this repository's build.** `pgrep`
/// finds every `build_runner watch` on the machine, and standing down for one
/// meant handing the build to a process that generates nothing here: the run
/// reports "handing the build to it rather than stopping it", exits 0, and the
/// generated files never appear. Measured in a probe project whose build was
/// handed to a watch running in the template repo two directories away.
bool _watches(_Watch watch, String? within) {
  if (within == null) return true;
  final cwd = watch.cwd;
  // A watch whose directory cannot be read is treated as this repo's, which is
  // the safe direction: standing down needlessly costs a rebuild the developer
  // can ask for, and building into a live watch's output is what corrupts it.
  if (cwd == null) return true;
  final root = _realPath(within);
  final at = _realPath(cwd);
  return at == root || p.isWithin(root, at);
}

/// [path] with symlinks resolved, falling back to normalisation.
///
/// `p.canonicalize` normalises and does not follow links, and both sides of
/// this comparison arrive by different routes: a repo the developer reached
/// through a symlink, against a working directory read out of `lsof` or
/// `/proc`, which is always the real one. On macOS that alone is enough to make
/// every temp directory disagree with itself — `/var/…` against `/private/var/…`.
String _realPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.canonicalize(path);
  }
}

/// PIDs of `build_runner watch` processes that have outlived their launcher.
///
/// The counterpart of [buildRunnerWatchPid]: these are the ones it skips. A
/// watch whose terminal or IDE died keeps running and regenerating nothing,
/// which looks exactly like a working setup until you notice the generated
/// file is stale. Reported by `frx doctor` so it can be found before that.
List<int> orphanedBuildRunnerWatchPids({String? within}) => [
  for (final watch in _watchProcesses(needCwd: within != null))
    if (watch.orphaned && _watches(watch, within)) watch.pid,
];

/// One running watch, whether its launcher is gone, and what it is watching.
typedef _Watch = ({int pid, bool orphaned, String? cwd});

/// Every running `build_runner watch`, with the orphan question answered.
///
/// The pattern wants `watch` as the token after the build_runner one, so a
/// command line that merely contains both words — `tail -f build_runner-watch.log`
/// — is not mistaken for a watch.
///
/// Scanned on every call rather than memoized: `doctor --fix` runs build_runner
/// between its two audits, which asks any running watch to exit, so a cached
/// answer would name a process that the fix itself had just stopped.
///
/// Windows has no `pgrep`; there this is empty and both callers behave as if
/// no watch were running.
List<_Watch> _watchProcesses({bool needCwd = false}) {
  if (Platform.isWindows) return const [];
  try {
    final found = Process.runSync('pgrep', ['-f', r'build_runner[^ ]* watch']);
    if (found.exitCode != 0) return const [];
    final pids = [
      for (final line in const LineSplitter().convert(found.stdout as String))
        if (int.tryParse(line.trim()) case final pid?) pid,
    ];
    if (pids.isEmpty) return const [];

    // Two `ps` calls at most, and only when a watch exists: one for the watches
    // and one for whatever their parents turned out to be.
    final watches = _describe(pids);
    final parents = _describe([for (final w in watches.values) w.ppid]);
    // Only when a caller is going to compare it: on macOS this forks `lsof`,
    // which without a network timeout can block on a stale mount — and the
    // orphan check, which runs on every audit, does not scope by tree.
    final cwds = needCwd ? _cwds(pids) : const <int, String>{};
    return [
      for (final pid in pids)
        if (watches[pid] case final self?)
          (
            pid: pid,
            orphaned: _isOrphan(self, parents[self.ppid]),
            cwd: cwds[pid],
          ),
    ];
  } on ProcessException {
    return const [];
  }
}

/// Each process's working directory, keyed by pid — which package a watch is
/// actually watching.
///
/// `ps` does not carry it on either platform, so this is the one fact that
/// needs a per-OS route: `/proc` on Linux, one batched `lsof` on macOS. A pid
/// that answers neither is simply absent, and [_watches] reads that as "cannot
/// tell", not as "not ours".
Map<int, String> _cwds(Iterable<int> pids) {
  final out = <int, String>{};
  if (Platform.isLinux) {
    for (final pid in pids) {
      try {
        out[pid] = Link('/proc/$pid/cwd').targetSync();
      } on FileSystemException {
        continue;
      }
    }
    return out;
  }
  if (!Platform.isMacOS) return out;
  try {
    final res = Process.runSync('lsof', [
      '-a',
      '-d',
      'cwd',
      '-p',
      pids.join(','),
      '-Fn',
    ]);
    int? current;
    for (final line in const LineSplitter().convert(res.stdout as String)) {
      if (line.startsWith('p')) current = int.tryParse(line.substring(1));
      if (line.startsWith('n') && current != null)
        out[current] = line.substring(1);
    }
  } on ProcessException {
    return out;
  }
  return out;
}

/// A process's parent and session, keyed by pid. Absent when `ps` did not see it.
typedef _Proc = ({int ppid, String session});

Map<int, _Proc> _describe(Iterable<int> pids) {
  if (pids.isEmpty) return const {};
  final res = Process.runSync('ps', [
    '-o',
    'pid=,ppid=,sess=',
    '-p',
    pids.join(','),
  ]);
  final out = <int, _Proc>{};
  for (final line in const LineSplitter().convert(res.stdout as String)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid == null || ppid == null) continue;
    out[pid] = (ppid: ppid, session: parts[2]);
  }
  return out;
}

/// Whether a watch has outlived the process that launched it.
///
/// **Not `ppid <= 1`.** That assumed an orphan is reparented to init, which is
/// false wherever a **subreaper** sits between the process and init — the normal
/// arrangement under `systemd --user`, where an orphan is reparented to the user
/// manager, whose pid is not 1. There the old check swapped both answers: a dead
/// watch read as live, so frx skipped a build nobody was going to run and left
/// stale generated code behind a message saying the build was handled, and
/// `doctor` stopped reporting the orphan it exists to surface.
///
/// The question that survives a subreaper is **whether the parent is still in the
/// watch's session**. A shell (or an IDE's spawned process) and everything it
/// starts share a session, so a live watch's parent is in the watch's session by
/// construction; a reaper — init, `systemd --user`, `tini` — is its own session
/// leader, so a reparented orphan's parent is not. What it was reparented *to* is
/// an implementation detail of the init system, and this asks nothing about it.
///
/// Two fallbacks, both toward "live": a parent of pid 1 or less is an orphan
/// outright, and a session `ps` would not report leaves the watch counted as live
/// — standing down for a watch that turns out to be dead costs a stale generated
/// file, while building over a live one kills the developer's watch.
///
/// **On macOS the session comparison never fires, and the `ppid` fallback is
/// what answers.** Apple's `ps` declares `sess` as a kernel pointer
/// (`KPTR`/`%lx` in `adv_cmds/ps/keyword.c`), which an unprivileged process is
/// shown as `0` — so every process reads the same value and the comparison is
/// always false. That is not a bug here: macOS has no subreapers, so a real
/// orphan is reparented to `launchd` at pid 1 and the fallback catches it. It is
/// recorded because the paragraph above describes Linux, and a reader would
/// otherwise believe the session test is doing the work everywhere.
///
/// The known way to be wrong is a watch deliberately put in its own session
/// (`setsid`, or a spawn with `ProcessStartMode.detached`): its parent is in a
/// different session, so a *live* watch reads as an orphan — and frx would then
/// build over it and kill it. Nothing in this repo starts a watch that way, and
/// nothing should.
bool _isOrphan(_Proc watch, _Proc? parent) {
  if (watch.ppid <= 1) return true;
  if (parent == null) return true; // the parent is gone from the table entirely
  if (watch.session.isEmpty || parent.session.isEmpty) return false;
  if (watch.session == '-' || parent.session == '-') return false;
  return watch.session != parent.session;
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
/// [report] off suppresses every line: `--json` consumers parse stdout, and the
/// same facts are in the result they get instead.
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
      final code = await streamProcess('dart', args, step.packageRoot);
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
Future<int> streamProcess(String exe, List<String> args, String cwd) async {
  final proc = await Process.start(
    exe,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  return proc.exitCode;
}
