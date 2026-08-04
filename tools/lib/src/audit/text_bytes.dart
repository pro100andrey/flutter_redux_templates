import 'dart:convert';

/// Why a text file is invisible to search.
///
/// Both causes have the same outcome and neither is visible in an editor: the
/// file looks exactly like its neighbours, compiles, and is skipped by every
/// search anyone runs against it.
enum Unsearchable {
  /// A NUL byte.
  ///
  /// Legal inside a Dart string literal — `'a\u0000b'` is a three-character
  /// string — and legal in the file that holds it. But `grep`, `git grep`,
  /// ripgrep and `file(1)` all classify a file containing one as *binary*, and
  /// the first three then skip it silently unless forced with `-a`.
  nulByte,

  /// Bytes that are not valid UTF-8.
  ///
  /// The same classification by a different route, and the one that also breaks
  /// the analyzer's own file reading — `File.readAsStringSync` throws rather
  /// than returning something wrong.
  notUtf8,
}

/// What makes [bytes] unsearchable and where, or null when nothing does.
///
/// The offset is a byte index, not a line: the point of the report is to be
/// actionable on a file no editor will show you the problem in, and `xxd -s
/// <offset>` is the tool that works there.
///
/// **Why this rule and not "any control byte".** Only these two cause the
/// skipping. A stray `0x01` is untidy, but `grep` still reads the file and still
/// finds what is in it, so reporting it would be this module claiming a
/// consequence it cannot demonstrate.
({Unsearchable kind, int offset})? unsearchableIn(List<int> bytes) {
  final nul = bytes.indexOf(0);
  if (nul >= 0) return (kind: Unsearchable.nulByte, offset: nul);
  try {
    const Utf8Decoder().convert(bytes);
  } on FormatException catch (e) {
    return (kind: Unsearchable.notUtf8, offset: e.offset ?? 0);
  }
  return null;
}

/// One sentence naming the problem and the fix, for a report.
///
/// Lives beside the rule so the audit and the test say the same thing about the
/// same file — the alternative is two wordings that drift, and this repository
/// has paid for that shape before.
String describeUnsearchable(Unsearchable kind, int offset) => switch (kind) {
  Unsearchable.nulByte =>
    'holds a NUL byte at offset $offset, which makes the whole file binary to '
        'grep, git grep and ripgrep — they skip it, so nothing declared here is '
        'findable. Write it as an escape (`\\u0000`), or key on something that '
        'needs no separator.',
  Unsearchable.notUtf8 =>
    'is not valid UTF-8 (first bad byte at offset $offset), so search tools '
        'treat it as binary and skip it, and `readAsStringSync` throws on it.',
};
