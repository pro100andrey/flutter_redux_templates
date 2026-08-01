import 'dart:io';
import 'console.dart';

/// Minimal stdin prompting for the `frx new` wizard. Works on a TTY and on
/// piped input alike (EOF → [AbortException]), so wizard flows are testable
/// with `echo -e '…' | frx new`.
class AbortException implements Exception {
  const AbortException();
}

/// Reads one line, trimmed. Throws [AbortException] on EOF (ctrl-D / end of
/// piped input).
String _readLine() {
  final line = stdin.readLineSync();
  if (line == null) throw const AbortException();
  return line.trim();
}

/// Asks a free-form question. Empty input returns [def] when given; when
/// [required] and no default, re-asks. [pattern] re-asks until matched.
String ask(
  String question, {
  String? def,
  bool required = true,
  RegExp? pattern,
  String? hint,
}) {
  while (true) {
    final suffix = def != null ? ' [$def]' : '';
    console.out.write('$question$suffix: ');
    final input = _readLine();
    if (input.isEmpty) {
      if (def != null) return def;
      if (!required) return '';
      console.out.writeln('  (required${hint != null ? ' — $hint' : ''})');
      continue;
    }
    if (pattern != null && !pattern.hasMatch(input)) {
      console.out.writeln('  (invalid${hint != null ? ' — $hint' : ''})');
      continue;
    }
    return input;
  }
}

/// Numbered single choice; empty input picks the first option.
String choose(String question, Map<String, String> options) {
  console.out.writeln('$question:');
  final keys = options.keys.toList();
  for (var i = 0; i < keys.length; i++) {
    console.out.writeln('  ${i + 1}. ${keys[i]} — ${options[keys[i]]}');
  }
  while (true) {
    console.out.write('Choice [1]: ');
    final input = _readLine();
    if (input.isEmpty) return keys.first;
    final n = int.tryParse(input);
    if (n != null && n >= 1 && n <= keys.length) return keys[n - 1];
    // Also accept the option name itself.
    if (keys.contains(input)) return input;
    console.out.writeln('  (enter 1–${keys.length})');
  }
}

/// Yes/no; empty input returns [def].
bool confirm(String question, {bool def = false}) {
  while (true) {
    console.out.write('$question [${def ? 'Y/n' : 'y/N'}]: ');
    final input = _readLine().toLowerCase();
    if (input.isEmpty) return def;
    if (input == 'y' || input == 'yes') return true;
    if (input == 'n' || input == 'no') return false;
  }
}

/// Comma-separated list; [min] entries required (0 allows empty → []).
List<String> askList(String question, {int min = 0, String? hint}) {
  while (true) {
    console.out.write('$question${min == 0 ? ' (optional)' : ''}: ');
    final items = _readLine()
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (items.length >= min) return items;
    console.out.writeln(
      '  (need at least $min${hint != null ? ' — $hint' : ''})',
    );
  }
}
