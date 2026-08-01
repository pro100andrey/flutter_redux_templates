/// Where the CLI writes.
///
/// Every command wrote to the process streams directly — about 150 call sites —
/// and that single fact shaped the whole test suite. `test/support/fixture.dart`
/// states it outright: *"Running the CLI in-process is awkward (it writes to
/// real stdout)"*, which is why every command test shells out to a cached
/// kernel snapshot, and why fifteen of the twenty-seven commands had no test at
/// all: covering one meant a subprocess, a fixture repo on disk, and a
/// second-guess at what the output should look like.
///
/// The sinks are [StringSink]s, so the swap costs nothing at the call site —
/// a bare `stdout.writeln(x)` becomes `console.out.writeln(x)`, cascades and
/// all — and a test supplies two `StringBuffer`s, which already implement it.
///
/// Held in a [Zone] rather than a mutable global: `dart test` runs the cases in
/// a suite on one isolate, so a global would be shared state between them, and
/// a test that forgot to restore it would corrupt whatever ran next. A zone
/// value is scoped to the body that asked for it and cannot leak.
library;

import 'dart:async';
import 'dart:io' as io;

/// The pair of sinks a command writes to, plus where it reads a piped
/// declaration from.
class Console {
  const Console(this.out, this.err, {this.input});

  /// The report: plans, tables, JSON, the ✓ lines.
  final StringSink out;

  /// Warnings and failures. Kept separate because `--json` consumers parse
  /// [out] and a warning mixed into it would break the parse.
  final StringSink err;

  /// Standard input, when a test supplies one. Null means the process's own.
  ///
  /// Only `frx batch -` reads it, and it is here rather than read directly for
  /// the reason the sinks are: a test that had to pipe a real stdin would need a
  /// subprocess, which is what kept fifteen commands untested.
  final String? input;

  /// Everything on standard input, as text.
  Future<String> stdinText() async =>
      input ?? await io.systemEncoding.decodeStream(io.stdin);

  /// The real process streams.
  static Console get standard => Console(io.stdout, io.stderr);
}

const _key = #frxConsole;

/// The console for the current scope — the process streams unless a
/// [withConsole] is in effect.
Console get console => (Zone.current[_key] as Console?) ?? Console.standard;

/// Runs [body] with everything it writes going to [replacement].
///
/// The seam the command tests use. Note what it does *not* redirect: a
/// subprocess frx spawns (`dart format`, `build_runner`) inherits the real
/// streams, because it is a different process and a zone does not cross that
/// boundary. Commands that shell out are still tested through their plan.
R withConsole<R>(Console replacement, R Function() body) =>
    runZoned(body, zoneValues: {_key: replacement});

/// A console that keeps what was written, for tests.
class CapturedConsole extends Console {
  CapturedConsole._(this._out, this._err, {super.input}) : super(_out, _err);

  factory CapturedConsole({String? input}) =>
      CapturedConsole._(StringBuffer(), StringBuffer(), input: input);

  final StringBuffer _out;
  final StringBuffer _err;

  /// Everything written to [out].
  String get output => _out.toString();

  /// Everything written to [err].
  String get errors => _err.toString();

  /// Deliberately not offered: the two buffers interleaved. That ordering is an
  /// artefact of the capture, not what a terminal saw, and a test asserting it
  /// would be asserting the artefact.
  @override
  String toString() =>
      'CapturedConsole(out: ${_out.length} chars, err: ${_err.length} chars)';
}
