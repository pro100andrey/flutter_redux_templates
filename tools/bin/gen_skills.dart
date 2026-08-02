import 'dart:io';

import 'package:tools/src/skills/skill_gen.dart';
import 'package:path/path.dart' as p;

/// Writes `.claude/skills/` from the CLI's own command objects.
///
/// A derived artifact, like `docs/flows` and the embedded template: regenerate
/// it with `make skills`, and `skills_freshness_test.dart` fails when it is
/// stale, so `make check` and CI catch a command added without its skill.
void main(List<String> args) {
  final root = args.isNotEmpty
      ? args.first
      : p.normalize(p.join(Directory.current.path, '..'));
  final files = SkillGen.generate();

  // The tree is generated whole, so a skill for a command that no longer
  // exists has to go rather than linger as a trigger for nothing.
  final dir = Directory(p.join(root, '.claude', 'skills'));
  if (dir.existsSync()) {
    for (final e in dir.listSync()) {
      if (e is Directory && p.basename(e.path).startsWith('frx-')) {
        e.deleteSync(recursive: true);
      }
    }
  }

  for (final entry in files.entries) {
    final file = File(p.join(root, entry.key))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  stdout.writeln(
    '✓ ${files.length} skill(s) written to ${p.join(root, '.claude/skills')}',
  );
}
