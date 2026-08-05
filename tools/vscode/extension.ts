// FRX — a thin VSCode wrapper around the `frx` scaffolding CLI.
//
// This file is pure wiring: it activates the extension, owns the three
// activation-scoped services (the build_runner watch, the FRX tree, the doctor
// audit), bundles them into an `app` context, and registers every command to
// the handlers in src/commands/. All the real work lives in the layers under
// src/ (cli/queries/ui/scaffold/…) and the providers (tree, codelens, …).
//
// In our monorepo only, a status-bar toggle for `build_runner watch` (see
// watch.ts) appears; while it runs, the scaffolders skip their "run
// build_runner now?" prompts — codegen regenerates on save.
import * as vscode from 'vscode';

import type { App } from './src/app';
import { FrxCodeActionProvider } from './src/code_actions';
import { FrxLensProvider } from './src/codelens';
import * as artifact from './src/commands/artifact';
import * as create from './src/commands/create';
import * as menu from './src/commands/menu';
import { FrxDoctor } from './src/doctor';
import { showFlow, showRoutes } from './src/flow_view';
import * as frx from './src/frx';
import { showMap } from './src/map';
import * as paths from './src/paths';
import * as plan from './src/plan_view';
import { FrxRenameProvider } from './src/rename_provider';
import { FrxTreeProvider } from './src/tree';
import type { FrxTreeItem } from './src/tree';
import { FrxWatch } from './src/watch';

/** The workspace's watch controller, or null when this isn't our monorepo. */
let watch: FrxWatch | null = null;

/** The FRX tree view provider, or null until registered (monorepo only). */
let frxTree: FrxTreeProvider | null = null;

/** The doctor health service (Problems panel + status chip), monorepo only. */
let doctor: FrxDoctor | null = null;

export function activate(context: vscode.ExtensionContext): void {
  // The services + refresh every command needs, bundled once. `watch`/`doctor`
  // are getters so a command captured before the monorepo branch runs still
  // sees the live instances.
  const app: App = {
    context,
    get watch() {
      return watch;
    },
    get doctor() {
      return doctor;
    },
    refresh: afterChange,
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('frx.addSubstate', () => create.addSubstate(app)),
    vscode.commands.registerCommand('frx.addPage', () => create.addPage(app)),
    vscode.commands.registerCommand('frx.remove', (arg?: artifact.ArtifactArg) => artifact.removeArtifact(app, arg)),
    vscode.commands.registerCommand('frx.rename', (arg?: artifact.ArtifactArg) => artifact.renameArtifact(app, arg)),
    // The two answers a pending plan's own tab carries, plus the way back to it
    // from the status-bar chip. Registered unconditionally rather than in the
    // monorepo branch: `frx.planTabActive` is only ever raised while a plan is
    // waiting, so it already gates them more tightly than `frx.isMonorepo` would.
    vscode.commands.registerCommand('frx.planApply', () => plan.applyPending()),
    vscode.commands.registerCommand('frx.planDiscard', () => plan.discardPending()),
    vscode.commands.registerCommand('frx.planShow', () => plan.showPending()),
    vscode.commands.registerCommand('frx.doctor', () => app.doctor?.run()),
    vscode.commands.registerCommand('frx.doctorFix', () => app.doctor?.fix()),
    vscode.commands.registerCommand('frx.map', () => showMap(context)),
    vscode.commands.registerCommand('frx.flow', (arg?: { frxName?: string }) => showFlow(context, arg?.frxName)),
    vscode.commands.registerCommand('frx.routes', () => showRoutes(context)),
    vscode.commands.registerCommand('frx.menu', () => menu.showMenu(app)),
    vscode.commands.registerCommand('frx.addTabs', () => create.addTabs(app)),
    vscode.commands.registerCommand('frx.addWidget', () => create.addSimple(app, 'widget')),
    vscode.commands.registerCommand('frx.addConnector', () => create.addSimple(app, 'connector')),
    vscode.commands.registerCommand('frx.addModel', () => create.addSimple(app, 'model')),
    vscode.commands.registerCommand('frx.addEnum', () => create.addSimple(app, 'enum')),
    vscode.commands.registerCommand('frx.addService', () => create.addSimple(app, 'service')),
    vscode.commands.registerCommand('frx.addRetrofit', () => create.addSimple(app, 'retrofit')),
    vscode.commands.registerCommand('frx.addThemeExtension', () => create.addSimple(app, 'themeExtension')),
  );

  activateMonorepo(context, app);

  // The monorepo can arrive after activation — `onStartupFinished` fires on a
  // window restored without folders, and a folder added later would otherwise
  // leave `frx.isMonorepo` false (so: no tree, no watch, no doctor, and every
  // `when: frx.isMonorepo` menu silently off) until the window was reloaded.
  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      // The cached project answer was for the old set of folders.
      paths.forgetWorkspaceRoot();
      activateMonorepo(context, app);
    }),
  );
}

/** Whether the monorepo-only services have already been created. */
let monorepoActivated = false;

/**
 * Bring up everything that only makes sense inside our monorepo: the
 * `build_runner watch` status-bar toggle (auto-resumed when it was left
 * enabled), the tree, the doctor audit, the providers, and the
 * `frx.isMonorepo` context key the menus are gated on. Idempotent — safe to
 * call again when the workspace folders change.
 */
