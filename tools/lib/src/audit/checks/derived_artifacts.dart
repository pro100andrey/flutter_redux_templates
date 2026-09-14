import 'package:path/path.dart' as p;

import '../../flow/flow_docs.dart';
import '../../refusal.dart';
import '../../skills/skill_gen.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// The `docs/flows/` export is a pure function of the connectors, so anything
/// it doesn't match is drift. Opt-in: checked only once the directory exists,
/// which is what `frx flow --md` creates.
void checkFlowDocs(FrxWorkspace repo, List<Finding> into) {
  final docs = FlowDocs(repo);
  if (!docs.enabled) {
    return;
  }

  final List<DocDrift> drift;
  try {
    drift = docs.check();
  } on FrxRefusal {
    // No AppRouter — `checkRoutesAndConnectors` already said so.
    return;
  }

  for (final d in drift) {
    into.add(
      Finding.error(
        '${d.message} — run `frx flow --md`.',
        // A missing file can't be squiggled; the rest can.
        file: d.kind == DocDriftKind.missing ? null : d.path,
        fix: const FlowDocsFix(),
      ),
    );
  }
}

/// `.claude/skills/` that a different frx wrote.
///
/// The skills are what an agent reads before it writes, so a stale one
/// describes a CLI that is not there — a flag that has gone, a command that
/// never arrived. It is the one derived artifact whose drift misleads a
/// *reader* rather than breaking a build, which is why it is worth a finding
/// rather than a note in a changelog.
///
/// **Compared by content, not by the version stamp.** The stamp says which frx
/// wrote the tree and is what the message quotes, but a hand-edited skill is
/// stale at the right version, and that is the case worth catching in a project
/// somebody has been editing.
///
/// Opt-in on the manifest: without `.frx-owned` this tree predates
/// `update-skills` or is somebody's own, and which of those it is cannot be
/// told from the directory names — the guess the manifest exists to stop.
void checkSkills(FrxWorkspace repo, List<Finding> into) {
  final dir = repo.claudeSkills;
  if (!dir.existsSync()) {
    return;
  }

  final owned = SkillGen.ownedIn(dir);
  if (owned.version == null) {
    return;
  }

  // The manifest carries the version, so it changes on every bump — and a bump
  // with no change to any command's surface leaves all thirty skills identical.
  // Reporting that would say "an agent is reading a description of a CLI that
  // is not here" about a tree that describes it exactly, and would contradict
  // this check's own rule two paragraphs up. Only the skills count.
  final stale = SkillGen()
      .changesIn(repo)
      .any((c) => !c.path.endsWith(SkillGen.manifestName));
  if (!stale) {
    return;
  }

  into.add(
    Finding.warn(
      '.claude/skills/ is not what frx ${SkillGen.version} generates'
      '${owned.version == SkillGen.version ? '' : ' (it was written by '
                '${owned.version})'}'
      ' — an agent is reading a description of a CLI that is not here.',
      // The manifest, which is guaranteed to be there — it is the gate above.
      // A finding with no file has no document for a lightbulb to hang off, so
      // it reaches the editor as prose and the remedy is never offered.
      file: p.join(dir.path, SkillGen.manifestName),
      fix: const SkillsFix(),
    ),
  );
}
