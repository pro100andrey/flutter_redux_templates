// The "create & wire" commands: substate, page, action, field, selector, tabs,
// and the single-file scaffolders. Each takes the shared `app` context and
// composes the ui prompts + the scaffold engine. Activation just registers
// these; the FRX overlay and "New here" menu delegate to them.
import * as vscode from 'vscode';

import { KINDS, type Kind } from '../generated/contract';

import type { App } from '../app';
import * as config from '../config';
import * as frx from '../frx';
import * as paths from '../paths';
import * as queries from '../queries';
import * as scaffold from '../scaffold';
import * as ui from '../ui';

/**
 * The `--kind` pickers: values from the CLI, prose from here.
 *
 * The values were hand-copied — four sets of them, and only `remove --kind` had
 * a test, so three could drift silently and the fourth was caught by a regex
 * over this file's text. Now `KINDS` is generated from each command's own
 * ArgParser and the blurbs are a `Record` over it: add a kind in Dart, run
 * `make contract`, and this stops compiling until somebody writes what it does.
 * The order is the CLI's, so the picker lists them the way `--help` does.
 */
const SUBSTATE_BLURBS: Record<Kind<'substate'>, string> = {
  value: 'Single nullable `value` field + SetValueAction',
  search: '`query` string + `IList<int> view` + SetQueryAction',
  table: 'byId `IMap` table + view + Add… / Retrieve… actions',
};

const ACTION_BLURBS: Record<Kind<'action'>, string> = {
  sync: 'AppState? reduce()',
  async: 'Future<AppState?> reduce() async',
  waiting: 'extends Action with WaitingAction',
};

const NAV_BLURBS: Record<Kind<'nav'>, string> = {
  push: 'Keep the current screen underneath (default)',
  replace: 'Swap the current screen for the destination',
  navigate: 'Go there, reusing the route if it is already up',
};

/** A quick-pick row per value, in the CLI's own order. */
function picks<K extends string>(
  values: readonly K[],
  blurbs: Record<K, string>,
): vscode.QuickPickItem[] {
  return values.map((label) => ({ label, description: blurbs[label] }));
}


/** @param uri the right-clicked folder (undefined from the palette) */
export async function addSubstate(app: App): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;
  frx.output().appendLine(`FRX: using ${inv.label}`);

  const name = await ui.askName('Add Substate', 'myProfile');
  if (name === undefined) return;

  const kindPick = await vscode.window.showQuickPick(
    picks(KINDS.substate, SUBSTATE_BLURBS),
    { title: `FRX — Kind for "${name}"`, placeHolder: 'Substate flavour', ignoreFocusOut: true },
  );
  if (kindPick === undefined) return;

  const base = ['add-substate', name, '--kind', kindPick.label, '--root', targetDir];
  const res = await scaffold.runScaffold({
    inv,
    args: base,
    cwd: targetDir,
    afterChange: app.refresh,
    overwritePrompt: `Substate "${name}" already exists. Overwrite its files?`,
    title: `FRX: creating ${name}…`,
    overwriteTitle: `FRX: overwriting ${name}…`,
  });
  if (!res) return;

  const stateFile = queries.createdStateFile(res.stdout, targetDir);
  await ui.open(stateFile);
  await scaffold.maybeRunBuildRunner({
    inv,
    packageRoot: stateFile && paths.findPackageRoot(stateFile),
    kind: 'substate',
    name,
    watch: app.watch,
    afterChange: app.refresh,
  });
}

