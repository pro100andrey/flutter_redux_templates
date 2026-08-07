import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/skills/skill_gen.dart';

/// `.claude/skills/` must be what the CLI's commands currently say.
///
/// The skills are a derived artifact, like `docs/flows` and the embedded
/// template: a command gains a flag, or a new command is added, and the skill
/// that tells an agent about it is one commit behind until it is regenerated.
/// This is the guard that makes the generated copy trustworthy — the copy this
/// repository has already been burned by, in the editor extension, where a
/// hand-kept list of the surface drifted to eight of ten entries.
///
/// It is a test **as well as** a `doctor` check, and the division moved once.
/// The original reason for having no check — "a project made by `frx create`
/// carries the skills but not the generator, so there is nothing there to
/// re-derive them from" — stopped being true when `SkillGen` moved into `lib/`:
/// the generator is inside every installed binary, and `frx update-skills` is
/// how a project asks it. `checkSkills` is the check that fell out of that.
///
/// What stays here is what only this repository can assert: that the skills
/// *committed* to it are current, which is a claim about a commit rather than
/// about a working tree, and so belongs to CI.
void main() {
  test('.claude/skills matches the CLI commands', () {
    final repoRoot = p.dirname(Directory.current.absolute.path);
    final fresh = SkillGen.generate();

    const regen = 'Regenerate them: cd tools && make skills';

    // Named before compared, so a failure says which skill rather than "some
    // file differs".
    final onDisk = <String>{};
    final skillsDir = Directory(p.join(repoRoot, '.claude', 'skills'));
    if (skillsDir.existsSync()) {
      for (final e in skillsDir.listSync()) {
        if (e is Directory) {
          final f = File(p.join(e.path, 'SKILL.md'));
          if (f.existsSync()) {
            onDisk.add('.claude/skills/${p.basename(e.path)}/SKILL.md');
          }
        }
      }
    }

    expect(
      onDisk.difference(fresh.keys.toSet()),
      isEmpty,
      reason:
          'Skill(s) on disk that no command generates — a command was '
          'removed or renamed. $regen',
    );
    expect(
      fresh.keys.toSet().difference(onDisk),
      isEmpty,
      reason: 'Command(s) with no skill on disk. $regen',
    );

    for (final entry in fresh.entries) {
      final actual = File(p.join(repoRoot, entry.key)).readAsStringSync();
      expect(actual, entry.value, reason: '${entry.key} is stale. $regen');
    }
  });

  test('every command an agent reaches for has a skill', () {
    final generated = SkillGen.generate().keys
        .map((k) => k.split('/')[2])
        .where((n) => n.startsWith('frx-'))
        .map((n) => n.substring(4))
        .toSet();

    // The four the router names instead: `create` makes the project this runs
    // in, `new` is an interactive dialogue an agent cannot drive,
    // `completions` configures a shell, and `update-skills` writes the skills
    // themselves — a skill describing it would be the tree explaining how it
    // is regenerated, and `doctor` reports staleness anyway.
    const notReachedForMidTask = {
      'create',
      'new',
      'completions',
      'update-skills',
    };

    final runnerCommands = {
      for (final c in FrxRunner().commands.values)
        if (!c.hidden && c.name != 'help') c.name,
    }..removeAll(notReachedForMidTask);

    expect(
      runnerCommands.difference(generated),
      isEmpty,
      reason:
          'A command exists with no skill and no stated reason to lack '
          'one. Add it to the situations map in skill_gen.dart, or to the '
          'exclusion list here with why.',
    );
  });
}
