// FRX — a thin VSCode wrapper around the `frx` scaffolding CLI.
//
// This file is pure wiring: it activates the extension, keeps the project
// session (src/session.ts — the build_runner watch, the FRX tree, the doctor
// audit and the rest of what is about one project) in step with the workspace
// folders, bundles it into an `app` context, and registers every command to
// the handlers in src/commands/. All the real work lives in the layers under
// src/ (cli/queries/ui/scaffold/…) and the providers (tree, codelens, …).
//
// In our monorepo only, a status-bar toggle for `build_runner watch` (see
// watch.ts) appears; while it runs, the scaffolders skip their "run
// build_runner now?" prompts — codegen regenerates on save.
import * as vscode from 'vscode';

import type { App } from './src/app';
import * as artifact from './src/commands/artifact';
import * as create from './src/commands/create';
import * as menu from './src/commands/menu';
import { showFlow, showRoutes } from './src/flow_view';
import { showMap } from './src/map';
import * as paths from './src/paths';
import * as plan from './src/plan_view';
import { ProjectSession, SessionHost } from './src/session';
import type { FrxTreeItem } from './src/tree';

export function activate(context: vscode.ExtensionContext): void {
  // The one project session, replaced whole when the workspace's project
  // changes — see session.ts for why nothing of it may outlive its root.
  const sessions = new SessionHost(
    (root) => new ProjectSession(context, root),
    paths.findWorkspaceRoot,
  );
  context.subscriptions.push(sessions);

  // The services + refresh every command needs, bundled once. `watch`/`doctor`
  // are getters so a command always sees the live session's instances.
  const app: App = {
    context,
    get watch() {
      return sessions.current?.watch ?? null;
    },
    get doctor() {
      return sessions.current?.doctor ?? null;
    },
    refresh: () => void sessions.current?.refresh(),
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
    vscode.commands.registerCommand('frx.addPackage', () => create.addPackage(app)),
    // The project-only commands, registered once and answered by whichever
    // session is live. Registered with the session they would be registered
    // again on every change of project, which throws for an id that exists.
    // Their menu entries are gated on `frx.isMonorepo`.
    vscode.commands.registerCommand('frx.toggleWatch', () => app.watch?.toggle()),
    vscode.commands.registerCommand('frx.showWatchOutput', () => app.watch?.channel().show()),
    vscode.commands.registerCommand('frx.refreshTree', () => app.refresh()),
    vscode.commands.registerCommand('frx.addAction', (item?: FrxTreeItem) => create.addAction(app, item?.frxName)),
    vscode.commands.registerCommand('frx.addField', (item?: FrxTreeItem) => create.addField(app, item?.frxName)),
    vscode.commands.registerCommand('frx.addSelector', (item?: FrxTreeItem) => create.addSelector(app, item?.frxName)),
    vscode.commands.registerCommand('frx.addNav', () => create.addNav(app)),
  );

  const sync = (): void => {
    const live = sessions.sync();
    vscode.commands.executeCommand('setContext', 'frx.isMonorepo', live !== null);
  };
  sync();

  // The project can arrive after activation — `onStartupFinished` fires on a
  // window restored without folders, and a folder added later would otherwise
  // leave `frx.isMonorepo` false (so: no tree, no watch, no doctor, and every
  // `when: frx.isMonorepo` menu silently off) until the window was reloaded.
  // It can also change or go away, and the session follows it either way.
  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      // The cached project answer was for the old set of folders.
      paths.forgetWorkspaceRoot();
      sync();
    }),
  );
}

export function deactivate(): void {}
