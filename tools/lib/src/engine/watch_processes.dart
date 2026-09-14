/// Which `build_runner watch` processes are running, and whose they are.
///
/// Read off the process table rather than the lock in `.dart_tool/build/lock/`:
/// an idle watch releases that lock between cycles, so it reads as free most
/// of the time. Two callers ask two questions of the same scan — `runBuild`
/// wants the live watch it must stand down for, `frx doctor` wants the
/// orphaned ones it must report — and the scan answers both from one `pgrep`
/// and at most two `ps` calls.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    if (watch.orphaned) {
      continue;
    }
    if (!_watches(watch, within)) {
      continue;
    }
    return watch.pid;
  }
  return null;
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
  if (within == null) {
    return true;
  }
  final cwd = watch.cwd;
  // A watch whose directory cannot be read is treated as this repo's, which is
  // the safe direction: standing down needlessly costs a rebuild the developer
  // can ask for, and building into a live watch's output is what corrupts it.
  if (cwd == null) {
    return true;
  }
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
/// every temp directory disagree with itself — `/var/…` against
/// `/private/var/…`.
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
/// command line that merely contains both words —
/// `tail -f build_runner-watch.log` — is not mistaken for a watch.
///
/// Scanned on every call rather than memoized: `doctor --fix` runs build_runner
/// between its two audits, which asks any running watch to exit, so a cached
/// answer would name a process that the fix itself had just stopped.
///
/// Windows has no `pgrep`; there this is empty and both callers behave as if
/// no watch were running.
List<_Watch> _watchProcesses({bool needCwd = false}) {
  if (Platform.isWindows) {
    return const [];
  }
  try {
    final found = Process.runSync('pgrep', ['-f', 'build_runner[^ ]* watch']);
    if (found.exitCode != 0) {
      return const [];
    }
    final pids = [
      for (final line in const LineSplitter().convert(found.stdout as String))
        ?int.tryParse(line.trim()),
    ];
    if (pids.isEmpty) {
      return const [];
    }

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
  if (!Platform.isMacOS) {
    return out;
  }
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
      if (line.startsWith('p')) {
        current = int.tryParse(line.substring(1));
      }
      if (line.startsWith('n') && current != null) {
        out[current] = line.substring(1);
      }
    }
  } on ProcessException {
    return out;
  }
  return out;
}

/// A process's parent and session, keyed by pid. Absent when `ps` did not see
/// it.
typedef _Proc = ({int ppid, String session});

/// What separates the columns `ps` prints.
final _columns = RegExp(r'\s+');

Map<int, _Proc> _describe(Iterable<int> pids) {
  if (pids.isEmpty) {
    return const {};
  }
  final res = Process.runSync('ps', [
    '-o',
    'pid=,ppid=,sess=',
    '-p',
    pids.join(','),
  ]);
  final out = <int, _Proc>{};
  for (final line in const LineSplitter().convert(res.stdout as String)) {
    final parts = line.trim().split(_columns);
    if (parts.length < 3) {
      continue;
    }
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid == null || ppid == null) {
      continue;
    }
    out[pid] = (ppid: ppid, session: parts[2]);
  }
  return out;
}

/// Whether a watch has outlived the process that launched it.
///
/// **Not `ppid <= 1`.** That assumed an orphan is reparented to init, which is
/// false wherever a **subreaper** sits between the process and init — the
/// normal arrangement under `systemd --user`, where an orphan is reparented to
/// the user manager, whose pid is not 1. There the old check swapped both
/// answers: a dead watch read as live, so frx skipped a build nobody was going
/// to run and left stale generated code behind a message saying the build was
/// handled, and `doctor` stopped reporting the orphan it exists to surface.
///
/// The question that survives a subreaper is **whether the parent is still in
/// the watch's session**. A shell (or an IDE's spawned process) and everything
/// it starts share a session, so a live watch's parent is in the watch's
/// session by construction; a reaper — init, `systemd --user`, `tini` — is its
/// own session leader, so a reparented orphan's parent is not. What it was
/// reparented *to* is an implementation detail of the init system, and this
/// asks nothing about it.
///
/// Two fallbacks, both toward "live": a parent of pid 1 or less is an orphan
/// outright, and a session `ps` would not report leaves the watch counted as
/// live — standing down for a watch that turns out to be dead costs a stale
/// generated file, while building over a live one kills the developer's watch.
///
/// **On macOS the session comparison never fires, and the `ppid` fallback is
/// what answers.** Apple's `ps` declares `sess` as a kernel pointer
/// (`KPTR`/`%lx` in `adv_cmds/ps/keyword.c`), which an unprivileged process is
/// shown as `0` — so every process reads the same value and the comparison is
/// always false. That is not a bug here: macOS has no subreapers, so a real
/// orphan is reparented to `launchd` at pid 1 and the fallback catches it. It
/// is recorded because the paragraph above describes Linux, and a reader would
/// otherwise believe the session test is doing the work everywhere.
///
/// The known way to be wrong is a watch deliberately put in its own session
/// (`setsid`, or a spawn with `ProcessStartMode.detached`): its parent is in a
/// different session, so a *live* watch reads as an orphan — and frx would then
/// build over it and kill it. Nothing in this repo starts a watch that way, and
/// nothing should.
bool _isOrphan(_Proc watch, _Proc? parent) {
  if (watch.ppid <= 1) {
    return true;
  }
  if (parent == null) {
    return true; // the parent is gone from the table entirely
  }
  if (watch.session.isEmpty || parent.session.isEmpty) {
    return false;
  }
  if (watch.session == '-' || parent.session == '-') {
    return false;
  }
  return watch.session != parent.session;
}
