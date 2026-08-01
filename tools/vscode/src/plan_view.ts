// The plan a rename or a removal shows before it touches disk: a **markdown
// document whose own tab carries the two buttons that answer it**.
//
// The failure this replaces was that the question covered its own answer. The
// plan opened in a preview and a `showWarningMessage({ modal: true })` opened on
// top of it — and a modal in VSCode is *application*-modal, so it blocks the
// whole workbench. The document the dialog pointed at ("the plan is open beside
// this dialog") could not be scrolled or clicked until you had already answered.
// You saw what a rename would do only after agreeing to it, which is the one
// thing the preview exists to prevent.
//
// **A preview can carry buttons** — not in its body, but in its tab's toolbar,
// which is where `frx.routes` and `frx.flow` have lived all along
// (`contributes.menus.editor/title`). So the modal is gone: ✓ Apply and ✕ Discard
// are `editor/title` entries gated on `frx.planTabActive`, and nothing overlaps
// anything.
//
// **The document opens through `vscode.openWith` rather than
// `markdown.showPreview`**, and that is load-bearing rather than a preference.
// `vscode.markdown.preview.editor` is the built-in preview registered as a custom
// editor, so its tab is a `TabInputCustom` and carries a **`uri`**;
// `markdown.showPreview` produces a `TabInputWebview`, which carries only a
// `viewType`. Only the first lets us say *which document* a closed tab held —
// which is what makes "closing the tab is a No" exact, and what keeps the buttons
// from appearing on somebody else's markdown preview. The renderer is the same
// built-in one either way: this extension still ships none.
//
// **The machinery already exists here.** `flow_view.ts` writes a markdown
// document and lets the platform draw it; the plan takes the same path.
//
// The native refactor-preview panel was rejected for now, and the reason should
// stay recorded: it would render paths as a real file tree with inline diffs, but
// its per-change checkboxes are only honest if the *editor* applies the edits, and
// application belongs to the CLI together with formatting, the derived-docs
// refresh and codegen. Splitting that to get a prettier preview is a larger
// decision than a presentation change can make. A hand-written webview was
// rejected on this repository's own evidence: the structural picture is being
// rebuilt precisely because hand-rolled rendering cost more than the platform's.
import * as path from 'path';
import * as vscode from 'vscode';

import { scratchDir } from './flow_view';
import type { PlanChange, WritePlan } from './queries';

/**
 * The scratch document a plan renders into. **One document per plan**, and that
 * is not tidiness — a shared path is a bug factory, and it produced two.
 *
 * VSCode caches a text model by URI and keeps it alive past the closing of the
 * editor that used it, so writing new bytes to a familiar path and reopening it
 * renders *the old plan*: ask for a removal right after a rename and the rename's
 * plan is what appears. `markdown.preview.refresh` was the mitigation this file
 * used to carry, and a mitigation is what it is — the write still races the
 * model. And with one path, a plan that supersedes another has to be careful not
 * to close the tab its replacement just opened, because they are the same tab.
 *
 * A fresh path has neither problem: nothing is cached under it, and the old plan's
 * tab is unambiguously the old plan's. The counter restarting per session is
 * fine — a model does not outlive the window that cached it, and a leftover file
 * is overwritten and then read from disk.
 *
 * Separate from the diagram scratch file either way: a plan and a flow diagram
 * are different questions, and sharing a name would make asking one close the
 * other.
 */
const scratchName = (n: number): string => `frx-plan-${n}.md`;

/** Which plan document to write next. */
let planSeq = 0;

/** The built-in markdown preview, in its custom-editor form. */
const PREVIEW_EDITOR = 'vscode.markdown.preview.editor';

/** The context key the ✓/✕ toolbar entries are gated on. */
const PLAN_TAB_ACTIVE = 'frx.planTabActive';

/** What to write above the table. */
export interface PlanHeading {
  /** e.g. `Rename "theme" → "appTheme"`. */
  title: string;
  /** Anything the CLI warned about on stderr — a tab shell's orphaned children. */
  warnings?: string;
}

/**
 * Render [plan] as a markdown document.
 *
 * Pure, so the shape is testable without an editor. Paths land in a monospace
 * table and are links into the files they name — with one rule about which end of
 * a move is linked: the source, because the destination does not exist yet and a
 * link to a file that is not there opens nothing.
 */
