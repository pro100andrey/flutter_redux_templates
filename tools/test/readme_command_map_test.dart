import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';

/// The README's command map must name every command, under its alias.
///
/// The skills are generated from the command objects and the extension reads
/// its constants out of them, so neither can drift. The README is prose, and
/// prose drifts: two commands had been on the CLI for releases and were not in
/// the table — `add-package` and `update-skills` — and nothing said so, because
/// nothing read the table. This reads it, the way `skills_freshness_test`
/// reads the skills.
///
/// Only the map is checked, not the sections below it: the map is the one
/// place the README claims to be complete ("every command has a short alias").
void main() {
  test('the command map lists every command with its alias', () {
    final readme = File(
      p.join(Directory.current.absolute.path, 'README.md'),
    ).readAsStringSync();

    final start = readme.indexOf('## Command map');
    expect(start, greaterThanOrEqualTo(0), reason: 'no "## Command map"');
    final end = readme.indexOf('\n## ', start + 1);
    final section = readme.substring(start, end < 0 ? readme.length : end);

    // `| \`name\` | \`alias\` | …` — the alias cell is empty for a command
    // that has none.
    final rows = RegExp(
      r'^\| `([a-z-]+)` \| (?:`([a-z]+)`)?\s*\|',
      multiLine: true,
    ).allMatches(section);
    final documented = {for (final m in rows) m.group(1)!: m.group(2)};
    expect(documented, isNotEmpty, reason: 'the table did not parse');

    final actual = {
      for (final c in FrxRunner().visibleCommands)
        c.name: c.aliases.firstOrNull,
    };

    expect(
      documented.keys.toSet().difference(actual.keys.toSet()),
      isEmpty,
      reason: 'the README names a command frx does not have',
    );
    expect(
      actual.keys.toSet().difference(documented.keys.toSet()),
      isEmpty,
      reason:
          'a command is missing from the README command map — add its row '
          'under the right heading in tools/README.md',
    );
    for (final entry in actual.entries) {
      expect(
        documented[entry.key],
        entry.value,
        reason: 'the alias the README gives `${entry.key}`',
      );
    }
  });
}
