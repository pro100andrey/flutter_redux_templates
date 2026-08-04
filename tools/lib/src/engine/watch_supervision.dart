import 'dart:async';
import 'dart:io';

import '../util/console.dart';

/// Keeping a `build_runner watch` from outliving the process that started it.
///
/// The problem, measured rather than assumed: `frx watch` is the parent of
/// `dart run build_runner watch`, and killing `frx` leaves the child running. It
/// reparents to pid 1 and keeps going for hours regenerating nothing, which
/// looks exactly like a working setup until a generated file turns out to be
/// stale. `frx doctor` reports those, but reporting is the cure for a wound
/// already taken.
///
/// **Why the child cannot be asked to do this.** Every mechanism that makes a
/// process die with its parent needs that process's cooperation: Linux's
/// `prctl(PR_SET_PDEATHSIG)` is set by the child on itself, the portable
/// pipe/EOF idiom needs the child to read the pipe, and macOS has no
/// `PDEATHSIG` at all. We do not own build_runner's source, so none of them
/// apply — which leaves a third process watching the link from outside.
///
/// See `tools/docs/research/orphaned-child-processes.md` for the survey this is
/// built from, including the platforms and the mechanisms that were rejected.
abstract final class WatchSupervision {
  const WatchSupervision._();

  /// How long a signalled watch is given to drain before it is killed outright.
  ///
  /// It has a lock to release and a build to finish; hurrying it is how a
  /// half-written generated file happens.
  static const drainTimeout = Duration(seconds: 10);

  /// Runs `dart <args>` in [cwd] as a supervised watch, returning its exit code.
  ///
  /// Three things happen that a bare [Process.start] does not do:
  ///
  ///  * `SIGTERM` and `SIGHUP` bring the child down instead of orphaning it;
  ///  * a reaper covers the case no in-process handler can — this process being
  ///    `SIGKILL`ed, where nothing of ours runs at all;
  ///  * `SIGINT` is deliberately *not* forwarded, for the reason on
  ///    [_watchSignals].
  static Future<int> run(List<String> args, String cwd) async {
    final proc = await Process.start(
      'dart',
      args,
      workingDirectory: cwd,
      // Not `detached`: that calls `setsid()`, which takes the child out of the
      // terminal's foreground process group — Ctrl-C would stop reaching it —
      // and puts it in its own session, which is exactly the shape frx's own
      // orphan detector reads as dead.
      mode: ProcessStartMode.inheritStdio,
    );

    final reaper = await _startReaper(childPid: proc.pid);
    final signals = _watchSignals(proc);

    try {
      return await proc.exitCode;
    } finally {
      for (final sub in signals) {
        unawaited(sub.cancel());
      }
      // The watch ended on its own terms; the reaper has nothing left to guard
      // and would otherwise poll until this process exits.
      reaper?.kill();
    }
  }

  /// Subscriptions that bring [proc] down when this process is asked to stop.
  ///
  /// **`SIGINT` is watched but not forwarded.** In a terminal the tty delivers
  /// Ctrl-C to the whole foreground process group, so the child already got it
  /// and is draining; build_runner treats a *second* `SIGINT` as a hard
  /// `exit(2)`, so forwarding would convert today's graceful Ctrl-C into an
  /// abrupt one. The handler exists only to keep this process alive long enough
  /// to await the child's exit instead of dying first and orphaning it.
  ///
  /// `SIGTERM` and `SIGHUP` are the opposite case: the child hears neither
  /// (build_runner installs a handler for `SIGINT` alone), so they are
  /// translated into the one signal it does handle.
  ///
  /// **The second Ctrl-C is an escape hatch, not a courtesy.** Swallowing
  /// `SIGINT` for the whole life of the run replaces the default disposition, so
  /// a watch that wedges — lock contention, a builder that never returns — makes
  /// `frx` unkillable from the keyboard: the child never exits, `await
  /// proc.exitCode` never completes, and every Ctrl-C is absorbed. The old
  /// unsupervised path at least let the first one through. Counting them keeps
  /// the graceful first press and restores the way out.
  static List<StreamSubscription<ProcessSignal>> _watchSignals(Process proc) {
    final subs = <StreamSubscription<ProcessSignal>>[];

    void translate(ProcessSignal signal) {
      // `sigterm` cannot be watched on Windows; asking would throw.
      if (Platform.isWindows && signal != ProcessSignal.sigint) return;
      subs.add(signal.watch().listen((_) => unawaited(_stop(proc))));
    }

    var interrupts = 0;
    subs.add(
      ProcessSignal.sigint.watch().listen((_) {
        if (++interrupts < 2) return;
        console.err.writeln(
          '\n⚠ build_runner is not stopping — leaving it to the reaper.',
        );
        exit(130); // 128 + SIGINT, what a shell reports for an interrupted job
      }),
    );
    translate(ProcessSignal.sigterm);
    translate(ProcessSignal.sighup);
    return subs;
  }

  /// Asks [proc] to drain, then insists.
  ///
  /// **Never to [Process.pid] alone.** `dart run` is a launcher: it compiles the
  /// build script and runs it as a *child* (`dartaotruntime`), and that child is
  /// what installs build_runner's `SIGINT` handler. Measured: two `SIGINT`s to
  /// the launcher left both processes running, and one to the group ended both.
  /// It is also why Ctrl-C works today, since a tty signals the whole foreground
  /// group rather than one pid. [signalPlan] decides which of the two shapes
  /// reaches the pair safely.
  static Future<void> _stop(Process proc) async {
    _signalTree(proc.pid, ProcessSignal.sigint);
    try {
      await proc.exitCode.timeout(drainTimeout);
    } on TimeoutException {
      _signalTree(proc.pid, ProcessSignal.sigkill);
    }
  }

