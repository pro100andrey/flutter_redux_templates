// The `dart run build_runner watch --workspace` controller and its status-bar
// toggle. Only created when the workspace is our monorepo (see
// paths.findWorkspaceRoot). The enabled/disabled choice is persisted per-workspace
// in workspaceState, so a watch left ON auto-resumes on the next VSCode reload.
//
// While the watch is running, codegen regenerates on save, so the callers skip
// their "run build_runner now?" prompts (see scaffold.maybeRunBuildRunner).
import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

import { BuildLogParser } from './buildlog';
import * as diag from './diagnostics';

const STATE_KEY = 'frx.watchEnabled';

/**
 * The `child_process.spawn` seam.
 *
 * Injected so the state machine below can be tested without a real
 * `build_runner` — the transitions it owns (and the one it used to get wrong)
 * are decided by whether a process is alive, which is otherwise only observable
 * by starting one.
 */
export type SpawnFn = (
  command: string,
  args: string[],
  options: cp.SpawnOptions,
) => cp.ChildProcess;

export class FrxWatch {
  private _child: cp.ChildProcess | null = null;
  private _channel: vscode.OutputChannel | null = null;
  private readonly _item: vscode.StatusBarItem;
  private readonly _buildDiagnostics: vscode.DiagnosticCollection;
  private readonly _log: BuildLogParser;

  /**
   * @param root monorepo root (the dir whose pubspec declares `workspace:`)
   * @param _resolveDart resolves the `dart` command, or null
   * @param _spawn the process seam; defaults to the real one
   */
  constructor(
    private readonly _context: vscode.ExtensionContext,
    private readonly _root: string,
    private readonly _resolveDart: () => Promise<string | null>,
    private readonly _spawn: SpawnFn = cp.spawn,
  ) {
    this._item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    // Clicking opens the FRX action overlay (watch toggle, add substate, add
    // page, …); the icon still reflects the watch state at a glance.
    this._item.command = 'frx.menu';

    // Builder failures parsed out of the watch stream → Problems panel.
    this._buildDiagnostics = vscode.languages.createDiagnosticCollection('frx build');
    const packages = fs
      .readdirSync(_root)
      .filter((d) => fs.existsSync(path.join(_root, d, 'pubspec.yaml')));
    this._log = new BuildLogParser(_root, packages, (findings) => {
      diag.publishByFile(this._buildDiagnostics, findings, (f) => {
        if (!f.file) return null;
        const range = new vscode.Range(f.line - 1, f.column - 1, f.line - 1, f.column - 1);
        const d = new vscode.Diagnostic(
          range,
          `build_runner: ${f.message}`,
          f.severity === 'error'
            ? vscode.DiagnosticSeverity.Error
            : vscode.DiagnosticSeverity.Warning,
        );
        d.source = 'frx build';
        return d;
      });
    });

    _context.subscriptions.push(this._item, this._buildDiagnostics, {
      dispose: () => this._kill(),
    });
    this._render();
    this._item.show();
  }

  /** Whether the user has the watch toggled on (persisted across reloads). */
  get enabled(): boolean {
    return this._context.workspaceState.get(STATE_KEY, false);
  }

  /** Whether the watch process is actually alive right now. */
  get running(): boolean {
    return this._child != null;
  }

  /** The dedicated output channel for watch logs; created lazily. */
  channel(): vscode.OutputChannel {
    if (!this._channel) {
      this._channel = vscode.window.createOutputChannel('FRX watch');
      this._context.subscriptions.push(this._channel);
    }
    return this._channel;
  }

  /** Restart the watch if it was left enabled — called once on activation. */
  async resume(): Promise<void> {
    if (this.enabled) await this._start();
  }

  /**
   * Flip the toggle: start the watch (and persist ON) or stop it (persist OFF).
   *
   * The branch is on [running], not on [enabled] — those two disagree in exactly
   * one state, and it is the one the toggle exists to rescue. A watch that died
   * under us leaves `enabled` true with no process, and branching on `enabled`
   * there means the click that the crash notification, the status chip and the
   * overlay row all describe as "restart" persisted OFF instead, so restarting
   * took two clicks. Branching on the process makes stop mean stop and every
   * other click mean start.
   */
  async toggle(): Promise<void> {
    if (this.running) {
      await this._context.workspaceState.update(STATE_KEY, false);
      this._kill();
      this._render();
    } else {
      await this._context.workspaceState.update(STATE_KEY, true);
      await this._start();
    }
  }

  private async _start(): Promise<void> {
    if (this._child) return;
    const dart = await this._resolveDart();
    if (!dart) {
      vscode.window.showErrorMessage(
        'FRX: `dart` is not reachable, so `build_runner watch` cannot start. ' +
          'Set `frx.path` / add dart to PATH, or run the watch in a terminal.',
      );
      await this._context.workspaceState.update(STATE_KEY, false);
      this._render();
      return;
    }

    const ch = this.channel();
    ch.appendLine(`$ ${dart} run build_runner watch --workspace   (cwd: ${this._root})`);

    let child: cp.ChildProcess;
    try {
      child = this._spawn(dart, ['run', 'build_runner', 'watch', '--workspace'], {
        cwd: this._root,
        shell: false,
      });
    } catch (err) {
      ch.appendLine(String(err));
      vscode.window.showErrorMessage(`FRX: failed to start watch — ${err}`);
      return;
    }

    this._child = child;
    child.stdout?.on('data', (d) => {
      ch.append(d.toString());
      this._log.feed(d);
    });
    child.stderr?.on('data', (d) => {
      ch.append(d.toString());
      this._log.feed(d);
    });
    child.on('exit', (code) => {
      // `_kill()` nulls `_child` before terminating, so an exit we caused is
      // no longer "current" — only an unexpected crash still is.
      const unexpected = this._child === child;
      if (unexpected) {
        this._child = null;
        this._buildDiagnostics.clear(); // a dead watch can't vouch for its findings
      }
      ch.appendLine(`\n[watch exited: ${code}]`);
      if (unexpected && this.enabled) {
        vscode.window.showWarningMessage(
          'FRX: build_runner watch stopped unexpectedly — click the frx status bar to restart.',
        );
      }
      this._render();
    });
    this._render();
  }

  /** Terminate the process without changing the persisted enabled state. */
  private _kill(): void {
    const child = this._child;
    if (!child) return;
    this._child = null;
    // A stopped watch no longer knows the build state — drop its findings
    // rather than leave them stale forever.
    this._buildDiagnostics.clear();
    try {
      child.kill('SIGTERM');
    } catch {
      /* already gone */
    }
  }

  private _render(): void {
    if (this.enabled && this.running) {
      this._item.text = '$(sync~spin) frx watch';
      this._item.tooltip = 'frx: build_runner watch is running (--workspace). Click for actions.';
      this._item.backgroundColor = undefined;
    } else if (this.enabled) {
      this._item.text = '$(warning) frx watch';
      this._item.tooltip = 'frx: watch is enabled but not running. Click for actions.';
      this._item.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    } else {
      this._item.text = '$(debug-start) frx';
      this._item.tooltip = 'frx: click for actions — watch, add substate, add page.';
      this._item.backgroundColor = undefined;
    }
  }
}
