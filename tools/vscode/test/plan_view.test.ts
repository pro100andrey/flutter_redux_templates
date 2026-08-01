import { contextKey, previewTab, reset, vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import {
  applyPending,
  buildPlanMarkdown,
  confirm,
  discardPending,
  drift,
  showPlan,
  summarize,
} from '../src/plan_view';
import { parseWritePlan } from '../src/queries';
import type { WritePlan } from '../src/queries';

/// The plan surface: a markdown document the platform renders, built from the
/// CLI's machine plan rather than by re-parsing its human report.
///
/// Two things are worth pinning. The shape a reader depends on — paths in a
/// monospace table, linked into the files they name — and the fact that the
/// document *answers itself*: the ✓/✕ that used to be a modal covering the plan
/// now ride on the plan's own tab, so what has to hold is that the gate showing
/// them tracks that tab exactly, and that every way out of the wait resolves it
/// once.

const plan: WritePlan = {
  command: 'rename',
  applied: false,
  changes: [
    {
      op: 'move',
      from: '/repo/business/lib/redux/theme/models/theme_state.dart',
      path: '/repo/business/lib/redux/app_theme/models/app_theme_state.dart',
    },
    { op: 'delete', path: '/repo/business/lib/redux/theme/models/theme_state.freezed.dart' },
    {
      op: 'edit',
      path: '/repo/business/lib/redux/app_state.dart',
      diff: '--- a/business/lib/redux/app_state.dart\n+++ b/…\n-  ThemeState theme,\n+  AppThemeState appTheme,',
    },
  ],
};

test('every path is a monospace link into the file it names', () => {
  const md = buildPlanMarkdown(plan, { title: 'Rename "theme" → "appTheme"' });
  assert.match(md, /\| --- \| --- \|/, 'the paths are in a table');
  assert.match(
    md,
    /\[`\/repo\/business\/lib\/redux\/app_state\.dart`\]\(file:\/\/\/repo\/business\/lib\/redux\/app_state\.dart\)/,
    'an edited file is monospace and clickable',
  );
});

test('a move links its source, not its destination', () => {
  // The destination does not exist yet, and a link to a file that is not there
  // opens nothing.
  const md = buildPlanMarkdown(plan, { title: 'x' });
  assert.match(md, /\[`[^`]*theme_state\.dart`\]\(file:\/\/\/[^)]*theme_state\.dart\) → `[^`]*app_theme_state\.dart`/);
});

test('the summary counts by operation, and reads', () => {
  assert.strictEqual(
    summarize(plan.changes),
    '**1 file moved · 1 file deleted · 1 file edited**',
  );
  assert.strictEqual(summarize([]), '**Nothing to do.**');
  assert.strictEqual(
    summarize([
      { op: 'delete-directory', path: '/a' },
      { op: 'edit', path: '/b' },
      { op: 'edit', path: '/c' },
    ]),
    '**1 folder deleted · 2 files edited**',
  );
});

test('an operation the format grows later is named, not mangled', () => {
  // Compatibility is additive-only: a consumer must not choke on a field — or an
  // operation — it does not recognise.
  assert.strictEqual(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    summarize([{ op: 'transmute' as any, path: '/a' }]),
    '**1 transmute**',
  );
});

test('the diffs the plan carries are fenced as diff blocks', () => {
  const md = buildPlanMarkdown(plan, { title: 'x' });
  assert.match(md, /```diff\n--- a\/business\/lib\/redux\/app_state\.dart/);
  // No renderer of our own — the fence is what the platform draws from.
  assert.ok(!md.includes('<script'), 'the document ships no renderer');
});

test('warnings from the CLI land in the document, not in the dialog', () => {
  const md = buildPlanMarkdown(plan, {
    title: 'x',
    warnings: '⚠ child pages are left behind',
  });
  assert.match(md, /## Warnings/);
  assert.match(md, /child pages are left behind/);
});

test('an empty changeset says so rather than showing an empty table', () => {
  const md = buildPlanMarkdown({ command: 'remove', applied: false, changes: [] }, { title: 'x' });
  assert.match(md, /Nothing to do\./);
  assert.ok(!md.includes('| --- | --- |'));
});

test('the document points at the buttons that answer it', () => {
  // The plan no longer has a dialog in front of it demanding an answer, so the
  // document has to say that it is waiting, and where the answer is.
  const md = buildPlanMarkdown(plan, { title: 'x' });
  assert.match(md, /Nothing is written until you press \*\*✓ Apply\*\*/);
  assert.match(md, /closing the tab — forgets it/);
});

/** A fake extension context pointing at a scratch directory. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const context = { storageUri: vscode.Uri.file('/store') } as any;

/** Let the best-effort tidy-up after an answered plan run to completion. */
const flush = (): Promise<void> => new Promise((r) => setImmediate(r));

/** The document of the most recent `showPlan`, as VSCode was asked to open it. */
function lastOpened(): any {
  const opens = vscode._commands.filter((c) => c.id === 'vscode.openWith');
  return opens[opens.length - 1].args[0];
}

/**
 * Plan → open its tab → hand back the wait, still outstanding.
 *
 * Wrapped in an object rather than returned bare: `await` flattens a promise of
 * a promise, so returning the wait directly would make every caller sit on an
 * answer nobody has given yet. The document is read back from the open call
 * rather than spelled out — which document a plan gets is the code's business.
 */
async function pendingPlan(): Promise<{ answer: Promise<boolean>; uri: any }> {
  reset();
  await showPlan(context, plan, { title: 'x' });
  const uri = lastOpened();
  const answer = confirm('Rename "theme" → "appTheme"?', plan);
  vscode.window.tabGroups._open(previewTab(uri));
  return { answer, uri };
}

test('the plan opens as the built-in preview, beside the code', async () => {
  await pendingPlan();
  const open = vscode._commands.find((c) => c.id === 'vscode.openWith');
  assert.ok(open, 'the plan is opened through openWith, not markdown.showPreview');
  assert.strictEqual(open!.args[1], 'vscode.markdown.preview.editor');
  assert.strictEqual(open!.args[2].viewColumn, vscode.ViewColumn.Beside);
  // A reusable italic tab would be taken over by the next file opened in that
  // column — including one opened by following a link out of the plan.
  assert.strictEqual(open!.args[2].preview, false);
  discardPending();
});

test('the toolbar gate is raised only while the plan tab is the active one', async () => {
  const { answer } = await pendingPlan();
  assert.strictEqual(contextKey('frx.planTabActive'), true);

  // Following a path out of the table lands you on another tab. The buttons go
  // with it — but the plan is still waiting.
  vscode.window.tabGroups._activate({ label: 'app_state.dart', input: {} });
  assert.strictEqual(contextKey('frx.planTabActive'), false);
  assert.strictEqual(vscode._statusBar.length, 1, 'the chip says the plan is still waiting');

  discardPending();
  await answer;
});

test('the buttons on someone else’s markdown preview are not these buttons', async () => {
  const { answer } = await pendingPlan();
  // A different document in the same built-in preview must not offer to apply
  // this plan — which is exactly what a viewType-only check could not tell.
  vscode.window.tabGroups._activate(previewTab(vscode.Uri.file('/store/frx-diagram.md')));
  assert.strictEqual(contextKey('frx.planTabActive'), false);
  discardPending();
  await answer;
});

test('✓ Apply resolves the wait, and ✕ Discard resolves it the other way', async () => {
  const yes = await pendingPlan();
  applyPending();
  assert.strictEqual(await yes.answer, true);

  const no = await pendingPlan();
  discardPending();
  assert.strictEqual(await no.answer, false);
});

test('answering retires the plan: tab, document, gate and chip', async () => {
  const { answer, uri } = await pendingPlan();
  assert.strictEqual(vscode._statusBar.length, 1);
  assert.ok(vscode._files.has(uri.fsPath), 'the document is on disk while it is asked about');
  applyPending();
  await answer;
  await flush();

  assert.strictEqual(vscode.window.tabGroups._group.tabs.length, 0, 'the tab is gone');
  // An answered plan left lying around is one a later plan can be mistaken for.
  assert.ok(!vscode._files.has(uri.fsPath), 'the document is gone too');
  assert.strictEqual(contextKey('frx.planTabActive'), false);
  assert.strictEqual(vscode._statusBar.length, 0, 'the chip is gone');
});

test('closing the plan tab is a No', async () => {
  const { answer } = await pendingPlan();
  const tab = vscode.window.tabGroups._group.tabs[0];
  await vscode.window.tabGroups.close(tab);
  assert.strictEqual(await answer, false);
  assert.strictEqual(vscode._statusBar.length, 0);
});

test('a second plan gets its own document, and retires the first', async () => {
  const { answer: first, uri: firstUri } = await pendingPlan();

  // The bug this pins: ask for a removal straight after a rename and the
  // *rename's* plan is what appears. VSCode caches a text model by URI and keeps
  // it past the editor that used it, so writing new bytes to a path it already
  // knows renders the old ones. Two plans therefore never share a path — which
  // also makes retiring the first unambiguous, where one path made closing "the
  // plan tab" close the tab the replacement had just opened.
  await showPlan(context, plan, { title: 'y' });
  const secondUri = lastOpened();
  assert.notStrictEqual(secondUri.toString(), firstUri.toString(), 'a document of its own');

  assert.strictEqual(await first, false, 'the superseded plan answers No');
  await flush();
  assert.strictEqual(vscode.window.tabGroups._group.tabs.length, 0, 'the first tab is gone');
  assert.ok(!vscode._files.has(firstUri.fsPath), 'and so is the document behind it');

  const second = confirm('Remove "theme"? This deletes its files.', plan);
  vscode.window.tabGroups._open(previewTab(secondUri));
  assert.strictEqual(contextKey('frx.planTabActive'), true, 'the new plan’s buttons are live');
  applyPending();
  assert.strictEqual(await second, true);
});

test('the chip carries the question, without a second sentence or its mark', () => {
  reset();
  confirm('Remove "theme"? This deletes its files and unwires it.', plan);
  assert.strictEqual(vscode._statusBar[0].text, '$(edit) FRX: Remove "theme"');
  // Applying is only ever reachable past the plan — the chip reveals it.
  assert.strictEqual(vscode._statusBar[0].command, 'frx.planShow');
  discardPending();
});

test('drift: the applied changeset is compared with the one that was shown', () => {
  assert.strictEqual(drift(plan.changes, plan.changes), null);
  // Re-derivation over changed neighbouring lines is the point of re-deriving,
  // so a differing diff over an identical file set is not drift.
  const restated = plan.changes.map((c) => ({ ...c, diff: c.diff && `${c.diff}\n+ // later` }));
  assert.strictEqual(drift(plan.changes, restated), null);
  // A file that was not in the plan is.
  const extra = [...plan.changes, { op: 'edit' as const, path: '/repo/app/lib/router.dart' }];
  assert.strictEqual(
    drift(plan.changes, extra),
    '1 file moved · 1 file deleted · 2 files edited, where the plan showed ' +
      '1 file moved · 1 file deleted · 1 file edited',
  );
});

test('parseWritePlan: reads the changeset, and rejects anything else', () => {
  const parsed = parseWritePlan(JSON.stringify(plan));
  assert.strictEqual(parsed?.changes.length, 3);
  assert.strictEqual(parsed?.applied, false);
  // The human report, which is what this used to re-parse.
  assert.strictEqual(parseWritePlan('Files:\n  move a → b\n'), null);
  assert.strictEqual(parseWritePlan('{}'), null);
  assert.strictEqual(parseWritePlan(''), null);
});

test('parseWritePlan: an unknown field is carried, not rejected', () => {
  const parsed = parseWritePlan(
    JSON.stringify({ command: 'rename', applied: false, changes: [], somethingNew: 42 }),
  );
  assert.ok(parsed, 'additive-only means a new field must not break the read');
});
