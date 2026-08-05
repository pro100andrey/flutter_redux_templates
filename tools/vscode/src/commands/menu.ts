// The FRX action overlay (status-bar click / Ctrl+Alt+F).
//
// **One inventory, two renderings.** [INVENTORY] is the list of capabilities; the
// palette renders it from `package.json` and this file renders it as a grouped
// QuickPick. Every row routes by **command id**, so the overlay cannot drift from
// the palette in behaviour either — and "which surface does this belong to" stops
// being a question by construction, rather than being answered once more per
// feature.
//
// The two surfaces had drifted apart in *both* directions, and the manifest's
// shape hid it: in this editor, *no* palette entry means "always visible", not
// "hidden". Three commands had no entry at all, the action scaffolder was
// explicitly hidden, eight capabilities had no command identity whatsoever, and
// the report-only audit was reachable only from here while the *fixing* variant
// was the one in the palette.
//
// `extension_contract_test.dart` fails if a declared command is missing from
// either index, with an allowlist carrying the reason for each deliberate
// absence.
//
// It used to have a sibling here — a "New here" menu on a right-clicked folder.
// The clicked folder was only ever used to compute the repo root, and the first
// workspace folder yields the same answer, so in a single-root workspace (which
// is how this monorepo is opened) the entries carried no information at all.
import * as vscode from 'vscode';

import type { App } from '../app';

/**
 * The families the CLI's own `--help` groups by, so a capability's home is
 * decided once — by what it does — rather than once per surface.
 */
type Family = 'Create & wire' | 'Edit existing' | 'Inspect' | 'Workflow';

/** One capability of the tooling: its command identity and how it reads. */
interface Capability {
  /** The command id — its palette identity, and how the overlay invokes it. */
  command: string;
  /** Row label, codicon included. */
  label: string;
  /** The one-line "what it does" a palette title cannot carry. */
  description: string;
  family: Family;
}

/**
 * Every capability, exactly once.
 *
 * Two commands are deliberately absent, both for the same reason: the rule's
 * subject is capabilities of the *tooling* — things that change the code or
 * reveal something about it — and a control that acts on the tooling's own UI is
 * not one. `frx.refreshTree` refreshes a view, the way a scrollbar does, and stays
 * on the tree's own title bar. `frx.menu` *is* this overlay; a row that reopened
 * it would be a mirror facing itself. Written down here and pinned by the
 * contract test, because an unstated exception is how a rule rots — and this rule
 * exists because the previous arrangement rotted exactly that way.
 */
