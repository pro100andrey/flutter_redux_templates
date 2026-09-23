// Everything that is about one project — the `build_runner` watch, the tree,
// the audit, the code lenses, the F2 and quick-fix providers, the folder
// watchers and the refresh that ties them together — built for one root and
// torn down as a unit.
//
// **Why a unit.** These used to be created once, on the first folder set that
// held a project, each keeping the root it was built with. When the workspace
// folders changed, `paths.forgetWorkspaceRoot()` made the Map, the Flow view and
// the audit re-resolve, while the tree, the watch and the lenses stayed on the
// old one: the Problems panel audited one app beside a tree of another, and a
// watch kept building a project that was no longer open. So there is one answer
// to "which project" — `paths.findWorkspaceRoot()` — and one owner of what
// depends on it: when the answer changes, the session is replaced whole.
import * as vscode from 'vscode';

import { FrxCodeActionProvider } from './code_actions';
import { FrxLensProvider } from './codelens';
import { FrxDoctor } from './doctor';
import * as frx from './frx';
import { RefreshScheduler, isGenerated } from './refresh';
import { FrxRenameProvider } from './rename_provider';
import { FrxTreeProvider } from './tree';
import * as upgradeCheck from './upgrade_check';
import { FrxWatch } from './watch';

/** What a session is, as far as whoever holds it is concerned. */
export interface Session extends vscode.Disposable {
  readonly root: string;
}

/**
 * Keeps exactly one session, for the project the workspace currently has.
 *
 * Generic over the session so the replacement rule can be tested without
 * building a real one.
 */
export class SessionHost<S extends Session> implements vscode.Disposable {
  private _current: S | null = null;

  /**
   * @param _open builds the session for a root
   * @param _findRoot the one answer to "which project" — `paths.findWorkspaceRoot`
   */
  constructor(
    private readonly _open: (root: string) => S,
    private readonly _findRoot: () => string | null,
  ) {}

  /** The live session, or null when the workspace holds no project. */
  get current(): S | null {
    return this._current;
  }

  /**
   * Bring the session in line with the project the workspace has now: keep it
   * when the root is the same, and otherwise close it and open the new one (or
   * none).
   */
  sync(): S | null {
    const root = this._findRoot();
    if (this._current && this._current.root === root) return this._current;
    const old = this._current;
    this._current = null;
    old?.dispose();
    if (root) this._current = this._open(root);
    return this._current;
  }

  dispose(): void {
    this._current?.dispose();
    this._current = null;
  }
}

/** The per-project services, live for one root. */
export class ProjectSession implements Session {
  readonly watch: FrxWatch;
  readonly doctor: FrxDoctor;
  readonly tree: FrxTreeProvider;
  private readonly _refresh: RefreshScheduler;
  private readonly _disposables: vscode.Disposable[] = [];

  constructor(
    context: vscode.ExtensionContext,
    readonly root: string,
  ) {
    this.tree = new FrxTreeProvider(context, root);
    this._refresh = new RefreshScheduler(() => Promise.all([this.tree.refresh(), this.doctor.refresh()]));
    this.doctor = new FrxDoctor(context, root, () => this.refresh());
    this.watch = new FrxWatch(context, root, frx.resolveDartCmd);
    this.watch.onBuilt = () => this._refresh.soon();

    this._disposables.push(
      this._refresh,
      this.watch,
      vscode.window.createTreeView('frx.tree', { treeDataProvider: this.tree }),
      ...this.doctor.disposables,
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
      ...this._watchSources(),
    );

    // Reap before resuming, and in that order: a watch left behind by a crashed
    // window still holds the build lock, so starting a second one would have it
    // ask the first to exit — which is the shape that produces two half-working
    // watches. `dispose()` never ran for that first one, and nothing else in the
    // extension can reach it.
    const watch = this.watch;
    void watch.reapStaleWatch().catch(() => {}).then(() => watch.resume());
    // The initial audit into the Problems panel, and the tree's first read —
    // here, so the rows are there when the section is opened rather than read
    // on the click (see FrxTreeProvider.refresh).
    void this.refresh();
    // Once a day, ask the installed binary whether a newer release exists.
    // After the audit rather than before it: the audit is what the window
    // opened for, and this is news that can arrive a moment later.
    void frx
      .resolveFrx(context, root)
      .then((inv) => (inv ? upgradeCheck.maybeCheckForUpgrade(context, inv) : undefined))
      .catch(() => {});
  }

  /** Refresh the tree and the audit now — once more after, if one is running. */
  refresh(): Promise<void> {
    return this._refresh.now();
  }

  dispose(): void {
    for (const d of this._disposables.splice(0)) d.dispose();
  }

  /**
   * Auto-refresh on external edits: the tree and the doctor findings depend on
   * sources that also change outside the extension (manual edits, git
   * checkouts). Watch the high-signal directories and fold event bursts into
   * one debounced refresh.
   *
   * The patterns match **entries, not just Dart files**, and that is the point
   * rather than laziness. A substate *is* a directory, so the change that
   * resolves a finding about one is often the directory going away — and a
   * deleted folder is reported as itself, which a `.dart` glob cannot match
   * because a folder has no `.dart` suffix. Watching only files left the
   * Problems panel asserting a substate was still unwired after it had been
   * deleted in the Explorer, with nothing but the tree's ⟳ to correct it.
   *
   * `build_runner` output is the exception, dropped by name: a cycle writes
   * dozens of files and each re-read the graph and re-ran the audit. What a
   * cycle changes arrives once instead, through the watch's `onBuilt`.
   */
  private _watchSources(): vscode.Disposable[] {
    const onFsEvent = (uri: vscode.Uri) => {
      if (!isGenerated(uri.fsPath)) this._refresh.soon();
    };
    const out: vscode.Disposable[] = [];
    for (const pattern of ['business/lib/redux/**', 'app/lib/navigation/**', 'app/lib/connectors/**']) {
      const watcher = vscode.workspace.createFileSystemWatcher(
        new vscode.RelativePattern(this.root, pattern),
      );
      watcher.onDidCreate(onFsEvent);
      watcher.onDidChange(onFsEvent);
      watcher.onDidDelete(onFsEvent);
      out.push(watcher);
    }
    // And the same thing again from the other side. The globs above depend on
    // the OS watcher reporting a recursively deleted folder at all, which is the
    // case it is worst at; these fire for operations performed *through* VSCode
    // — deleting a substate folder in the Explorer, most of all — with no glob
    // to match and no watcher to miss them. Both paths are wanted: the watcher
    // sees what happens outside the editor (a git checkout), these see what
    // happens inside it.
    const inProject = (uris: readonly vscode.Uri[]): void => {
      const hit = uris.find((u) => u.fsPath.startsWith(this.root));
      if (hit) onFsEvent(hit);
    };
    out.push(
      vscode.workspace.onDidDeleteFiles((e) => inProject(e.files)),
      vscode.workspace.onDidCreateFiles((e) => inProject(e.files)),
      vscode.workspace.onDidRenameFiles((e) => inProject(e.files.map((f) => f.newUri))),
    );
    return out;
  }
}
