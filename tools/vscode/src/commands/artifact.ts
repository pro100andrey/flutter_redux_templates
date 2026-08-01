// The artifact lifecycle commands: rename and remove a substate/page (files,
// classes, and every wiring reference).
//
// **Both always preview.** That is the risk grading as a rule: destructive
// operations always show a plan, creative ones never do. The plan opens as a
// markdown document beside the code and answers itself: ✓ Apply and ✕ Discard
// are on that tab's own toolbar (see plan_view.ts). Nothing covers the plan while
// you decide, which is the whole of what the modal got wrong.
//
// The document is built from the CLI's **machine** plan (`--json`), not by
// re-parsing the human report: rendering a table needs the plan as data.
//
// **Apply runs with `--json` too, and the two changesets are compared.** The CLI
// recomputes from disk rather than replaying the preview, and the answer can now
// wait as long as you like — so the tree may move in between. It is checked
// rather than prevented: `--apply` derives correct edits for the tree as it
// stands, and its pre-flight plus atomic rollback already cover the dangerous
// cases. What is left is that what ran might not be what you read, and that gets
// said out loud instead of being smoothed over.
import * as vscode from 'vscode';

import type { App } from '../app';
import * as config from '../config';
import * as cursor from '../cursor';
import * as frx from '../frx';
import * as plan from '../plan_view';
import * as queries from '../queries';
import * as ui from '../ui';
import type { ArtifactKind } from '../ui';

/**
 * What the entry points hand these commands. A tree item carries
 * `frxName`/`frxKind`; the F2 rename provider carries `name`/`newName`/`kind`;
 * the palette and the editor context menu pass nothing.
 *
 * There is no marker for *which* of those two it was. There used to be, unused:
 * the entry points that pass nothing are answered the same way — the cursor
 * first, the picker second — so the origin never decided anything.
 */
export interface ArtifactArg {
  frxName?: string;
  frxKind?: ArtifactKind;
  name?: string;
  newName?: string;
  kind?: string;
}

/**
 * Remove a substate or page: preview the plan, confirm, then apply with --force.
 */
export async function removeArtifact(app: App, arg?: ArtifactArg): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  let name = arg?.frxName;
  let kind: string | undefined = arg?.frxKind;
  if (!name) {
    const picked = await ui.pickArtifact(inv, targetDir, 'Remove — substate or page');
    if (!picked) return;
    name = picked.name;
    kind = picked.kind ?? kind; // picked from a group → we already know which
  }

  const base = ['remove', name, '--root', targetDir];
  if (kind) base.push('--kind', kind);

  // Preview: `remove` without --apply writes nothing and emits the changeset.
  const preview = await frx.runWithProgress(
    `FRX: planning removal of ${name}…`,
    inv,
    [...base, '--json'],
    targetDir,
  );

  // Ambiguous — the name is both a substate and a page. `remove` exits 64 for
  // this, but 64 is also the generic usage code, so match the message too so a
  // real usage error doesn't misfire the picker.
  if (preview.code === 64 && !kind && /substate.*and.*page/is.test(preview.stderr)) {
    const pick = await vscode.window.showQuickPick<vscode.QuickPickItem & { label: ArtifactKind }>(
      [
        { label: 'substate', description: 'Remove the AppState substate' },
        { label: 'page', description: 'Remove the page + route' },
      ],
      { title: `FRX — "${name}" is both a substate and a page`, placeHolder: 'Which to remove?' },
    );
    if (!pick) return;
    return removeArtifact(app, { frxName: name, frxKind: pick.label });
  }
  // Not found (exit 70) or another failure — surface the message, don't confirm.
  if (preview.code !== 0) {
    frx.output().show(true);
    const msg = (preview.stderr || preview.stdout || '').trim().split('\n').pop();
    vscode.window.showWarningMessage(`FRX: ${msg || `nothing to remove for "${name}".`}`);
    return;
  }

  const planned = queries.parseWritePlan(preview.stdout);
  if (!planned) return ui.fail(preview);

  // The document carries the plan and any warnings (a tab shell's "child pages
  // left behind" note goes to stderr); the modal only asks.
  await plan.showPlan(app.context, planned, {
    title: `Remove "${name}"`,
    warnings: preview.stderr,
  });
  const go = await plan.confirm(`Remove "${name}"? This deletes its files and unwires it.`, planned);
  if (!go) return;

  // Apply. The CLI's -b runs the correct build_runner for the kind (a page
  // removal needs clean+build, which the CLI handles); skip it while the watch
  // regenerates or when disabled.
  const applyArgs = [...base, '--apply', '--json'];
  if (await shouldRunBuildForRemoval(app)) applyArgs.push('-b');

  const res = await frx.runWithProgress(`FRX: removing ${name}…`, inv, applyArgs, targetDir);
  if (res.code !== 0) return ui.fail(res);
  reportApplied(res.stdout, planned, `removed "${name}"`);
  app.refresh();
}

