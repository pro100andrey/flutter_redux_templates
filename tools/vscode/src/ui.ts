// The extension's shared user-interaction helpers: the prompts, confirmations,
// error surfacing, and "which folder / which frx" resolution that every command
// repeats. Command code composes these instead of re-writing the same input
// boxes and error dialogs. Depends on the CLI adapter (frx); knows nothing about
// the settings or the extension's mutable state (watch, tree) — the two settings
// it used to read went with the confirmation helper and the open-after-create
// gate.
import * as vscode from 'vscode';

import { KINDS } from './generated/contract';
import * as frx from './frx';
import type { Invocation, RunResult } from './frx';
import * as naming from './naming';
import * as paths from './paths';
import * as queries from './queries';

/**
 * Where "Install frx" sends someone who has the extension and no CLI.
 *
 * The repository's install section rather than the latest release page: it
 * carries the one-line installer for all three platforms, and it keeps working
 * when the release the user would have landed on is superseded.
 */
const INSTALL_DOCS_URL =
  'https://github.com/pro100andrey/flutter_redux_templates#install-the-frx-cli';

/**
 * The kinds `frx remove --kind` accepts, in its order.
 *
 * A second statement of the CLI's list, and the only one the extension keeps —
 * `--kind` is passed as a string, so nothing else would catch a value the CLI
 * stopped accepting. `extension_contract_test.dart` compares this array against
 * the command's own `allowed`, from the side that owns it.
 *
 * The first two are *wired* artifacts, resolved from what the project declares;
 * the rest are file sets resolved from disk. Only the first two can be picked
 * from a list, because only they have a `list-*` command that enumerates them —
 * the rest are reached by name, which is why `remove` auto-detects the kind.
 */
export const ARTIFACT_KINDS = KINDS.remove;

/** Which kind of artifact a picked row refers to. */
export type ArtifactKind = (typeof ARTIFACT_KINDS)[number];

/** The two the pickers can enumerate. */
export type ListedKind = Extract<ArtifactKind, 'substate' | 'page'>;

/**
 * What `pickArtifact` resolved to; `kind` is undefined on the free-text path.
 *
 * [ListedKind], not [ArtifactKind]: this picker enumerates substates and pages,
 * so a caller that only handles those two — `rename` — stays type-checked
 * against being handed an action.
 */
export interface PickedArtifact {
  name: string;
  kind: ListedKind | undefined;
}

/**
 * A picker row. `frxKind` — not `kind` — carries the artifact kind: `kind` is a
 * reserved QuickPickItem property (that's how a separator row is marked), and
 * putting our own string there is exactly the bug the type system now rejects.
 */
interface PickRow extends vscode.QuickPickItem {
  frxKind?: ListedKind;
}

/** The folder a command was invoked on: the clicked one, else the first workspace folder. */
export function folderOf(uri: vscode.Uri | undefined): string | undefined {
  const dir = uri?.fsPath ?? vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!dir) {
    vscode.window.showErrorMessage('FRX: open a folder (or right-click a target folder) first.');
  }
  return dir;
}

/**
 * The command preamble every scaffolder repeats: resolve the target *project*,
 * then resolve frx (explaining the failure). Returns `{ inv, targetDir }` ready
 * to run, or null when there's no project or frx is unavailable (a message was
 * already shown).
 *
 * `targetDir` is the project root, not the folder the command was invoked on.
 * The CLI's `--root` only walks *up*, so the palette — which has no clicked
 * folder and falls back to the first workspace folder — handed it a directory
 * above the project in any repository where the template was unpacked into a
 * subdirectory, and every command failed with "not inside a frx project".
 */
export async function resolveTarget(
  context: vscode.ExtensionContext,
  uri: vscode.Uri | undefined,
): Promise<{ inv: Invocation; targetDir: string } | null> {
  const invokedOn = folderOf(uri);
  if (!invokedOn) return null;
  const targetDir = paths.projectRootFor(invokedOn);
  if (!targetDir) {
    // Either nothing of ours is here, or several are and picking one would mean
    // scaffolding into an app the user never named.
    const roots = paths.findProjectRoots();
    vscode.window.showErrorMessage(
      roots.length > 1
        ? `FRX: ${roots.length} frx projects are open — right-click inside the one you mean.`
        : 'FRX: no frx project here (looked for app/lib/navigation/app_router.dart).',
    );
    return null;
  }
  const inv = await resolveOrExplain(context, targetDir);
  if (!inv) return null;
  return { inv, targetDir };
}