/** @param uri the right-clicked folder (undefined from the palette) */
export async function addPage(app: App): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;
  frx.output().appendLine(`FRX: using ${inv.label}`);

  const name = await ui.askName('Add Page', 'myProfile');
  if (name === undefined) return;

  const accessPick = await vscode.window.showQuickPick(
    [
      { label: 'Protected', description: 'Requires a session (default)' },
      { label: 'Public', description: 'Reachable while logged out — added to the auth guard' },
    ],
    { title: `FRX — Access for "${name}"`, placeHolder: 'Route access', ignoreFocusOut: true },
  );
  if (accessPick === undefined) return;

  const base = ['add-page', name, '--root', targetDir];
  if (accessPick.label === 'Public') base.push('--public');
  const res = await scaffold.runScaffold({
    inv,
    args: base,
    cwd: targetDir,
    afterChange: app.refresh,
    overwritePrompt: `Page "${name}" already exists. Overwrite its files?`,
    title: `FRX: creating page ${name}…`,
    overwriteTitle: `FRX: overwriting page ${name}…`,
  });
  if (!res) return;

  // The page (ui) is the dumb widget you flesh out first; open it.
  const pageFile = queries.createdFile(res.stdout, targetDir, '_page.dart');
  await ui.open(pageFile);

  // auto_route generates the route class in the app package; find it via the
  // connector frx just wrote.
  const connectorFile = queries.createdFile(res.stdout, targetDir, '_page_connector.dart');
  await scaffold.maybeRunBuildRunner({
    inv,
    packageRoot: connectorFile && paths.findPackageRoot(connectorFile),
    kind: 'page',
    name,
    watch: app.watch,
    afterChange: app.refresh,
  });
}

/**
 * Wire a navigation hop: page A gains a callback that pushes page B, and B's
 * route parameters come along.
 *
 * Both pages must already be registered — `add-nav` refuses an unregistered
 * destination because auto_route generates no route class to push — so both
 * sides are picked from `list-routes` rather than typed.
 */
export async function addNav(app: App): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  const from = await ui.pickPage(inv, targetDir, 'Navigate from');
  if (from === undefined) return;
  const to = await ui.pickPage(inv, targetDir, `Navigate from "${from}" to`);
  if (to === undefined) return;
  if (from === to) {
    vscode.window.showWarningMessage('FRX: a page cannot navigate to itself.');
    return;
  }

  const kindPick = await vscode.window.showQuickPick(
    picks(KINDS.nav, NAV_BLURBS),
    { title: `FRX — ${from} → ${to}`, placeHolder: 'Which GoAction', ignoreFocusOut: true },
  );
  if (kindPick === undefined) return;

  const args = ['add-nav', from, to, '--kind', kindPick.label, '--root', targetDir];
  const res = await scaffold.runScaffold({
    inv,
    args,
    cwd: targetDir,
    afterChange: app.refresh,
    // add-nav edits existing files and is idempotent — it reports "already
    // has" and stops — so there is no overwrite to prompt for.
    title: `FRX: wiring ${from} → ${to}…`,
  });
  if (!res) return;
  vscode.window.showInformationMessage(
    `FRX: ${from} → ${to} wired. Hook the callback to whatever the user taps.`,
  );
}

/**
 * Add a ReduxAction into a substate: name + substate + kind. `presetState`
 * (from a tree substate item) skips the substate prompt.
 */
export async function addAction(app: App, presetState?: string): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  const name = await ui.askName('Add Action', 'fetchProfile');
  if (name === undefined) return;

  let state = presetState;
  if (!state) {
    state = await ui.pickSubstate(inv, targetDir, 'Action — substate');
    if (state === undefined) return;
  }

  const kindPick = await vscode.window.showQuickPick(
    picks(KINDS.action, ACTION_BLURBS),
    { title: `FRX — Action kind for "${name}"`, placeHolder: 'Body shape', ignoreFocusOut: true },
  );
  if (kindPick === undefined) return;

  // Optional async_redux behaviour mixins, narrowed as you pick — the CLI
  // owns both the catalogue and the exclusion rule.
  const mixinPicks = await ui.pickMixins(inv, targetDir, `FRX — Mixins for "${name}" (optional)`);
  if (mixinPicks === undefined) return;

  const base = ['add-action', name, '--state', state.trim(), '--kind', kindPick.label, '--root', targetDir];
  for (const m of mixinPicks) base.push('--mixin', m);
  const res = await scaffold.runScaffold({
    inv,
    args: base,
    cwd: targetDir,
    afterChange: app.refresh,
    overwritePrompt: `Action "${name}" already exists. Overwrite?`,
    title: `FRX: action ${name}…`,
    overwriteTitle: `FRX: overwriting ${name}…`,
  });
  if (!res) return;

  await ui.open(queries.createdFile(res.stdout, targetDir, '_action.dart'));
  vscode.window.showInformationMessage(`FRX: created action ${name}.`);
}