function activateMonorepo(context: vscode.ExtensionContext, app: App): void {
  if (monorepoActivated) return;
  const root = paths.findWorkspaceRoot();
  if (root) {
    monorepoActivated = true;
    vscode.commands.executeCommand('setContext', 'frx.isMonorepo', true);
    const theWatch = (watch = new FrxWatch(context, root, frx.resolveDartCmd));

    // The FRX tree: substates + routes, with click-to-open and item actions.
    frxTree = new FrxTreeProvider(context);
    // `frx doctor` findings as ambient squiggles + Problems entries + status chip.
    const theDoctor = (doctor = new FrxDoctor(context, afterChange));
    context.subscriptions.push(
      vscode.window.createTreeView('frx.tree', { treeDataProvider: frxTree }),
      ...theDoctor.disposables,
      vscode.languages.registerCodeLensProvider(
        { language: 'dart', scheme: 'file' },
        new FrxLensProvider(root),
      ),
      // F2 on a substate/page symbol → rename the whole artifact via frx rename.
      vscode.languages.registerRenameProvider(
        { language: 'dart', scheme: 'file' },
        new FrxRenameProvider(context),
      ),
      // Quick-fix lightbulbs on auto-fixable `frx doctor` findings — on every
      // file kind it can anchor to, not just Dart (see FrxCodeActionProvider).
      vscode.languages.registerCodeActionsProvider(
        FrxCodeActionProvider.selector,
        new FrxCodeActionProvider(),
        FrxCodeActionProvider.metadata,
      ),
      vscode.commands.registerCommand('frx.toggleWatch', () => theWatch.toggle()),
      vscode.commands.registerCommand('frx.showWatchOutput', () => theWatch.channel().show()),
      vscode.commands.registerCommand('frx.refreshTree', () => afterChange()),
      vscode.commands.registerCommand('frx.addAction', (item?: FrxTreeItem) => create.addAction(app, item?.frxName)),
      vscode.commands.registerCommand('frx.addField', (item?: FrxTreeItem) => create.addField(app, item?.frxName)),
      vscode.commands.registerCommand('frx.addSelector', (item?: FrxTreeItem) => create.addSelector(app, item?.frxName)),
      vscode.commands.registerCommand('frx.addNav', () => create.addNav(app)),
    );
    // Reap before resuming, and in that order: a watch left behind by a crashed
    // window still holds the build lock, so starting a second one would have it
    // ask the first to exit — which is the shape that produces two half-working
    // watches. `dispose()` never ran for that first one, and nothing else in the
    // extension can reach it.
    void theWatch.reapStaleWatch().catch(() => {}).then(() => theWatch.resume());
    theDoctor.refresh(); // initial audit into the Problems panel

    // Auto-refresh on external edits: the tree and the doctor findings depend
    // on sources that also change outside the extension (manual edits, git
    // checkouts, build_runner output). Watch the high-signal directories and
    // fold event bursts into one debounced refresh.
    //
    // The patterns match **entries, not just Dart files**, and that is the point
    // rather than laziness. A substate *is* a directory, so the change that
    // resolves a finding about one is often the directory going away — and a
    // deleted folder is reported as itself, which `**/*.dart` cannot match
    // because a folder has no `.dart` suffix. Watching only files left the
    // Problems panel asserting a substate was still unwired after it had been
    // deleted in the Explorer, with nothing but the tree's ⟳ to correct it.
    // Folder renames and non-Dart files had the same hole. The extra events this
    // lets through are generated-file churn, which the debounce already absorbs
    // and which `**/*.dart` was letting through anyway (`.g.dart` is a `.dart`).
    let debounce: NodeJS.Timeout | undefined;
    const onFsEvent = () => {
      clearTimeout(debounce);
      debounce = setTimeout(() => afterChange(), 800);
    };
    for (const pattern of [
      'business/lib/redux/**',
      'app/lib/navigation/**',
      'app/lib/connectors/**',
    ]) {
      const watcher = vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(root, pattern),
      );
      watcher.onDidCreate(onFsEvent);
      watcher.onDidChange(onFsEvent);
      watcher.onDidDelete(onFsEvent);
      context.subscriptions.push(watcher);
    }
    // And the same thing again from the other side. The globs above depend on the
    // OS watcher reporting a recursively deleted folder at all, which is the case
    // it is worst at; these fire for operations performed *through* VSCode —
    // deleting a substate folder in the Explorer, most of all — with no glob to
    // match and no watcher to miss them. Both paths are wanted: the watcher sees
    // what happens outside the editor (a git checkout, build_runner), these see
    // what happens inside it.
    const inWorkspace = (uris: readonly vscode.Uri[]): boolean =>
      uris.some((u) => u.fsPath.startsWith(root));
    context.subscriptions.push(
      vscode.workspace.onDidDeleteFiles((e) => inWorkspace(e.files) && onFsEvent()),
      vscode.workspace.onDidCreateFiles((e) => inWorkspace(e.files) && onFsEvent()),
      vscode.workspace.onDidRenameFiles(
        (e) => inWorkspace(e.files.map((f) => f.newUri)) && onFsEvent(),
      ),
      { dispose: () => clearTimeout(debounce) },
    );
  }
}

/** Refresh the tree and re-run doctor into the Problems panel after a change. */
function afterChange(): void {
  frxTree?.refresh();
  doctor?.refresh();
}

export function deactivate(): void {}