/** Resolve frx, or show an actionable error and return null. */
export async function resolveOrExplain(
  context: vscode.ExtensionContext,
  targetDir: string,
): Promise<Invocation | null> {
  const inv = await frx.resolveFrx(context, targetDir);
  if (inv) return inv;
  // The install instruction leads with the download, not `dart install .`:
  // someone who got here from the Marketplace has the extension and no checkout,
  // and being told to run a command inside a directory they do not have is a
  // dead end. Contributors already know the other way.
  const pick = await vscode.window.showErrorMessage(
    'FRX: could not find the `frx` CLI. Install it, set `frx.path`, or open the ' +
      'monorepo so its tools/ package is reachable.',
    'Install frx',
    'Open Settings',
  );
  if (pick === 'Install frx') {
    vscode.env.openExternal(vscode.Uri.parse(INSTALL_DOCS_URL));
  } else if (pick === 'Open Settings') {
    vscode.commands.executeCommand('workbench.action.openSettings', 'frx.path');
  }
  return null;
}

/** Prompt for a name with the shared validation. Returns the trimmed name, or undefined if cancelled. */
export async function askName(title: string, placeHolder: string): Promise<string | undefined> {
  const value = await vscode.window.showInputBox({
    title: `FRX — ${title}`,
    prompt: 'Name — any casing (myProfile, my_profile, MyProfile)',
    placeHolder,
    ignoreFocusOut: true,
    validateInput: (v) => {
      const t = v.trim();
      if (!t) return 'Name is required.';
      return /^[A-Za-z][A-Za-z0-9 _-]*$/.test(t)
        ? undefined
        : 'Start with a letter; use only letters, digits, spaces, _ or -.';
    },
  });
  return value === undefined ? undefined : value.trim();
}

/**
 * Pick an EXISTING substate by name, with type-to-filter over the live list
 * (`frx list-substates`). Each row shows the AppState field + its state type;
 * `showQuickPick` filters by both as you type. Falls back to a free-text input
 * box when the list can't be built (frx unavailable / no substates) so nothing
 * is lost. Returns the chosen field (camelCase), the typed text, or undefined
 * if cancelled.
 */
export async function pickSubstate(
  inv: Invocation,
  root: string,
  title: string,
): Promise<string | undefined> {
  // Skip `wait` and other file-less pseudo-substates — they have no folder.
  const subs = (await queries.listSubstates(inv, root))?.filter((s) => s.file);
  if (subs && subs.length) {
    const pick = await vscode.window.showQuickPick(
      subs.map((s) => ({ label: s.field, description: s.type })),
      {
        title: `FRX — ${title}`,
        placeHolder: 'Type to filter substates',
        matchOnDescription: true,
        ignoreFocusOut: true,
      },
    );
    return pick === undefined ? undefined : pick.label;
  }
  return vscode.window.showInputBox({
    title: `FRX — ${title}`,
    prompt: 'Substate name (its folder under redux, any casing)',
    placeHolder: 'profile',
    ignoreFocusOut: true,
    validateInput: (v) => (v.trim() ? undefined : 'Substate is required.'),
  });
}

/**
 * Pick an EXISTING artifact — a substate OR a page — with type-to-filter over
 * the live lists (`list-substates` + `list-routes`), split into **Substates**
 * and **Pages** groups so the two kinds don't read as one flat list.
 *
 * Returns `{ name, kind }` — `kind` lets the caller pass `--kind`, so the CLI
 * never has to re-ask which one you meant. The free-text fallback (no lists
 * readable) returns `{ name, kind: undefined }`. Undefined if cancelled.
 */
export async function pickArtifact(
  inv: Invocation,
  root: string,
  title: string,
): Promise<PickedArtifact | undefined> {
  const [subs, routes] = await Promise.all([
    queries.listSubstates(inv, root),
    queries.listRoutes(inv, root),
  ]);
  const substates: PickRow[] = (subs ?? [])
    .filter((s) => s.file) // skip the file-less `wait` pseudo-substate
    .map((s) => ({ label: s.field, description: s.type, frxKind: 'substate' }));
  const pages: PickRow[] = (routes ?? [])
    .filter((r) => r.route && r.route.endsWith('Route'))
    // Strip the generated `Route` suffix — remove/rename expect the base name.
    .map((r) => ({
      label: naming.stripSuffix(r.route, 'Route'),
      description: r.path || r.route,
      frxKind: 'page',
    }));

  if (substates.length || pages.length) {
    const items: PickRow[] = [];
    if (substates.length) {
      items.push({ label: 'Substates', kind: vscode.QuickPickItemKind.Separator }, ...substates);
    }
    if (pages.length) {
      items.push({ label: 'Pages', kind: vscode.QuickPickItemKind.Separator }, ...pages);
    }
    const pick = await vscode.window.showQuickPick(items, {
      title: `FRX — ${title}`,
      placeHolder: 'Type to filter substates & pages',
      matchOnDescription: true,
      ignoreFocusOut: true,
    });
    return pick === undefined ? undefined : { name: pick.label, kind: pick.frxKind };
  }

  const typed = await vscode.window.showInputBox({
    title: `FRX — ${title}`,
    prompt: 'Substate or page name (any casing)',
    placeHolder: 'myProfile',
    ignoreFocusOut: true,
    validateInput: (v) => (v.trim() ? undefined : 'Name is required.'),
  });
  return typed === undefined ? undefined : { name: typed, kind: undefined };
}