/** A "scaffold a setter action too?" row. */
interface SetterPick extends vscode.QuickPickItem {
  action: boolean;
}

/**
 * Add a field to an existing substate's freezed state (+ optional setter).
 * `presetState` (from the state-file lens) skips the substate prompt.
 */
export async function addField(app: App, presetState?: string): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  let state = presetState;
  if (!state) {
    state = await ui.pickSubstate(inv, targetDir, 'Add field — substate');
    if (state === undefined) return;
  }

  const spec = await vscode.window.showInputBox({
    title: `FRX — Field for "${state}"`,
    prompt: 'name:type — e.g. email:String?, count:int, tags:IList<String>',
    placeHolder: 'email:String?',
    ignoreFocusOut: true,
    validateInput: (v) => {
      const i = v.indexOf(':');
      if (i <= 0 || i === v.trim().length - 1) return 'Use name:type.';
      return undefined;
    },
  });
  if (spec === undefined) return;

  const base = ['add-field', state.trim(), spec.trim(), '--root', targetDir];

  // A non-nullable type needs a @Default(<expr>) — a state is built with no args.
  const type = spec.slice(spec.indexOf(':') + 1).trim();
  if (!type.endsWith('?')) {
    const def = await vscode.window.showInputBox({
      title: `FRX — Default for "${type}"`,
      prompt: `A non-nullable field needs @Default(<expr>). Enter the expression (or cancel and make ${type} nullable).`,
      placeHolder: '0 / false / const []',
      ignoreFocusOut: true,
      validateInput: (v) => (v.trim() ? undefined : 'A default is required for a non-nullable type.'),
    });
    if (def === undefined) return;
    base.push('--default', def.trim());
  }

  const setter = await vscode.window.showQuickPick<SetterPick>(
    [
      { label: 'No setter', action: false },
      { label: 'Also create Set<Field>Action', action: true },
    ],
    { title: 'FRX — Setter action', placeHolder: 'Scaffold a setter action too?', ignoreFocusOut: true },
  );
  if (setter === undefined) return;
  if (setter.action) base.push('--action');

  // A new field breaks compilation until freezed regenerates, so build unless
  // the watch is doing it or the user opted out entirely.
  const shouldBuild = !app.watch?.running && config.runBuildRunner() !== 'never';
  if (shouldBuild) base.push('-b');

  const res = await frx.runWithProgress(`FRX: add field to ${state}…`, inv, base, targetDir);
  if (res.code !== 0) return ui.fail(res);
  app.refresh();
  await ui.open(queries.createdFile(res.stdout, targetDir, '_action.dart'));
  vscode.window.showInformationMessage(
    app.watch?.running
      ? `FRX: added field to "${state}". Watch will regenerate the code.`
      : `FRX: added field to "${state}".`,
  );
}

/**
 * Add a computed getter to a substate's Select<Pascal> selector.
 * `presetState` (from a lens/tree) skips the substate prompt.
 */