export function buildPlanMarkdown(plan: WritePlan, heading: PlanHeading): string {
  const out: string[] = [`# ${heading.title}`, '', summarize(plan.changes), ''];

  if (plan.changes.length) {
    out.push('| | file |', '| --- | --- |');
    for (const c of plan.changes) out.push(`| ${c.op} | ${cell(c)} |`);
    out.push('');
  } else {
    out.push('Nothing to do.', '');
  }

  if (heading.warnings?.trim()) {
    out.push('## Warnings', '', ...heading.warnings.trim().split('\n'), '');
  }

  const diffs = plan.changes.filter((c) => c.diff?.trim());
  if (diffs.length) {
    out.push('## What changes', '');
    for (const c of diffs) {
      out.push(`### ${path.basename(c.path)}`, '', '```diff', c.diff!.trimEnd(), '```', '');
    }
  }

  // The footer names where the answer is, because the answer is no longer in
  // front of you demanding one: a document that just sits there has to say that
  // it is waiting, and on what.
  out.push(
    '---',
    '',
    '_Nothing is written until you press **✓ Apply** in this tab’s toolbar. ' +
      '**✕ Discard** — or closing the tab — forgets it._',
    '',
  );
  return out.join('\n');
}

/**
 * How each operation reads, singular and plural.
 *
 * Spelled out rather than pluralised by rule, because the rule gets
 * `delete-directory` wrong and the format may grow an operation at any time — an
 * unknown one falls back to its own name rather than to a mangling of it.
 */
const LABEL: Record<string, [string, string]> = {
  create: ['file created', 'files created'],
  overwrite: ['file overwritten', 'files overwritten'],
  edit: ['file edited', 'files edited'],
  delete: ['file deleted', 'files deleted'],
  'delete-directory': ['folder deleted', 'folders deleted'],
  move: ['file moved', 'files moved'],
};

/** `8 files edited · 2 files moved` — the line the status chip also carries. */
export function summarize(changes: PlanChange[]): string {
  if (!changes.length) return '**Nothing to do.**';
  const counts = new Map<string, number>();
  for (const c of changes) counts.set(c.op, (counts.get(c.op) ?? 0) + 1);
  const parts = [...counts.entries()].map(([op, n]) => {
    const label = LABEL[op];
    return `${n} ${label ? label[n === 1 ? 0 : 1] : op}`;
  });
  return `**${parts.join(' · ')}**`;
}

/**
 * How the changeset that was applied differs from the one that was shown, or
 * null when they match.
 *
 * The two are separate derivations: the CLI recomputes from disk on the apply
 * run rather than replaying the preview, and the buttons live on a tab you can
 * leave open — so the tree can move between reading a plan and accepting it.
 * Compared by address and operation rather than by diff: a diff differing while
 * the file set is identical is the same set of edits over changed neighbouring
 * lines, which is what re-derivation is *for*.
 */
export function drift(shown: PlanChange[], applied: PlanChange[]): string | null {
  const key = (c: PlanChange) => `${c.op}\t${c.from ?? ''}\t${c.path}`;
  const a = [...shown.map(key)].sort().join('\n');
  const b = [...applied.map(key)].sort().join('\n');
  if (a === b) return null;
  return `${plain(summarize(applied))}, where the plan showed ${plain(summarize(shown))}`;
}

/** The table cell for one change: the path(s), monospaced, linked where they exist. */
function cell(c: PlanChange): string {
  if (c.op === 'move' && c.from) return `${link(c.from)} → \`${c.path}\``;
  return link(c.path);
}

/** A path as a monospace link into the file it names. */
function link(file: string): string {
  return `[\`${file}\`](${vscode.Uri.file(file).toString()})`;
}

/** The plan currently waiting for an answer, if any. */
interface Pending {
  /** The document, and the identity of the tab showing it. */
  uri: vscode.Uri;
  /** Answer it, then close its tab and drop its document. Idempotent. */
  settle: (go: boolean) => void;
}

let pending: Pending | null = null;

/** Where the last plan was written — read by `confirm` to find its own tab. */
let planUri: vscode.Uri | null = null;

/**
 * Write the plan document and open it beside the code.
 *
 * Workspace storage, not global, for the reason `flow_view` gives: global storage
 * is one directory shared by every window, and the preview live-updates, so two
 * monorepos open side by side would show whichever plan was drawn last.
 *
 * `Beside`, because the paths in the table are links and following one is the
 * point of them: in a second column the plan — and its buttons — stay on screen
 * while you read the file it named. `preview: false` keeps the tab from being
 * the reusable italic one, which the next opened file would take over.
 */
export async function showPlan(
  context: vscode.ExtensionContext,
  plan: WritePlan,
  heading: PlanHeading,
): Promise<void> {
  // A plan still waiting for an answer is over: its document is not the one on
  // screen any more. Settled here rather than in `confirm`, so there is no moment
  // in which a plan is shown while ✓ would apply the previous one. Its own tab
  // and file go with it, which is unambiguous now that they are its own.
  pending?.settle(false);

  const dir = scratchDir(context);
  await vscode.workspace.fs.createDirectory(dir);
  const uri = vscode.Uri.joinPath(dir, scratchName(planSeq++));
  await vscode.workspace.fs.writeFile(
    uri,
    new TextEncoder().encode(buildPlanMarkdown(plan, heading)),
  );
  planUri = uri;

  await vscode.commands.executeCommand('vscode.openWith', uri, PREVIEW_EDITOR, {
    viewColumn: vscode.ViewColumn.Beside,
    preview: false,
  });
}