/**
 * Pick an EXISTING page, with type-to-filter over `frx list-routes`. Rows show
 * the base name plus the route's path. Returns the base name (the casing the
 * CLI resolves), or undefined if cancelled / nothing to pick.
 */
export async function pickPage(
  inv: Invocation,
  root: string,
  title: string,
): Promise<string | undefined> {
  const routes = (await queries.listRoutes(inv, root)) ?? [];
  const items = routes
    .filter((r) => r.route && r.route.endsWith('Route'))
    .map((r) => ({
      label: naming.stripSuffix(r.route, 'Route'),
      description: r.path || r.route,
    }));
  if (!items.length) {
    vscode.window.showWarningMessage('FRX: no routes found — nothing to diagram.');
    return undefined;
  }
  const pick = await vscode.window.showQuickPick(items, {
    title: `FRX — ${title}`,
    placeHolder: 'Type to filter pages',
    matchOnDescription: true,
    ignoreFocusOut: true,
  });
  return pick === undefined ? undefined : pick.label;
}

export async function confirmOverwrite(message: string): Promise<boolean> {
  const pick = await vscode.window.showWarningMessage(message, { modal: true }, 'Overwrite');
  return pick === 'Overwrite';
}

/**
 * Pick the folder under `ui/lib/` a widget goes into — one already in use, or
 * a new one by typing its name.
 *
 * `showQuickPick` can't do this: it only ever returns one of its items, and
 * `--dir` is deliberately open (a name that doesn't exist creates the folder).
 * So this drives a `QuickPick` directly and, while the typed text matches no
 * existing folder, offers it as a row of its own.
 *
 * The kind's usual home is listed first, described as such. Falls back to a
 * plain input box when frx can't be read, so nothing is lost.
 */
export async function pickDir(
  inv: Invocation,
  root: string,
  kind: string,
): Promise<string | undefined> {
  const known = await queries.listWidgetDirs(inv, root);
  if (!known) {
    return vscode.window.showInputBox({
      title: 'FRX — widget folder',
      prompt: 'Folder under ui/lib to write into',
      placeHolder: 'inputs',
      ignoreFocusOut: true,
      validateInput: dirError,
    });
  }

  const home = known.home[kind];
  // The conventional folder first, then the rest in the CLI's order.
  const ordered = [
    ...(home && known.dirs.includes(home) ? [home] : []),
    ...known.dirs.filter((d) => d !== home),
  ];
  const rows = ordered.map((d) => ({
    label: d,
    description: d === home ? `where a ${kind} usually goes` : undefined,
  }));

  return new Promise((resolve) => {
    const qp = vscode.window.createQuickPick();
    qp.title = 'FRX — widget folder';
    qp.placeholder = 'Pick a folder, or type a new name to create one';
    qp.ignoreFocusOut = true;
    qp.items = rows;

    // While the typed text names no existing folder, it becomes its own row —
    // the only way to accept a value a QuickPick has no item for.
    qp.onDidChangeValue((value) => {
      const typed = value.trim();
      qp.items =
        typed && !ordered.includes(typed) && !dirError(typed)
          ? [{ label: typed, description: '$(add) new folder' }, ...rows]
          : rows;
    });

    let picked: string | undefined;
    qp.onDidAccept(() => {
      picked = qp.selectedItems[0]?.label ?? qp.value.trim();
      qp.hide();
    });
    qp.onDidHide(() => {
      qp.dispose();
      resolve(picked && !dirError(picked, known.dirs) ? picked : undefined);
    });
    qp.show();
  });
}

/**
 * The CLI's `--dir` rule, checked here so the picker can reject as you type.
 *
 * `existing` matters: the CLI accepts a folder that is already there *as it is
 * named* and only enforces snake_case for one it has to create. Applying the
 * new-folder rule to everything made the picker stricter than the CLI — it
 * would list a `myWidgets` returned by `list-widget-dirs` and then refuse the
 * pick, silently, by resolving undefined. add_widget_command.dart says so at
 * the point it decides: "otherwise completion and the picker would offer names
 * (`myWidgets`) that this then refuses".
 */
function dirError(value: string, existing: readonly string[] = []): string | undefined {
  const v = value.trim();
  if (!v) return 'A folder is required.';
  if (existing.includes(v)) return undefined;
  return /^[a-z][a-z0-9_]*$/.test(v)
    ? undefined
    : 'Use a single lower_snake_case folder name.';
}