export async function addSelector(app: App, presetState?: string): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  let state = presetState;
  if (!state) {
    state = await ui.pickSubstate(inv, targetDir, 'Add selector — substate');
    if (state === undefined) return;
  }

  const name = await ui.askName(`Add selector to "${state}"`, 'isValid');
  if (name === undefined) return;

  const type = await vscode.window.showInputBox({
    title: `FRX — Return type for "${name}"`,
    prompt: 'Getter return type (e.g. bool, String?, IList<int>)',
    value: 'Object?',
    ignoreFocusOut: true,
  });
  if (type === undefined) return;

  const base = ['add-selector', state.trim(), name, '--root', targetDir];
  if (type.trim()) base.push('--type', type.trim());

  const res = await frx.runWithProgress(`FRX: add selector to ${state}…`, inv, base, targetDir);
  if (res.code !== 0) return ui.fail(res);
  app.refresh();
  vscode.window.showInformationMessage(`FRX: added selector "${name}" to ${state}.`);
}

/** Scaffold a tab flow: shell name + a comma-separated list of tab pages. */
export async function addTabs(app: App): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  const name = await ui.askName('Add Tabs', 'dashboard');
  if (name === undefined) return;

  const parseTabs = (v: string): string[] => v.split(',').map((t) => t.trim()).filter(Boolean);
  const tabsRaw = await vscode.window.showInputBox({
    title: 'FRX — Tabs: tab pages',
    prompt: 'Comma-separated tab names (≥2), e.g. home, profile, settings',
    placeHolder: 'home, profile',
    ignoreFocusOut: true,
    validateInput: (v) => {
      const tabs = parseTabs(v);
      if (tabs.length < 2) return 'Provide at least two tab names.';
      const bad = tabs.find((t) => !/^[A-Za-z][A-Za-z0-9 _-]*$/.test(t));
      return bad ? `Invalid tab name "${bad}".` : undefined;
    },
  });
  if (tabsRaw === undefined) return;

  const base = ['add-tabs', name, '--root', targetDir];
  for (const t of parseTabs(tabsRaw)) base.push('--tab', t);
  const res = await scaffold.runScaffold({
    inv,
    args: base,
    cwd: targetDir,
    afterChange: app.refresh,
    overwritePrompt: `Some files for "${name}" already exist. Overwrite?`,
    title: `FRX: tabs ${name}…`,
    overwriteTitle: `FRX: overwriting ${name}…`,
  });
  if (!res) return;

  // Open the first tab page to flesh out; run build_runner in the app package.
  await ui.open(queries.createdFile(res.stdout, targetDir, '_page.dart'));
  const connectorFile = queries.createdFile(res.stdout, targetDir, '_page_connector.dart');
  await scaffold.maybeRunBuildRunner({
    inv,
    packageRoot: connectorFile && paths.findPackageRoot(connectorFile),
    kind: 'tabs',
    name,
    watch: app.watch,
    afterChange: app.refresh,
  });
}

/**
 * How to run one single-file scaffolder: the CLI command plus what to ask and
 * what to follow it up with.
 *
 * A plain record, not a picker row. These used to be QuickPickItems in a
 * second-level "New…" menu, which is why seven capabilities had no command
 * identity at all — to create a widget you had to already know it hid behind a
 * submenu inside the overlay.
 */
interface ScaffoldSpec {
  cmd: string;
  /** Filename suffix of the file to open afterwards. */
  open: string;
  /** Offer a `--serializable` (fromJson/toJson) choice. */
  serializable?: boolean;
  /** Prompt for `--value` entries (enums). */
  values?: boolean;
  /** Prompt for `--kind`, then the `--dir` folder (widgets). */
  widget?: boolean;
  /** Its output needs codegen. */
  buildRunner?: boolean;
}

/**
 * A `--kind` row for `add-widget`; mirrors the CLI's `WidgetKind`.
 *
 * The archetype is `value`, not `kind`: `QuickPickItem.kind` already means
 * separator-or-item to VSCode.
 */
interface KindPick extends vscode.QuickPickItem {
  value: string;
}

/**
 * The widget archetypes. Each decides what the widget takes in, which
 * primitive it wraps, and which states its previews enumerate — so it is asked
 * before the folder, whose suggestion depends on it.
 */