/**
 * Wait for the answer the plan's own tab carries.
 *
 * Three things end the wait and nothing else does: ✓ Apply, ✕ Discard, and
 * closing the tab (a No — the document says so, and it is the gesture that was
 * already documented as forgetting a plan). Moving to another tab deliberately
 * does **not**: following a path out of the table is the reading the plan is for,
 * and it would be absurd for that to cancel the thing you were reading about.
 *
 * While the answer is outstanding a status-bar chip says so, because the buttons
 * ride on a tab that can be behind another one. The chip **reveals the plan**
 * rather than applying it: there is no route to applying that does not go past
 * the plan.
 */
export function confirm(question: string, plan: WritePlan): Promise<boolean> {
  // Defensive: `showPlan` runs first on every path and has already done this.
  pending?.settle(false);

  const uri = planUri;
  // Without a document there is nothing to answer.
  if (!uri) return Promise.resolve(false);

  return new Promise<boolean>((resolve) => {
    const chip = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 99);
    chip.text = `$(edit) FRX: ${chipLabel(question)}`;
    chip.tooltip = `${plain(summarize(plan.changes))} — click to show the plan`;
    chip.command = 'frx.planShow';
    chip.show();

    const subs: vscode.Disposable[] = [chip];
    let settled = false;
    const settle = (go: boolean): void => {
      if (settled) return;
      settled = true;
      pending = null;
      // An answered plan must not go on claiming that nothing is written until
      // you answer it — so its tab goes, and so does the document behind it.
      discardDocument(uri);
      for (const d of subs) d.dispose();
      void vscode.commands.executeCommand('setContext', PLAN_TAB_ACTIVE, false);
      resolve(go);
    };

    subs.push(
      vscode.window.tabGroups.onDidChangeTabs((e) => {
        if (e.closed.some((t) => isPlanTab(t, uri))) return settle(false);
        syncContext(uri);
      }),
      vscode.window.tabGroups.onDidChangeTabGroups(() => syncContext(uri)),
    );

    pending = { uri, settle };
    syncContext(uri);
  });
}

/** ✓ Apply — carry out the pending plan. */
export function applyPending(): void {
  pending?.settle(true);
}

/** ✕ Discard — answer No; nothing is written. */
export function discardPending(): void {
  pending?.settle(false);
}

/** Reveal the pending plan's tab — what the status-bar chip does. */
export async function showPending(): Promise<void> {
  if (!pending) return;
  const tab = findPlanTab(pending.uri);
  await vscode.commands.executeCommand('vscode.openWith', pending.uri, PREVIEW_EDITOR, {
    viewColumn: tab?.group.viewColumn ?? vscode.ViewColumn.Beside,
    preview: false,
  });
}

/** Whether [tab] is the tab showing the plan document at [uri]. */
function isPlanTab(tab: vscode.Tab, uri: vscode.Uri): boolean {
  const input: unknown = tab.input;
  return (
    input instanceof vscode.TabInputCustom &&
    input.viewType === PREVIEW_EDITOR &&
    input.uri.toString() === uri.toString()
  );
}

/** The open tab showing the plan, if it is still open. */
function findPlanTab(uri: vscode.Uri): vscode.Tab | undefined {
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) if (isPlanTab(tab, uri)) return tab;
  }
  return undefined;
}

/** Raise the gate exactly while the plan's own tab is the active one. */
function syncContext(uri: vscode.Uri): void {
  const active = vscode.window.tabGroups.activeTabGroup?.activeTab;
  void vscode.commands.executeCommand(
    'setContext',
    PLAN_TAB_ACTIVE,
    !!active && isPlanTab(active, uri),
  );
}

/**
 * Retire an answered plan: close its tab, then delete its document.
 *
 * In that order, so the file never goes out from under an open editor. The delete
 * is what makes a leftover tab harmless if the close ever misses one — an empty
 * or gone document cannot pass itself off as the plan you are being asked about,
 * which is the failure this whole document-per-plan arrangement exists to rule
 * out. Both are best-effort: a plan has already been answered by this point, and
 * failing to tidy up after it is not a reason to report that it went wrong.
 */
function discardDocument(uri: vscode.Uri): void {
  const tab = findPlanTab(uri);
  const closed = tab
    ? Promise.resolve(vscode.window.tabGroups.close(tab))
    : Promise.resolve(true);
  void closed
    .catch(() => undefined)
    .then(() => Promise.resolve(vscode.workspace.fs.delete(uri)).catch(() => undefined));
}

/**
 * The chip's text: the question without its question mark, and without whatever
 * a caller added after it (`remove` explains what removal means in a second
 * sentence, which is right in a document and too long for a status bar).
 */
function chipLabel(question: string): string {
  return question.split('?')[0].trim();
}

/** The summary without its markdown emphasis, for plain-text surfaces. */
function plain(summary: string): string {
  return summary.replace(/\*\*/g, '');
}