/**
 * Open a file frx created.
 *
 * Unconditional: if you scaffolded it, you are about to edit it. The setting
 * that used to gate this described a fork nobody took.
 */
export async function open(file: string | null | undefined): Promise<void> {
  if (!file) return;
  try {
    const doc = await vscode.workspace.openTextDocument(file);
    await vscode.window.showTextDocument(doc, { preview: false });
  } catch {
    /* non-fatal */
  }
}

/** Report a failed run, surfacing the output channel. */
export function fail(res: RunResult): void {
  frx.output().show(true);
  const detail = (res.stderr || res.stdout || '').trim().split('\n').slice(-3).join(' ');
  vscode.window.showErrorMessage(`FRX failed (exit ${res.code}). ${detail}`.trim());
}

/**
 * Multi-select over the action mixins, resolving conflicts as you pick.
 *
 * async_redux makes some pairs a compile error — it has them collide on a
 * private member — so a combination the CLI would refuse must not survive the
 * picker. Ticking one of a conflicting pair unticks the other, and the
 * placeholder says which went and why.
 *
 * **The list itself never changes.** Removing the conflicting rows was the
 * obvious design and it does not work: assigning `items` clears the selection
 * and reports that on a later tick, so the pick that triggered the rebuild is
 * wiped a moment after you make it. Unticking instead touches only
 * `selectedItems`, whose echo can be recognised and ignored — and it reads
 * better anyway, because you see what happened rather than watching a row
 * disappear.
 *
 * The rule is not re-encoded here: `conflictsWith` arrives from the CLI with
 * the implications already folded in, so this is set membership.
 *
 * Returns the chosen names, `[]` for none, or undefined when cancelled — the
 * three outcomes a caller has to tell apart.
 */
/** Order-independent identity of a selection, for recognising an echo. */
const keyOf = (names: readonly string[]): string => [...names].sort().join(',');

export async function pickMixins(
  inv: Invocation,
  root: string,
  title: string,
): Promise<string[] | undefined> {
  const all = await queries.listMixins(inv, root);
  if (!all) {
    // Not the same as "no mixins wanted": the catalogue is compiled into the
    // CLI, so an empty read means frx could not be run or is older than this
    // extension. Returning [] quietly is how a `list-mixins` that refused
    // `--root` looked exactly like a user skipping the step.
    vscode.window.showWarningMessage(
      'FRX: could not read the action mixins — scaffolding without them. ' +
        'See the FRX output; the CLI may be older than the extension.',
    );
    return [];
  }
  if (all.length === 0) return [];

  const excludes = new Map(all.map((m) => [m.name, new Set(m.conflictsWith)]));
  const items = all.map((m) => ({
    label: m.name,
    description: m.implies ? `${m.summary} · implies ${m.implies}` : m.summary,
  }));

  return new Promise((resolve) => {
    const qp = vscode.window.createQuickPick<(typeof items)[number]>();
    qp.title = title;
    qp.canSelectMany = true;
    qp.ignoreFocusOut = true;
    qp.items = items;
    qp.placeholder = 'Behaviour mixins — press Enter to skip';

    /// The exact set last written back, so its echo is not read as a click.
    /// Cleared once seen: a set reached again by hand is a real click, and
    /// treating it as another echo silently dropped the tick.
    let echo: string | null = null;
    let chosen: string[] = [];

    qp.onDidChangeSelection((picked) => {
      const names = picked.map((p) => p.label);
      if (keyOf(names) === echo) {
        echo = null;
        return;
      }

      // Resolved over the whole selection, newest first, rather than over what
      // changed: a pair arriving in one event is both-new, so a rule phrased as
      // "the newest pick evicts what it excludes" never fires and the pair
      // survives to be refused by the CLI.
      const kept: string[] = [];
      const dropped: string[] = [];
      const blame = new Map<string, string>();
      for (const name of [...names].reverse()) {
        const clash = kept.find((k) => excludes.get(name)?.has(k));
        if (clash === undefined) {
          kept.unshift(name);
        } else {
          dropped.unshift(name);
          blame.set(name, clash);
        }
      }
      chosen = kept;

      qp.placeholder = dropped.length === 0
        ? 'Behaviour mixins — press Enter to skip'
        : dropped
            .map((d) => `Unticked ${d} — async_redux excludes it with ${blame.get(d)}`)
            .join(' · ');

      if (dropped.length === 0) return;
      echo = keyOf(chosen);
      qp.selectedItems = items.filter((i) => chosen.includes(i.label));
    });

    // Accept records the answer and hides; hiding is the one place that
    // resolves and disposes, so a dismissal cannot leak a pending promise.
    let accepted: string[] | undefined;
    qp.onDidAccept(() => {
      accepted = [...chosen];
      qp.hide();
    });
    qp.onDidHide(() => {
      qp.dispose();
      resolve(accepted);
    });
    qp.show();
  });
}
