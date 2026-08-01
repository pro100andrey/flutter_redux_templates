import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/engine/build_step.dart';

/// A second build_runner asks a running one to exit, so every path through
/// [runBuild] has to stand down while a watch is up.
void main() {
  // A root no build could succeed in: if the watch guard fails to short-circuit,
  // the spawned `dart run build_runner build` exits non-zero and the test sees it.
  BuildStep step() =>
      BuildStep.build('/frx-nonexistent', nextHint: 'regenerate the parts');

  test('a running watch short-circuits an explicit --build-runner', () async {
    final built = await runBuild(step(), enabled: true, watching: true);
    expect(built.code, 0, reason: 'the build must be skipped, not attempted');
    expect(built.ran, isFalse);
    // The fact the machine write format reports: an agent needs to know the
    // build was handed over at the moment it acts, not when it audits later.
    expect(built.handedToWatch, isTrue);
  });

  test('a running watch also suppresses the copy-paste hint', () async {
    final built = await runBuild(step(), enabled: false, watching: true);
    expect(built.code, 0);
    expect(built.handedToWatch, isTrue);
  });

  test('without a watch, opting out still only hints', () async {
    final built = await runBuild(step(), enabled: false, watching: false);
    expect(built.code, 0);
    expect(built.ran, isFalse);
    expect(built.handedToWatch, isFalse);
  });

  test('detection answers without throwing', () {
    expect(buildRunnerWatchPid(), anyOf(isNull, isA<int>()));
  });

  test('an orphaned watch is not mistaken for a live one', () async {
    // A decoy whose command line matches the scan, started so that its parent
    // shell exits immediately — the shape a watch takes once its terminal or
    // IDE dies, and the case that made the first cut of this guard skip builds
    // nobody was going to run.
    //
    // It orphans a *real* process rather than stubbing the answer, which is what
    // makes it worth running: the first cut split on `ppid <= 1` and this case
    // failed on any machine with a subreaper between the process and init —
    // `systemd --user` reparents an orphan to the user manager, whose pid is not
    // 1. So what is asserted below is the behaviour, not the mechanism.
    // `... build_runner_decoy.sh watch` — `watch` as the token after the
    // build_runner one, the shape the scan looks for.
    final script = File(
      p.join(Directory.systemTemp.path, 'build_runner_decoy.sh'),
    )..writeAsStringSync('sleep 20\n');
    final started = await Process.run('sh', [
      '-c',
      r'nohup sh '
          '${script.path}'
          r' watch >/dev/null 2>&1 & echo $!',
    ]);
    final decoy = int.parse((started.stdout as String).trim());
    addTearDown(() {
      Process.runSync('kill', ['-9', '$decoy']);
      if (script.existsSync()) script.deleteSync();
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final scanned =
        Process.runSync('pgrep', ['-f', r'build_runner[^ ]* watch']).stdout
            as String;
    expect(
      scanned,
      contains('$decoy'),
      reason: 'the decoy must match the scan, or this proves nothing',
    );
    expect(
      buildRunnerWatchPid(),
      isNot(decoy),
      reason: 'an orphan must not count as a live watch',
    );
    // The same process doctor reports: skipped as a build partner precisely
    // because it does no work, so someone has to be told it is there.
    expect(
      orphanedBuildRunnerWatchPids(),
      contains(decoy),
      reason: 'an orphan must still be findable, to be reported',
    );
  }, testOn: 'posix');

  test('a watch whose launcher is alive is live, and not an orphan', () async {
    // The other half, and the one that must not regress while the orphan case is
    // being fixed: this process is the decoy's parent and is very much alive, so
    // frx has to stand down for it.
    final script = File(
      p.join(Directory.systemTemp.path, 'build_runner_live.sh'),
    )..writeAsStringSync('sleep 20\n');
    final live = await Process.start('sh', [script.path, 'watch']);
    addTearDown(() {
      live.kill(ProcessSignal.sigkill);
      if (script.existsSync()) script.deleteSync();
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      orphanedBuildRunnerWatchPids(),
      isNot(contains(live.pid)),
      reason: 'its parent is this test process, which is running',
    );
    expect(buildRunnerWatchPid(), isNotNull);
  }, testOn: 'posix');

  test('a command that merely mentions both words is not a watch', () async {
    // `tail -f build_runner-watch.log` and friends: the words are there, the
    // shape is not. Counting one as a live watch would make frx refuse to
    // build and name an unrelated pid.
    final log = File(
      p.join(Directory.systemTemp.path, 'build_runner-watch.log'),
    )..writeAsStringSync('');
    final started = await Process.run('sh', [
      '-c',
      r'nohup tail -f '
          '${log.path}'
          r' >/dev/null 2>&1 & echo $!',
    ]);
    final impostor = int.parse((started.stdout as String).trim());
    addTearDown(() {
      Process.runSync('kill', ['-9', '$impostor']);
      if (log.existsSync()) log.deleteSync();
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(buildRunnerWatchPid(), isNot(impostor));
    expect(orphanedBuildRunnerWatchPids(), isNot(contains(impostor)));
  }, testOn: 'posix');
}