const WIDGET_BLURBS: Record<Kind<'widget'>, { label: string; description: string }> = {
  view: { label: '$(symbol-structure) View', description: 'draws a render model' },
  field: { label: '$(edit) Field', description: 'takes a FieldVm; wraps InputFormField' },
  choice: { label: '$(list-selection) Choice', description: 'takes a ChoiceVm; wraps ChoiceFormField' },
  action: { label: '$(play) Action', description: 'a labelled action; wraps Button' },
  container: { label: '$(layout) Container', description: 'wraps other widgets; takes a child' },
};

const WIDGET_KINDS: KindPick[] = KINDS.widget.map((value) => ({ value, ...WIDGET_BLURBS[value] }));

/** The single-file scaffolders, each with its own command identity. */
const SIMPLE_SCAFFOLDS = {
  widget: { cmd: 'add-widget', widget: true, open: '.dart' },
  connector: { cmd: 'add-connector', open: '_connector.dart' },
  model: { cmd: 'add-model', serializable: true, buildRunner: true, open: '.dart' },
  enum: { cmd: 'add-enum', values: true, open: '.dart' },
  service: { cmd: 'add-service', open: '.dart' },
  retrofit: { cmd: 'add-retrofit', buildRunner: true, open: '.dart' },
  themeExtension: { cmd: 'add-theme-extension', buildRunner: true, open: '.dart' },
} satisfies Record<string, ScaffoldSpec>;

/** Which single-file scaffolder to run — the key of [SIMPLE_SCAFFOLDS]. */
export type SimpleScaffold = keyof typeof SIMPLE_SCAFFOLDS;

/** Runs the single-file scaffolder named by `which`. */
export function addSimple(app: App, which: SimpleScaffold): Promise<void> {
  return runSimpleScaffold(app, SIMPLE_SCAFFOLDS[which]);
}

/** A "plain or with JSON?" row. */
interface SerializablePick extends vscode.QuickPickItem {
  serializable: boolean;
}

/** One row of the `add-package` picker. */
interface PackagePick extends vscode.QuickPickItem {
  // Not `kind`: `QuickPickItem` already declares one, typed `QuickPickItemKind`.
  pkg: string;
}

/**
 * The optional workspace members, and what each is for.
 *
 * Hand-written rather than derived: `add-package` takes its kind as a
 * positional, so there is no `--kind` list on the parser for the contract
 * generator to harvest. If it ever grows one, this table should come from
 * `KINDS` like the others do.
 */
const PACKAGE_KINDS: PackagePick[] = [
  {
    pkg: 'models',
    label: '$(symbol-structure) models',
    description: 'freezed models and converters shared between packages',
  },
  {
    pkg: 'http_client',
    label: '$(cloud) http_client',
    description: 'Dio + Retrofit clients and interceptors',
  },
  {
    pkg: 'storage',
    label: '$(database) storage',
    description: 'key-value persistence behind BaseKeyValueStorage',
  },
];

/**
 * Adds an optional workspace member.
 *
 * Surfaced because `add-model` and `add-retrofit` refuse when their package is
 * absent and name this command in the message — a refusal that pointed at
 * something the editor could not run would be a dead end.
 *
 * No file to open afterwards and no build_runner: the new member is not
 * resolved until `pub get` runs, which is what the closing message says.
 */
