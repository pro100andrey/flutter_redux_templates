// Locating and running the `frx` CLI from the extension.
//
// The tricky part is PATH: a GUI-launched editor does not inherit the login
// shell's PATH — on Linux the desktop session's environment comes from systemd,
// which never reads a shell rc file, and a Dock-launched VSCode on macOS has the
// same hole — so a `frx` installed by `dart install` is often invisible to
// `child_process`. Asking the OS to find it by spawning the bare name therefore
// depends on how the editor happened to be started.
//
// So we do not ask. `discover.ts` looks for the *file*, through the PATH
// directories and the directory `dart install` writes to, and we spawn the
// absolute path it finds — the child's own PATH decides nothing. The
// `dart run` fallback stays, because it is what makes a fresh clone work with no
// install, but it re-compiles the CLI on every call (~7s against ~6ms), so
// landing on it is said out loud rather than left to be discovered.
import * as cp from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';

import * as config from './config';
import { findInstalledFrx } from './discover';

let _channel: vscode.OutputChannel | undefined;

/** The shared "FRX" output channel; created lazily. */
export function output(): vscode.OutputChannel {
  return (_channel ??= vscode.window.createOutputChannel('FRX'));
}

/** How to invoke frx: the executable plus any fixed leading arguments. */
export interface Invocation {
  cmd: string;
  baseArgs: string[];
  label: string;
}

/** The outcome of a run. A spawn failure is reported as `code: -1`. */
export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

/**
 * Resolve how to run frx, trying in order:
 *   1. the `frx.path` setting (explicit binary),
 *   2. an installed binary — searched for as a *file*, through the PATH
 *      directories and then the two directories frx is installed into (`dart
 *      install`'s, then the one-line installer's `~/.frx/bin`), and invoked by
 *      its absolute path,
 *   3. `dart run <repo>/tools/bin/frx.dart` (zero-install; works straight from
 *      a fresh clone as long as the Dart SDK is on PATH).
 *
 * @param targetDir folder the command was invoked on
 * @returns null when nothing is runnable
 */
export async function resolveFrx(
  context: vscode.ExtensionContext,
  targetDir: string | undefined,
): Promise<Invocation | null> {
  const configured = config.binPath();
  if (configured) {
    return { cmd: configured, baseArgs: [], label: configured };
  }

  const installed = installedFrx();
  if (installed) {
    // Verified even though the file is right there: the `--version` line is what
    // proves it is really frx and not an unrelated tool of the same name.
    const version = await frxVersion(installed, []);
    if (version) {
      return { cmd: installed, baseArgs: [], label: `frx ${version} (${installed})` };
    }
  }

  const frxDart = findFrxDart(context, targetDir);
  if (frxDart && (await canSpawn('dart', ['--version']))) {
    warnAboutDartRun();
    // Pass the script as an absolute path and let the run's cwd be the target
    // folder: Dart resolves the tools/ package config from the script's own
    // location, while frx sees Directory.current = targetDir (so its printed
    // relative paths are relative to targetDir, like the installed binary).
    return {
      cmd: 'dart',
      baseArgs: ['run', frxDart],
      label: `dart run ${path.relative(path.dirname(frxDart), frxDart)}`,
    };
  }

  return null;
}

/**
 * Run `<cmd> [baseArgs] --version` and return the version string if it prints
 * our `frx <version>` line and exits 0; otherwise null. This both proves the
 * binary exists and confirms it is really frx (guards against an unrelated tool
 * that happens to be named `frx` on PATH).
 */
function frxVersion(cmd: string, baseArgs: string[]): Promise<string | null> {
  return new Promise((resolve) => {
    let child: cp.ChildProcess;
    try {
      child = cp.spawn(cmd, [...baseArgs, '--version'], { shell: false });
    } catch {
      return resolve(null);
    }
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', (code) => {
      const m = out.trim().match(/^frx\s+(\S+)/);
      resolve(code === 0 && m ? m[1] : null);
    });
    setTimeout(() => {
      try {
        child.kill();
      } catch {
        /* ignore */
      }
      resolve(null);
    }, 5000);
  });
}

/** Binds the pure search in `discover.ts` to this machine. */
function installedFrx(): string | undefined {
  return findInstalledFrx({
    platform: process.platform,
    pathVar: process.env.PATH,
    homedir: os.homedir(),
    localAppData: process.env.LOCALAPPDATA,
    isFile: (candidate) => {
      try {
        return fs.statSync(candidate).isFile();
      } catch {
        return false; // Missing, or not readable — either way, not it.
      }
    },
  });
}

/** Whether the `dart run` cost has already been said this session. */
let _warnedAboutDartRun = false;

