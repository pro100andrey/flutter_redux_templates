/// A minimal, dependency-free unified diff — used by `--diff` to show the exact
/// textual change a wiring edit or a textual sweep makes, before it is applied.
///
/// Line-based LCS (fine for the small hand-written sources frx edits). Returns
/// an empty string when [oldText] and [newText] are identical.
String unifiedDiff(
  String oldText,
  String newText, {
  required String path,
  int context = 3,
}) {
  if (oldText == newText) return '';
  final a = _lines(oldText);
  final b = _lines(newText);
  final script = _editScript(a, b);
  final hunks = _hunks(script, context);
  if (hunks.isEmpty) return '';

  final out = StringBuffer()
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');
  for (final h in hunks) {
    out.writeln('@@ -${h.oldStart},${h.oldLen} +${h.newStart},${h.newLen} @@');
    for (final line in h.lines) {
      out.writeln('${line.tag}${line.text}');
    }
  }
  return out.toString();
}

List<String> _lines(String s) {
  if (s.isEmpty) return const [];
  final lines = s.split('\n');
  // A trailing newline yields a final empty element — drop it so it isn't shown
  // as a spurious line.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

class _Line {
  const _Line(this.tag, this.text);
  final String tag; // ' ' | '-' | '+'
  final String text;
}

/// An ordered edit script of equal / removed / added lines (LCS backtrack).
List<_Line> _editScript(List<String> a, List<String> b) {
  final m = a.length, n = b.length;
  // dp[i][j] = LCS length of a[i..] and b[j..].
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }

  final script = <_Line>[];
  var i = 0, j = 0;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      script.add(_Line(' ', a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      script.add(_Line('-', a[i]));
      i++;
    } else {
      script.add(_Line('+', b[j]));
      j++;
    }
  }
  while (i < m) {
    script.add(_Line('-', a[i++]));
  }
  while (j < n) {
    script.add(_Line('+', b[j++]));
  }
  return script;
}

class _Hunk {
  _Hunk(this.oldStart, this.newStart);
  final int oldStart;
  final int newStart;
  int oldLen = 0;
  int newLen = 0;
  final List<_Line> lines = [];
}

/// Groups the edit [script] into unified-diff hunks, keeping [context] equal
/// lines of context and merging changes separated by ≤ `2 * context` of them.
List<_Hunk> _hunks(List<_Line> script, int context) {
  // Positions of changed entries.
  final changed = <int>[
    for (var k = 0; k < script.length; k++)
      if (script[k].tag != ' ') k,
  ];
  if (changed.isEmpty) return const [];

  // Merge runs whose gap of equal lines is small enough to share a hunk.
  final ranges = <(int, int)>[];
  var start = changed.first, prev = changed.first;
  for (final c in changed.skip(1)) {
    if (c - prev - 1 > 2 * context) {
      ranges.add((start, prev));
      start = c;
    }
    prev = c;
  }
  ranges.add((start, prev));

  // Old/new 1-based line number at the start of each script entry.
  final hunks = <_Hunk>[];
  for (final (lo, hi) in ranges) {
    final from = (lo - context).clamp(0, script.length);
    final to = (hi + context + 1).clamp(0, script.length);
    // Compute the 1-based start lines by counting entries before `from`.
    var oldLine = 1, newLine = 1;
    for (var k = 0; k < from; k++) {
      if (script[k].tag != '+') oldLine++;
      if (script[k].tag != '-') newLine++;
    }
    final hunk = _Hunk(oldLine, newLine);
    for (var k = from; k < to; k++) {
      final line = script[k];
      hunk.lines.add(line);
      if (line.tag != '+') hunk.oldLen++;
      if (line.tag != '-') hunk.newLen++;
    }
    hunks.add(hunk);
  }
  return hunks;
}