  /// How to reach the whole watch — the launcher *and* the build script under
  /// it — given who leads the child's process group.
  ///
  /// Prefers the group, which is the watch and nothing else *when we lead it*.
  /// Started from an interactive shell, job control makes `frx` a group leader,
  /// so its group holds exactly the launcher and the script. Started without job
  /// control (`nohup`, CI, a spawn from an editor), `frx` inherits the caller's
  /// group, and signalling that would reach the caller's other jobs — so there
  /// the child and its direct children are named by pid instead.
  ///
  /// Pure, and separated for that reason: which of the two it picks is the whole
  /// correctness question, and it is not observable from the outside of a
  /// process that has already exited.
  ///
  /// **The group form is only ever used for `INT`.** We are a member of that
  /// group, and `kill -KILL -<us>` would take us down with the watch: `run()`'s
  /// `finally` would never cancel the handlers or stop the reaper, the child's
  /// exit code would never be returned, and the shell would report `Killed: 9`
  /// for what the user asked to be a clean stop. `INT` is safe there because we
  /// hold a handler for it; `KILL` cannot be handled by anyone.
  ///
  /// **Children are signalled before the launcher.** `pkill -P <launcher>` finds
  /// children *of a living process* — kill the launcher first and the build
  /// script is already reparented to init, so the second command matches
  /// nothing and the escalation leaves behind exactly the orphan this module
  /// exists to prevent.
  static List<List<String>> signalPlan({
    required int selfPid,
    required int childPid,
    required int? childGroup,
    required String signal,
  }) {
    if (signal != 'KILL' && childGroup == selfPid) {
      return [
        ['kill', '-$signal', '-$selfPid'],
      ];
    }
    return [
      ['pkill', '-$signal', '-P', '$childPid'],
      ['kill', '-$signal', '$childPid'],
    ];
  }

  /// [signalPlan] as one shell line, for the reaper — which is a `bash -c` and
  /// cannot call back into Dart. Errors are swallowed because by the time it
  /// runs the watch may already be gone, and a reaper that prints to a terminal
  /// nobody owns any more is noise.
  static String reaperAim({
    required int selfPid,
    required int childPid,
    required int? childGroup,
  }) => signalPlan(
    selfPid: selfPid,
    childPid: childPid,
    childGroup: childGroup,
    signal: 'INT',
  ).map((c) => '${c.join(' ')} 2>/dev/null').join('; ');

  static void _signalTree(int childPid, ProcessSignal signal) {
    final plan = signalPlan(
      selfPid: pid,
      childPid: childPid,
      childGroup: _processGroupOf(childPid),
      signal: signal == ProcessSignal.sigkill ? 'KILL' : 'INT',
    );
    for (final command in plan) {
      try {
        Process.runSync(command.first, command.sublist(1));
      } on ProcessException {
        // `pkill` is absent from a minimal image, and `kill` can be a shell
        // builtin only. Reached from a signal listener through `unawaited`, so
        // an escape here is an unhandled async error rather than a message.
      }
    }
  }

  /// The process group [target] belongs to, or null when `ps` cannot say.
  static int? _processGroupOf(int target) {
    try {
      final res = Process.runSync('ps', ['-o', 'pgid=', '-p', '$target']);
      return int.tryParse((res.stdout as String).trim());
    } on ProcessException {
      return null;
    }
  }

  /// A detached process that outlives us and stops [childPid] once we are gone.
  ///
  /// The shape is build_runner's own — it starts exactly this one-liner for
  /// every child it spawns (`build_runner/lib/src/bootstrap/processes.dart`) —
  /// so it is a pattern already proven inside this dependency tree rather than
  /// an invention. Two deliberate differences: it watches *our* pid, where
  /// build_runner watches its own (which is why build_runner's reaper does
  /// nothing about this problem); and it sends `SIGINT` where build_runner sends
  /// `-9`, because the thing being stopped here is a watch with a lock to
  /// release, not a build script.
  ///
  /// Known limits, none of them repairable at this layer: the poll is
  /// second-granular; a recycled pid would make the reaper either never fire or
  /// fire at a stranger; and `kill -0` reports failure on `EPERM` as well as on
  /// "no such process", so a hostile-enough environment could make it act while
  /// we are alive. That last one bit VS Code in the field; here the parent is
  /// this process and the same user, so it is close to unreachable.
  static Future<Process?> _startReaper({required int childPid}) async {
    try {
      if (Platform.isWindows) {
        return await Process.start('powershell', [
          '-NoProfile',
          '-Command',
          'Wait-Process -Id $pid; Stop-Process -Id $childPid -Force',
        ], mode: ProcessStartMode.detached);
      }
      return await Process.start('bash', [
        '-c',
        'while kill -0 $pid 2>/dev/null; do sleep 1; done; ${reaperAim(selfPid: pid, childPid: childPid, childGroup: _processGroupOf(childPid))}',
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      // No `bash` or no `powershell` on PATH. The watch still runs; it just
      // loses the one guard that covers a hard kill of this process.
      return null;
    }
  }
}
