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

/** How long a signalled watch is given to drain before it is killed outright. */
const DRAIN_MS = 10_000;

/**
 * How long to wait for `build_runner stop` before giving up on it.
 *
 * It needs one: `takeLock` retries in a `while (true)` with a 100 ms delay and
 * no deadline of its own, so against a wedged watch — one holding the lock and
 * no longer reading it — the call never returns.
 */
const STOP_MS = 15_000;

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
   * Stop any `build_runner watch` left over from a previous window.
   *
   * **This is the only measure that repairs an orphan that already exists**, and
   * the only one that covers the case nothing else can: `dispose()` does not run
   * when VS Code or the extension host is killed, so a crash always leaves the
   * watch behind. Everything else here reduces how often that happens.
   *
   * `build_runner stop` is parent-agnostic on purpose — it writes a `.requested`
   * file beside the build lock and whoever holds the lock picks it up through a
   * file watcher, so it never asks who started the process. That is also why it
   * is scoped to this project and cannot touch a watch belonging to another one.
   *
   * Failure is silent by design: there is usually nothing to stop, and a warning
   * on every activation would train the user to ignore the channel.
   */
  async reapStaleWatch(): Promise<void> {
    const dart = await this._resolveDart();
    if (!dart) return;
    const ch = this.channel();
    await new Promise<void>((resolve) => {
      let done = false;
      const finish = (note: string) => {
        if (done) return;
        done = true;
        ch.appendLine(note);
        resolve();
      };
      let stop: cp.ChildProcess;
      try {
        stop = this._spawn(dart, ['run', 'build_runner', 'stop', '--workspace'], {
          cwd: this._root,
          shell: false,
          stdio: 'ignore',
        });
      } catch {
        // EACCES on the resolved `dart`, ENOENT on a stale `frx.path`, EMFILE.
        // `_start` wraps its identical spawn for the same reason; letting this
        // one reject would leave the user's persisted watch-ON silently off.
        finish('[reap: could not start build_runner stop]');
        return;
      }
      const deadline = setTimeout(() => {
        try {
          stop.kill('SIGKILL');
        } catch {
          /* already gone */
        }
        finish('[reap: build_runner stop timed out — a wedged watch may remain]');
      }, STOP_MS);
      stop.on('exit', () => {
        clearTimeout(deadline);
        finish('[reap: checked for a leftover watch]');
      });
      stop.on('error', () => {
        clearTimeout(deadline);
        finish('[reap: could not run build_runner stop]');
      });
    });
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

  /**
   * Terminate the process without changing the persisted enabled state.
   *
   * **SIGINT, and not to `child.pid` alone.** Two facts, both measured:
   * `build_runner watch` installs a handler for `SIGINT` and no other signal, so
   * the SIGTERM this used to send skipped the drain entirely; and `dart run` is
   * a launcher whose *child* is the build script that carries that handler, so a
   * signal to `child.pid` is ignored by both. Signalling the process group is
   * not an option here the way it is in a terminal — an extension's child shares
   * the extension host's group, and signalling that would hit VS Code itself —
   * so the script is reached by naming it: `pkill -P <launcher>`.
   *
   * Detaching the child to give it its own group is also not an option: that
   * calls `setsid()`, and a watch in its own session is exactly the shape
   * `frx doctor` reads as an orphan, after which frx would build over a healthy
   * watch and kill it.
   */
  private _kill(): void {
    const child = this._child;
    if (!child) return;
    this._child = null;
    // A stopped watch no longer knows the build state — drop its findings
    // rather than leave them stale forever.
    this._buildDiagnostics.clear();
    // Everything that reaches *past* the launcher needs a pid. Signalling the
    // launcher itself does not, and happens either way — a spawn that failed
    // before it got a pid is still a process to ask to stop.
    const pid = child.pid;

    if (process.platform === 'win32') {
      // Node's `kill()` ignores the signal on Windows and kills one process;
      // `/T` is what takes the build script with it.
      try {
        if (pid !== undefined) this._spawn('taskkill', ['/pid', String(pid), '/T', '/F'], {});
        else child.kill();
      } catch {
        /* nothing left to kill */
      }
      return;
    }

    try {
      child.kill('SIGINT');
      if (pid !== undefined) this._spawn('pkill', ['-INT', '-P', String(pid)], {});
    } catch {
      /* already gone */
    }
    if (pid === undefined) return;
    // It has a lock to release and possibly a build to finish. Insist only
    // after giving it that time.
    const deadline = setTimeout(() => {
      try {
        // Children first: `pkill -P` finds children of a *living* process, so
        // killing the launcher first leaves the build script reparented to init
        // and holding the build lock — a fresh orphan made by the guard against
        // orphans.
        this._spawn('pkill', ['-KILL', '-P', String(pid)], {});
        process.kill(pid, 'SIGKILL');
      } catch {
        /* drained in time */
      }
    }, DRAIN_MS);
    child.once('exit', () => clearTimeout(deadline));
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
