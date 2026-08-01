import 'dart:async';

import 'package:tools/src/command_runner.dart';
import 'package:tools/src/util/console.dart';

import 'fixture.dart';

/// The result of running a command in this process.
typedef Ran = ({int exitCode, String stdout, String stderr});

/// Runs `frx <args>` **in-process**, capturing what it writes.
///
/// The alternative — [runFrx] in `fixture.dart` — spawns a kernel snapshot per
/// call. That is ~0.2s each and needs the snapshot built first, which is why
/// fifteen commands had no test: the cost of the first one was a fixture repo
/// plus a subprocess. This is a function call.
///
/// `--root` is appended when the args do not already set it, matching the
/// subprocess helper so a test reads the same either way.
///
/// What this does *not* cover, and why the subprocess tests stay:
///
///  * anything a command shells out for — `dart format`, `build_runner`,
///    `dart fix` — writes to the real streams from another process, so a plan
///    that ends in one is asserted up to the point it spawns;
///  * `Directory.current`, which a zone cannot redirect. Commands that resolve
///    by cwd rather than `--root` (`__complete`) still need `runFrxIn`.
Future<Ran> runInProcess(Fixture fixture, List<String> args) async {
  final captured = CapturedConsole();
  final full = [
    ...args,
    if (!args.contains('--root')) ...['--root', fixture.root.path],
  ];
  // `withConsole` is synchronous in its return; the body's future is awaited
  // outside it, but the zone the future was *created* in is the one its
  // continuations run in, so the capture survives every await inside.
  final code = await withConsole(captured, () => FrxRunner().runFrx(full));
  return (exitCode: code, stdout: captured.output, stderr: captured.errors);
}

/// Runs `frx <args>` in-process against a root that is not a [Fixture] — the
/// real monorepo, for the read-only commands.
Future<Ran> runInProcessAt(String root, List<String> args) async {
  final captured = CapturedConsole();
  final code = await withConsole(
    captured,
    () => FrxRunner().runFrx([...args, '--root', root]),
  );
  return (exitCode: code, stdout: captured.output, stderr: captured.errors);
}