/**
 * Say what the fallback costs, once.
 *
 * Not a popup: the fallback is legitimate on a fresh clone, and interrupting
 * someone for a working setup is worse than the seconds. But it is three orders
 * of magnitude slower than the binary, and a silent choice that expensive is how
 * it went unnoticed.
 */
function warnAboutDartRun(): void {
  if (_warnedAboutDartRun) return;
  _warnedAboutDartRun = true;
  output().appendLine(
    'FRX: no installed `frx` found — falling back to `dart run`, which ' +
      're-compiles the CLI on every call (seconds, against milliseconds for the ' +
      'binary). Install the binary — on macOS/Linux `curl -fsSL ' +
      'https://raw.githubusercontent.com/pro100andrey/flutter_redux_templates/main/tools/scripts/install.sh | sh`, ' +
      'on Windows the same for install.ps1 piped to `iex`, or `dart install .` in ' +
      'tools/ from a checkout — or set `frx.path`.',
  );
}

/** `'dart'` if it can be spawned, else null (a Dock-launched VSCode may lack it). */
export async function resolveDartCmd(): Promise<string | null> {
  return (await canSpawn('dart', ['--version'])) ? 'dart' : null;
}

/** True if `cmd` can be spawned at all (i.e. it exists), regardless of exit code. */
function canSpawn(cmd: string, args: string[]): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false;
    const done = (ok: boolean) => {
      if (!settled) {
        settled = true;
        resolve(ok);
      }
    };
    let child: cp.ChildProcess;
    try {
      child = cp.spawn(cmd, args, { shell: false });
    } catch {
      return done(false);
    }
    child.on('error', () => done(false)); // ENOENT etc.
    child.on('close', () => done(true));
    setTimeout(() => {
      try {
        child.kill();
      } catch {
        /* ignore */
      }
      done(true); // it spawned; a slow probe still means "exists"
    }, 4000);
  });
}

/**
 * Find `tools/bin/frx.dart` for the `dart run` fallback. Checks the extension's
 * own parent (dev host: the extension lives at tools/vscode), then walks up from
 * the target folder and every workspace folder looking for `tools/bin/frx.dart`.
 * @returns absolute path to frx.dart, or null
 */
function findFrxDart(
  context: vscode.ExtensionContext,
  targetDir: string | undefined,
): string | null {
  const candidates = [path.join(path.dirname(context.extensionPath), 'bin', 'frx.dart')];

  const starts = [targetDir, ...(vscode.workspace.workspaceFolders ?? []).map((f) => f.uri.fsPath)].filter(
    (s): s is string => Boolean(s),
  );
  for (const start of starts) {
    let dir = start;
    while (true) {
      candidates.push(path.join(dir, 'tools', 'bin', 'frx.dart'));
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }

  return candidates.find((c) => fs.existsSync(c)) ?? null;
}

/**
 * Run `inv` with `args` in `cwd`, streaming output to the FRX channel and also
 * capturing it. Never rejects — a spawn error comes back as `{ code: -1 }`.
 */
export function run(inv: Invocation, args: string[], cwd: string): Promise<RunResult> {
  const out = output();
  const full = [...inv.baseArgs, ...args];
  out.appendLine(`$ ${inv.cmd} ${full.join(' ')}   (cwd: ${cwd})`);
  return new Promise((resolve) => {
    let child: cp.ChildProcessWithoutNullStreams;
    try {
      child = cp.spawn(inv.cmd, full, { cwd, shell: false });
    } catch (err) {
      out.appendLine(String(err));
      return resolve({ code: -1, stdout: '', stderr: String(err) });
    }
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => {
      stdout += d;
      out.append(d.toString());
    });
    child.stderr.on('data', (d) => {
      stderr += d;
      out.append(d.toString());
    });
    child.on('error', (err) => resolve({ code: -1, stdout, stderr: stderr || String(err) }));
    child.on('close', (code) => resolve({ code: code ?? -1, stdout, stderr }));
  });
}

/** Wrap `run` in a cancellable progress notification. */
export function runWithProgress(
  title: string,
  inv: Invocation,
  args: string[],
  cwd: string,
): Thenable<RunResult> {
  return vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title, cancellable: false },
    () => run(inv, args, cwd),
  );
}

/**
 * How to invoke `dart` for build_runner. The `dart run` fallback already found
 * `dart` on PATH, so reuse it; otherwise probe PATH. Returns null when `dart`
 * can't be found — the caller should say so instead of spawning a bare `dart`
 * that ENOENTs (the exact PATH assumption resolveFrx exists to avoid).
 */
export async function resolveDart(inv: Invocation): Promise<string | null> {
  if (inv.cmd === 'dart') return 'dart';
  if (await canSpawn('dart', ['--version'])) return 'dart';
  return null;
}
