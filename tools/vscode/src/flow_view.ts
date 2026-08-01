// The FRX Flow view: the app's behaviour as a mermaid diagram.
//
// Two views — a page's use cases as a `sequenceDiagram` (`frx flow <page>`) and
// the whole app's screens as a `flowchart` (`frx flow --routes`). Both come out
// of the source AST, so they always describe the code as written.
//
// Rendering is VSCode's, not ours: since 1.121 the built-in
// `mermaid-markdown-features` renders mermaid in the markdown preview, so the
// view writes a markdown document and hands it to `markdown.showPreview`. That
// is why this extension vendors nothing — pan/zoom, "copy source" and "open in
// editor" are the platform's, and mermaid is updated by VSCode rather than by
// us. The `when: activeWebviewPanelId == 'markdown.preview'` menu entries in
// package.json put the view-switching buttons in the preview's own toolbar.
import * as vscode from 'vscode';

import * as frx from './frx';
import type { Invocation } from './frx';
import * as paths from './paths';
import * as queries from './queries';
import * as ui from './ui';

/**
 * The scratch document both views render into. One fixed name, so re-running
 * replaces the document in place and the preview stays a single tab — the way
 * the singleton webview it replaced behaved.
 *
 * The markdown preview takes its tab title from the file name, and this file
 * holds either view. Naming it for one of them (`frx-flow`) put "Navigation
 * map" under a tab labelled *flow*; the document's own heading is what says
 * which view you are looking at.
 */
const SCRATCH = 'frx-diagram.md';

/**
 * Show the flow for [page]; prompts for one when omitted.
 * @param page base name, e.g. `logIn`
 */
export async function showFlow(
  context: vscode.ExtensionContext,
  page: string | undefined,
): Promise<void> {
  const ready = await _resolve(context, 'diagram a flow');
  if (!ready) return;

  const target = page ?? (await ui.pickPage(ready.inv, ready.root, 'Flow — page'));
  if (!target) return;

  const diagram = await queries.flow(ready.inv, target, ready.root);
  if (diagram === null) return _explain(`could not diagram "${target}"`);

  await _preview(context, buildMarkdown(diagram, `${target} — use cases`));
}

/** Show the app-wide navigation map: every route and the hops between them. */
export async function showRoutes(context: vscode.ExtensionContext): Promise<void> {
  const ready = await _resolve(context, 'map the navigation');
  if (!ready) return;

  const diagram = await queries.routeMap(ready.inv, ready.root);
  if (diagram === null) return _explain('could not read the navigation map');

  await _preview(context, buildMarkdown(diagram, 'Navigation map'));
}

/** The workspace root + resolved frx invocation, or null (having explained). */
async function _resolve(
  context: vscode.ExtensionContext,
  what: string,
): Promise<{ inv: Invocation; root: string } | null> {
  const root = paths.findWorkspaceRoot();
  if (!root) {
    vscode.window.showErrorMessage(`FRX: open the monorepo to ${what}.`);
    return null;
  }
  const inv = await ui.resolveOrExplain(context, root);
  return inv ? { inv, root } : null;
}

/** Surface the CLI's own message from the output channel when frx failed. */
function _explain(message: string): void {
  frx.output().show(true);
  vscode.window.showWarningMessage(`FRX: ${message} — see the FRX output.`);
}

/** Write the document to extension storage and reveal its markdown preview. */
async function _preview(context: vscode.ExtensionContext, markdown: string): Promise<void> {
  // Workspace storage, not global: global storage is one directory shared by
  // every window, so a second monorepo open beside this one would render into
  // the same file — and the preview watching it live-updates, so both windows
  // end up showing whichever diagram was drawn last.
  const dir = scratchDir(context);
  await vscode.workspace.fs.createDirectory(dir);
  const uri = vscode.Uri.joinPath(dir, SCRATCH);
  await vscode.workspace.fs.writeFile(uri, new TextEncoder().encode(markdown));

  await vscode.commands.executeCommand('markdown.showPreview', uri);
  // A preview left open from a previous run is still showing the old document:
  // the file changed underneath it, so ask for a re-render rather than trust
  // the watcher to have noticed before `showPreview` revealed the panel.
  await vscode.commands.executeCommand('markdown.preview.refresh');
}

/**
 * Where the scratch document goes: this workspace's storage, falling back to
 * the shared one when there is none (both views need an open monorepo, so the
 * fallback is a guard rather than a path anyone takes).
 */
export function scratchDir(context: vscode.ExtensionContext): vscode.Uri {
  return context.storageUri ?? context.globalStorageUri;
}

/**
 * Wrap a mermaid diagram in a markdown document the preview can render.
 *
 * The fence is sized to its content: a fenced block ends at the first fence at
 * least as long as the one that opened it, so a diagram that happens to contain
 * backticks would otherwise close its own block and spill raw mermaid into the
 * page.
 */
export function buildMarkdown(diagram: string, heading: string): string {
  const fence = '`'.repeat(Math.max(3, longestBacktickRun(diagram) + 1));
  return `# ${heading}\n\n${fence}mermaid\n${diagram}\n${fence}\n`;
}

/** The length of the longest run of backticks in [text]. */
function longestBacktickRun(text: string): number {
  let longest = 0;
  for (const run of text.match(/`+/g) ?? []) longest = Math.max(longest, run.length);
  return longest;
}