/**
 * Rename a substate or page — files, classes, and every wiring reference.
 * Every path previews the plan and confirms before applying.
 *
 * With no name given — the palette and the editor context menu — **the symbol
 * under the cursor is tried first**, through the same resolver the F2 provider
 * uses. Right-clicking a state class used to discard the cursor and offer you
 * every substate and page in the project. On a symbol frx does not own (or with
 * no Dart editor open) it falls back to that picker, which is still the right
 * answer for the palette.
 */
export async function renameArtifact(app: App, arg?: ArtifactArg): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  let kind: string | undefined = arg?.kind ?? arg?.frxKind;
  let oldName = arg?.name ?? arg?.frxName;
  if (!oldName) {
    const atCursor = await cursor.artifactAtActiveCursor(app.context);
    if (atCursor) {
      oldName = atCursor.name;
      kind = atCursor.kind;
    }
  }
  if (!oldName) {
    const picked = await ui.pickArtifact(inv, targetDir, 'Rename — current substate or page');
    if (!picked) return;
    oldName = picked.name;
    kind = picked.kind ?? kind; // picked from a group → we already know which
  }
  let newName = arg?.newName;
  if (!newName) {
    newName = await ui.askName(`Rename "${oldName}" → new name`, 'myNewName');
    if (newName === undefined) return;
  }
  if (newName === oldName) return; // no-op

  const base = ['rename', oldName, newName, '--root', targetDir];
  if (kind) base.push('--kind', kind);

  // Preview (no --apply): frx writes nothing and emits the changeset — files
  // moved, stale generated files dropped, and every file whose references change.
  const preview = await frx.runWithProgress(
    'FRX: planning rename…',
    inv,
    [...base, '--json'],
    targetDir,
  );
  if (preview.code !== 0) {
    frx.output().show(true);
    const msg = (preview.stderr || preview.stdout || '').trim().split('\n').pop();
    vscode.window.showWarningMessage(`FRX: ${msg || `cannot rename "${oldName}".`}`);
    return;
  }
  const planned = queries.parseWritePlan(preview.stdout);
  if (!planned) return ui.fail(preview);

  // A rename moves files and rewrites references across packages — show exactly
  // what it will touch instead of applying it sight-unseen.
  await plan.showPlan(app.context, planned, {
    title: `Rename "${oldName}" → "${newName}"`,
    warnings: preview.stderr,
  });
  if (!(await plan.confirm(`Rename "${oldName}" → "${newName}"?`, planned))) {
    return;
  }

  // Apply. Regenerate non-interactively only when the watch is off AND the
  // setting is "always"; otherwise the stale part shows up in doctor.
  const applyArgs = [...base, '--apply', '--json'];
  if (!app.watch?.running && config.runBuildRunner() === 'always') {
    applyArgs.push('-b');
  }

  const res = await frx.runWithProgress(`FRX: renaming ${oldName} → ${newName}…`, inv, applyArgs, targetDir);
  if (res.code !== 0) return ui.fail(res);
  reportApplied(res.stdout, planned, `renamed "${oldName}" → "${newName}"`);
  app.refresh();
}

/**
 * Say what was done — and, when it was not what the plan showed, say that too.
 *
 * `--json` is what makes the comparison possible and is also what suppresses the
 * CLI's own closing line (`rename_command.dart` prints it only when not in
 * machine mode), so the channel gets that line from here instead: a log that goes
 * quiet the moment the editor starts reading a command's output is a worse trade
 * than writing one sentence.
 */
function reportApplied(stdout: string, shown: queries.WritePlan, did: string): void {
  frx.output().appendLine(`✓ FRX: ${did}. Run \`dart analyze\` to confirm nothing dangles.`);

  const applied = queries.parseWritePlan(stdout);
  const changed = applied && plan.drift(shown.changes, applied.changes);
  if (!changed) {
    vscode.window.showInformationMessage(`FRX: ${did}.`);
    return;
  }
  void vscode.window
    .showWarningMessage(
      `FRX: ${did} — the tree changed since the plan: ${changed}.`,
      'Show output',
    )
    .then((pick) => {
      if (pick) frx.output().show(true);
    });
}

/** Whether to append `-b` to a removal, honouring watch state + the setting. */
async function shouldRunBuildForRemoval(app: App): Promise<boolean> {
  if (app.watch?.running) return false;
  const mode = config.runBuildRunner();
  if (mode === 'never') return false;
  if (mode === 'always') return true;
  const pick = await vscode.window.showInformationMessage(
    'FRX: run build_runner to finish the removal?',
    'Run build_runner',
  );
  return pick === 'Run build_runner';
}
