import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../skills/skill_gen.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Rewrites `.claude/skills/` from the CLI that is running.
///
/// **The one artifact a generated project could not refresh.** `frx create`
/// packs `.claude/` into the archive and leaves `tools/` behind, so a project
/// arrives with the skills of whichever frx made it and no way to re-derive
/// them — `skills_freshness_test` says as much, and was right when it was
/// written. It stopped being right the moment `SkillGen` moved into `lib/`: the
/// generator reads nothing but the command objects, so it is already inside
/// every installed binary. What was missing was a way to ask it.
///
/// **It edits rather than creates**, which is not a detail. Every file it
/// writes is one it wrote last time, so routing them through the overwrite
/// guard would demand `--force` on a command whose whole job is to overwrite —
/// and would hide the thing worth seeing, which is `--diff` of what a newer frx
/// says differently.
class UpdateSkillsCommand extends WritingCommand {
  // `--force` would mean nothing here: nothing is refused for existing.
  @override
  WriteFlags get flags => const WriteFlags(force: false, diff: true);

  // `WritingCommand` mixes in `NameArg`, whose default is a single `<name>`.
  // This one names nothing: the tree it writes is the whole tree.
  @override
  List<String> get positionals => const [];

  @override
  String get name => 'update-skills';

  @override
  String get description =>
      "Rewrite .claude/skills/ from this frx's own commands.";

  @override
  String get invocation => 'frx update-skills [--dry-run]';

  @override
  List<String> get aliases => ['us'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final skillsDir = Directory(p.join(repo.root.path, '.claude', 'skills'));
    final owned = SkillGen.ownedIn(skillsDir);
    // Rendered once and handed on: the header wants the count and the plan
    // wants the content, and they are the same render.
    final generated = SkillGen.generate();
    final changes = Changeset(
      SkillGen.changesIn(repo.root, generated: generated),
    );
    final skills = changes.changes
        .where((c) => c.path.endsWith('SKILL.md'))
        .length;
    final removed = changes.changes.whereType<DeleteDirectory>().length;

    return WritePlan(
      changes: changes,
      // `SkillGen.directories().length`, not another `generate()`: the header
      // wants a count, and rendering thirty documents a third time to take
      // `.length` of them is the sort of thing this repository measures.
      header:
          'Skills — ${SkillGen.directories().length} for frx '
          '${SkillGen.version}',
      narrate: () {
        if (changes.isEmpty) {
          console.out.writeln('  Already current — nothing to do.');
          return;
        }
        if (owned.version != null && owned.version != SkillGen.version) {
          console.out.writeln(
            '  Written by frx ${owned.version}; this is ${SkillGen.version}.',
          );
        }
        console.out.writeln(
          skills == 0 && removed == 0
              ? '  Every skill is current; only the manifest moved.'
              : '  $skills skill(s) rewritten'
                    '${removed == 0 ? '' : ', $removed removed'}.',
        );
      },
      closing: changes.isEmpty
          ? null
          : 'The skills are what an agent reads before it writes. Re-run this '
                'after every frx upgrade.',
    );
  }
}
