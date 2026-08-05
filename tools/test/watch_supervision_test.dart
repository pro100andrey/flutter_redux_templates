import 'package:test/test.dart';
import 'package:tools/src/engine/watch_supervision.dart';

/// Where a signal aimed at `build_runner watch` has to land.
///
/// The whole of this was measured, not reasoned: `dart run build_runner watch`
/// is a *launcher* that compiles the build script and runs it as a child
/// (`dartaotruntime`), and only that child installs build_runner's `SIGINT`
/// handler. Two `SIGINT`s sent to the launcher's pid left both processes
/// running; one sent to the process group ended both. Anything here that aims at
/// the launcher alone is a guard that reports success and does nothing — the
/// failure this module exists to prevent.
void main() {
  group('when we lead the child’s process group', () {
    // An interactive shell puts `frx watch` in its own group, so the group is
    // exactly the launcher and the build script. Signalling it is precise.
    List<List<String>> plan(String signal) => WatchSupervision.signalPlan(
      selfPid: 100,
      childPid: 101,
      childGroup: 100,
      signal: signal,
    );

    test('the group is signalled, negated the way kill(2) wants it', () {
      expect(plan('INT'), [
        ['kill', '-INT', '-100'],
      ]);
    });

    test('the escalation never uses the group — we are in it', () {
      // `kill -KILL -<us>` takes frx down with the watch: `run()`'s `finally`
      // never cancels the handlers or stops the reaper, the child's exit code is
      // never returned, and the shell reports `Killed: 9` for what the user
      // asked to be a clean stop. `INT` is safe there only because we hold a
      // handler for it.
      expect(plan('KILL'), [
        ['pkill', '-KILL', '-P', '101'],
        ['kill', '-KILL', '101'],
      ]);
    });

    test('the launcher is never signalled on its own', () {
      // The bug this pins: `kill -INT <launcher>` is silently ignored.
      expect(
        plan('INT').expand((c) => c),
        isNot(contains('101')),
        reason: 'signalling the launcher by pid does nothing',
      );
    });
  });

  group('when the group is somebody else’s', () {
    // `nohup`, CI, or a spawn from an editor: no job control, so `frx` inherits
    // the caller's group. Signalling that would reach the caller's other jobs.
    List<List<String>> plan(String signal) => WatchSupervision.signalPlan(
      selfPid: 100,
      childPid: 101,
      childGroup: 55,
      signal: signal,
    );

    test('the child and its children are named, not the group', () {
      expect(plan('INT'), [
        ['pkill', '-INT', '-P', '101'],
        ['kill', '-INT', '101'],
      ]);
    });

    test('children are signalled before the launcher', () {
      // `pkill -P` finds children of a *living* process. Kill the launcher first
      // and the build script is already reparented to init, so the second
      // command matches nothing — the escalation manufactures the very orphan
      // this module exists to prevent.
      final commands = plan('KILL').map((c) => c.first).toList();
      expect(commands.indexOf('pkill'), lessThan(commands.indexOf('kill')));
    });

    test('no negative pid is used, so no stranger is signalled', () {
      for (final command in plan('INT')) {
        for (final arg in command) {
          expect(
            arg,
            isNot(matches(r'^-\d+$')),
            reason: 'a negative pid here would signal the caller’s other jobs',
          );
        }
      }
    });

    test('the build script is reached through pkill -P', () {
      // Without this the launcher dies and the script it started is orphaned —
      // trading one orphan for another.
      expect(plan('INT').first, containsAllInOrder(['pkill', '-P', '101']));
    });
  });

  test('an unreadable group is treated as somebody else’s', () {
    // `ps` failing must not be read as "we lead it": that would send a signal to
    // a negative pid chosen from nothing.
    expect(
      WatchSupervision.signalPlan(
        selfPid: 100,
        childPid: 101,
        childGroup: null,
        signal: 'INT',
      ).last,
      ['kill', '-INT', '101'],
    );
  });

  group('the reaper line', () {
    test('carries the same aim, as shell', () {
      expect(
        WatchSupervision.reaperAim(
          selfPid: 100,
          childPid: 101,
          childGroup: 100,
        ),
        'kill -INT -100 2>/dev/null',
      );
    });

    test('chains both commands when the group is not ours', () {
      expect(
        WatchSupervision.reaperAim(selfPid: 100, childPid: 101, childGroup: 55),
        'pkill -INT -P 101 2>/dev/null; kill -INT 101 2>/dev/null',
      );
    });

    test('never escalates to KILL', () {
      // The reaper runs unattended, after we are gone. A watch has a lock to
      // release; build_runner uses `-9` in its own reaper because it is killing
      // a build script, which is a different thing.
      for (final group in [100, 55]) {
        expect(
          WatchSupervision.reaperAim(
            selfPid: 100,
            childPid: 101,
            childGroup: group,
          ),
          isNot(contains('KILL')),
        );
      }
    });

    test('silences its own errors', () {
      // By the time it fires the watch may already be gone, and it has no
      // terminal left to complain into.
      expect(
        WatchSupervision.reaperAim(selfPid: 1, childPid: 2, childGroup: null),
        allOf(contains('2>/dev/null'), isNot(contains('echo'))),
      );
    });
  });
}
