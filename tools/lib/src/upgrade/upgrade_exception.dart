import 'dart:io';

/// Raised for a failure the caller should report as-is rather than interpret.
class UpgradeException implements Exception {
  UpgradeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `Process.runSync` with the one failure it does not report through its
/// result turned into one that is.
///
/// A binary that is absent throws `ProcessException`, and nothing above this
/// catches it: the docstring promised a missing `tar` would be "reported
/// rather than worked around", and what actually happened was an unhandled
/// exception, a Dart stack trace and exit 255 — the shape of a crash, for a
/// condition the tool understands perfectly well.
ProcessResult runTool(
  String executable,
  List<String> arguments, {
  required String missing,
}) {
  try {
    return Process.runSync(executable, arguments);
  } on ProcessException catch (e) {
    throw UpgradeException('$missing (${e.message}).');
  }
}