const INVENTORY: Capability[] = [
  // --- Create & wire ------------------------------------------------------
  {
    command: 'frx.addSubstate',
    label: '$(database) Add substate…',
    description: 'Generate + wire an AsyncRedux substate',
    family: 'Create & wire',
  },
  {
    command: 'frx.addPage',
    label: '$(browser) Add page…',
    description: 'Generate a page + connector + route',
    family: 'Create & wire',
  },
  {
    command: 'frx.addTabs',
    label: '$(layout) Add tabs…',
    description: 'AutoTabsScaffold shell + tab pages',
    family: 'Create & wire',
  },
  {
    command: 'frx.addAction',
    label: '$(zap) Add action…',
    description: 'ReduxAction into a substate',
    family: 'Create & wire',
  },
  {
    command: 'frx.addNav',
    label: '$(arrow-right) Wire navigation…',
    description: 'Push from one page to another, params included',
    family: 'Create & wire',
  },
  {
    command: 'frx.addWidget',
    label: '$(symbol-misc) Add widget…',
    description: 'Widget + its previews, by archetype and folder',
    family: 'Create & wire',
  },
  {
    command: 'frx.addConnector',
    label: '$(plug) Add connector…',
    description: 'A StoreConnector in app for a dumb widget',
    family: 'Create & wire',
  },
  {
    command: 'frx.addModel',
    label: '$(symbol-structure) Add model…',
    description: 'freezed model, optionally with fromJson/toJson',
    family: 'Create & wire',
  },
  {
    command: 'frx.addEnum',
    label: '$(symbol-enum) Add enum…',
    description: 'Plain enum in models',
    family: 'Create & wire',
  },
  {
    command: 'frx.addService',
    label: '$(server-process) Add service…',
    description: 'Service + Redux dispatcher pair',
    family: 'Create & wire',
  },
  {
    command: 'frx.addRetrofit',
    label: '$(cloud) Add Retrofit client…',
    description: 'Retrofit @RestApi client',
    family: 'Create & wire',
  },
  {
    command: 'frx.addPackage',
    label: '$(package) Add package…',
    description: 'Optional workspace member',
    family: 'Create & wire',
  },
  {
    command: 'frx.addThemeExtension',
    label: '$(paintcan) Add theme extension…',
    description: 'ThemeExtension in ui',
    family: 'Create & wire',
  },
  // --- Edit existing ------------------------------------------------------
  {
    command: 'frx.addField',
    label: '$(add) Add field…',
    description: 'Add a field to a substate state (+ setter)',
    family: 'Edit existing',
  },
  {
    command: 'frx.addSelector',
    label: '$(filter) Add selector…',
    description: 'Computed getter on a substate Select…',
    family: 'Edit existing',
  },
  {
    command: 'frx.rename',
    label: '$(edit) Rename…',
    description: 'Rename a substate/page — files, classes & wiring',
    family: 'Edit existing',
  },
  {
    command: 'frx.remove',
    label: '$(trash) Remove…',
    description: 'Delete an artifact and unwire it',
    family: 'Edit existing',
  },
  // --- Inspect ------------------------------------------------------------
  {
    command: 'frx.map',
    label: '$(type-hierarchy) Map',
    description: 'The structure — substates, pages, and what connects them',
    family: 'Inspect',
  },
  {
    command: 'frx.flow',
    label: '$(git-merge) Flow…',
    description: 'Diagram a page\'s use cases (sequence)',
    family: 'Inspect',
  },
  {
    command: 'frx.routes',
    label: '$(milestone) Navigation map',
    description: 'Every screen and the hops between them',
    family: 'Inspect',
  },
  {
    command: 'frx.doctor',
    label: '$(checklist) Doctor',
    description: 'Audit wiring drift, codegen & placement — reports only',
    family: 'Inspect',
  },
  {
    command: 'frx.doctorFix',
    label: '$(tools) Doctor — fix',
    description: 'Repair the auto-fixable findings',
    family: 'Inspect',
  },
  // --- Workflow -----------------------------------------------------------
  {
    command: 'frx.toggleWatch',
    label: '$(sync) build_runner watch',
    description: 'Start or stop codegen on save',
    family: 'Workflow',
  },
  {
    command: 'frx.showWatchOutput',
    label: '$(output) Show watch output',
    description: 'The watch process\'s log',
    family: 'Workflow',
  },
];

/** The order the families appear in — the CLI's own. */
const FAMILIES: Family[] = ['Create & wire', 'Edit existing', 'Inspect', 'Workflow'];

/** A menu row that knows which command it runs. */
interface MenuRow extends vscode.QuickPickItem {
  command?: string;
}

/**
 * The FRX action overlay: the same inventory the palette carries, grouped under
 * separators so it reads as an index rather than a list.
 *
 * The watch rows keep their live state — the one thing a searchable palette
 * cannot show, and the reason the overlay is worth having beside it.
 */
export async function showMenu(app: App): Promise<void> {
  const rows: MenuRow[] = [];
  for (const family of FAMILIES) {
    const of = INVENTORY.filter((c) => c.family === family);
    if (!of.length) continue;
    rows.push({ label: family, kind: vscode.QuickPickItemKind.Separator });
    for (const c of of) {
      rows.push({
        label: watchLabel(app, c) ?? c.label,
        description: watchState(app, c.command) ?? c.description,
        command: c.command,
      });
    }
  }

  const pick = await vscode.window.showQuickPick(rows, {
    title: 'FRX',
    placeHolder: 'Choose an action',
    matchOnDescription: true,
  });
  if (!pick?.command) return;
  await vscode.commands.executeCommand(pick.command);
}

/** The watch row's icon reflects whether it is running; other rows keep theirs. */
function watchLabel(app: App, c: Capability): string | null {
  const watch = app.watch;
  if (!watch || c.command !== 'frx.toggleWatch') return null;
  const icon = watch.running ? 'check' : watch.enabled ? 'warning' : 'circle-large-outline';
  return `$(${icon}) build_runner watch`;
}

/**
 * The live description for a watch row, or null for every other row.
 *
 * Outside the monorepo there is no watch controller; the rows stay (the inventory
 * is one list) and read as their static description, and the commands themselves
 * are gated on `frx.isMonorepo` like every other.
 */
function watchState(app: App, command: string): string | null {
  const watch = app.watch;
  if (!watch) return null;
  if (command === 'frx.toggleWatch') {
    return watch.running
      ? 'running — select to stop'
      : watch.enabled
        ? 'enabled but stopped — select to restart'
        : 'off — select to start (--workspace)';
  }
  if (command === 'frx.showWatchOutput' && (watch.running || watch.enabled)) {
    return 'the running watch\'s log';
  }
  return null;
}