export async function addPackage(app: App): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  const pick = await vscode.window.showQuickPick<PackagePick>(PACKAGE_KINDS, {
    title: 'FRX — add package',
    placeHolder: 'Which workspace member?',
    ignoreFocusOut: true,
  });
  if (pick === undefined) return;

  const res = await scaffold.runScaffold({
    inv,
    args: ['add-package', pick.pkg, '--root', targetDir],
    cwd: targetDir,
    afterChange: app.refresh,
    title: `FRX: add-package ${pick.pkg}…`,
  });
  if (!res) return;

  // The CLI answers "already a member" with an empty plan and exit 0, so a
  // truthy result is not the same as a package having been created. Saying
  // "added — run pub get" there sends the user to re-resolve a workspace that
  // did not change.
  //
  // Read off the plan rather than off the CLI's prose: `<pkg>/pubspec.yaml` is
  // the file that makes a directory a member, and every writing command prints
  // what it wrote in the same `create <path>` shape. A reworded sentence would
  // have turned a string match silently false.
  const created = queries.createdFile(res.stdout, targetDir, `${pick.pkg}/pubspec.yaml`);
  if (!created) {
    vscode.window.showInformationMessage(
      `FRX: ${pick.pkg} is already a workspace member — nothing to do.`,
    );
    return;
  }

  vscode.window.showInformationMessage(
    `FRX: ${pick.pkg} added — run \`flutter pub get\` before using it.`,
  );
}

/** Runs a name-only scaffolder (with an optional serialization prompt for models). */
async function runSimpleScaffold(app: App, spec: ScaffoldSpec): Promise<void> {
  const target = await ui.resolveTarget(app.context, undefined);
  if (!target) return;
  const { inv, targetDir } = target;

  const name = await ui.askName(spec.cmd, 'myThing');
  if (name === undefined) return;

  const base = [spec.cmd, name, '--root', targetDir];
  if (spec.widget) {
    const kind = await vscode.window.showQuickPick<KindPick>(WIDGET_KINDS, {
      title: `FRX — ${name}`,
      placeHolder: 'What does it take in?',
      ignoreFocusOut: true,
    });
    if (kind === undefined) return;
    // `--dir` is required and open-ended, so it gets its own picker: existing
    // folders to choose from, a typed name to create one.
    const dir = await ui.pickDir(inv, targetDir, kind.value);
    if (dir === undefined) return;
    base.push('--kind', kind.value, '--dir', dir);
  }
  if (spec.values) {
    const raw = await vscode.window.showInputBox({
      title: `FRX — ${name}: values`,
      prompt: 'Comma-separated enum values (≥1), e.g. pending, running, done',
      placeHolder: 'pending, running, done',
      ignoreFocusOut: true,
      validateInput: (v) => {
        const items = v.split(',').map((t) => t.trim()).filter(Boolean);
        if (items.length === 0) return 'At least one value is required.';
        const bad = items.find((t) => !/^[A-Za-z][A-Za-z0-9 _-]*$/.test(t));
        return bad ? `Invalid value "${bad}".` : undefined;
      },
    });
    if (raw === undefined) return;
    for (const v of raw.split(',').map((t) => t.trim()).filter(Boolean)) {
      base.push('--value', v);
    }
  }
  if (spec.serializable) {
    const pick = await vscode.window.showQuickPick<SerializablePick>(
      [
        { label: 'Plain', serializable: false },
        { label: 'With JSON (fromJson/toJson)', serializable: true },
      ],
      { title: `FRX — ${name}`, placeHolder: 'Serialization', ignoreFocusOut: true },
    );
    if (pick === undefined) return;
    if (pick.serializable) base.push('--serializable');
  }
  // afterChange re-audits: a model/retrofit/theme creates a missing-part doctor
  // finding until codegen runs.
  const res = await scaffold.runScaffold({
    inv,
    args: base,
    cwd: targetDir,
    afterChange: app.refresh,
    overwritePrompt: `"${name}" already exists. Overwrite?`,
    title: `FRX: ${spec.cmd} ${name}…`,
    overwriteTitle: `FRX: overwriting ${name}…`,
  });
  if (!res) return;

  const created = queries.createdFile(res.stdout, targetDir, spec.open);
  await ui.open(created);
  if (spec.buildRunner) {
    await scaffold.maybeRunBuildRunner({
      inv,
      packageRoot: created && paths.findPackageRoot(created),
      kind: spec.cmd,
      name,
      watch: app.watch,
      afterChange: app.refresh,
    });
  } else {
    vscode.window.showInformationMessage(`FRX: created ${name}.`);
  }
}
