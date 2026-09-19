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
    const version = await knownVersion(installed);
    if (version) {
      const inv = { cmd: installed, baseArgs: [], label: `frx ${version} (${installed})` };
      // Said, not awaited: a mismatch is worth a warning, never a wait.
      void noteCompatibility(context, version, inv);
      return inv;
    }
  }

  const frxDart = findFrxDart(context, targetDir);
  if (frxDart && (await dartSpawns())) {
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

/** How the CLI's version stands to the extension's, by major.minor. */
export type Compatibility = 'same' | 'cli-older' | 'cli-newer';

/**
 * Whether a CLI at [cliVersion] and an extension at [extVersion] are the pair
 * that shipped together.
 *
 * Major.minor only. The two are released on one tag, so they agree exactly
 * when installed together; what this catches is the other case — a Marketplace
 * update landing on a machine whose binary was never re-installed, or the
 * reverse — and there the patch digit is noise: the editor reads the CLI's
 * contract out of generated constants, and that contract moves with the minor.
 * A version neither side can parse is `same`, because a mismatch that cannot be
 * shown should not be claimed.
 */
export function compatibility(cliVersion: string, extVersion: string): Compatibility {
  const cli = majorMinor(cliVersion);
  const ext = majorMinor(extVersion);
  if (!cli || !ext) return 'same';
  if (cli[0] === ext[0] && cli[1] === ext[1]) return 'same';
  return cli[0] < ext[0] || (cli[0] === ext[0] && cli[1] < ext[1]) ? 'cli-older' : 'cli-newer';
}

function majorMinor(version: string): [number, number] | null {
  const m = /^v?(\d+)\.(\d+)/.exec(version.trim());
  return m ? [Number(m[1]), Number(m[2])] : null;
}

/** Whether the pair has been compared this session. */
let _compatNoted = false;

/**
 * Warn, once per session, when the resolved CLI and this extension are not the
 * pair that shipped together.
 *
 * The failure it names is quiet: an extension a minor ahead offers a `--kind`
 * the binary rejects, and the user sees "FRX failed (exit 64)" with no hint
 * that the two halves have parted. A CLI that is behind can be brought up from
 * here, since `frx upgrade` is the CLI's own; an extension that is behind is
 * the Marketplace's to update, so that direction only says so.
 */
async function noteCompatibility(
  context: vscode.ExtensionContext,
  cliVersion: string,
  inv: Invocation,
): Promise<void> {
  if (_compatNoted) return;
  _compatNoted = true;
  const ext = extensionVersion(context);
  if (!ext) return;
  const how = compatibility(cliVersion, ext);
  if (how === 'same') return;
  if (how === 'cli-older') {
    const pick = await vscode.window.showWarningMessage(
      `FRX: the frx CLI is ${cliVersion} and this extension is ${ext}. They ship ` +
        'together; the editor may offer options this binary does not have.',
      'Upgrade frx',
    );
    if (pick === 'Upgrade frx') {
      await upgradeFrx(inv);
      // The binary changed under us: compare again on the next resolve rather
      // than staying quiet about a pair that may still not match.
      _compatNoted = false;
    }
    return;
  }
  vscode.window.showWarningMessage(
    `FRX: the frx CLI is ${cliVersion}, newer than this extension (${ext}). ` +
      'Update the FRX extension from the Marketplace to match it.',
  );
}

/**
 * This extension's own version, as the manifest states it.
 *
 * Read off the running extension first, and off the manifest beside it
 * otherwise — never a constant in source, which would be a fourth statement of
 * a fact three files already have to agree on.
 */
export function extensionVersion(context: vscode.ExtensionContext): string | null {
  const own = context.extension?.packageJSON?.version;
  if (typeof own === 'string') return own;
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(context.extensionPath, 'package.json'), 'utf8'));
    return typeof manifest?.version === 'string' ? manifest.version : null;
  } catch {
    return null;
  }
}

/**
 * Run `frx upgrade` on the resolved binary, with progress, and say how it went.
 *
 * `resolveFrx` re-resolves on every command, and what it remembers of the
 * binary is keyed on the file itself (see `knownVersion`) — so the replaced
 * binary is what the next command spawns, with nothing here to invalidate.
 */
export async function upgradeFrx(inv: Invocation): Promise<RunResult> {
  const res = await runWithProgress('FRX: frx upgrade…', inv, ['upgrade'], os.homedir());
  const last = (res.stdout.trim().split('\n').pop() ?? '').trim();
  if (res.code === 0) {
    vscode.window.showInformationMessage(`FRX: ${last || 'frx upgraded.'}`);
  } else {
    output().show(true);
    vscode.window.showErrorMessage(`FRX: frx upgrade failed (exit ${res.code}) — see the FRX output.`);
  }
  return res;
}

/** The last binary asked for `--version`, what the file was then, and the answer. */
let _known: { path: string; mtimeMs: number; size: number; version: Promise<string | null> } | null =
  null;

/**
 * The installed binary's version — from `--version` the first time, and from
 * memory while the file on disk is the same one.
 *
 * Every command resolves frx afresh, and the tree and the audit resolve it
 * separately on every refresh, so this spawn ran twice per change for an
 * answer that only changes when the binary does. The binary is what the answer
 * is keyed on: its path, size and modification time, read with one `stat`. A
 * replaced binary — `frx upgrade`, a reinstall — misses on all of them and is
 * asked again, so nothing here needs invalidating by hand.
 *
 * What is kept is the probe, not its answer: the tree, the audit and the
 * upgrade check all resolve at activation in the same tick, and remembering
 * only a settled answer let all three spawn before the first had one. A probe
 * that comes back empty is forgotten — unless a newer one has already taken
 * its place, which a late failure must not evict.
 */
function knownVersion(cmd: string): Promise<string | null> {
  let mtimeMs: number;
  let size: number;
  try {
    ({ mtimeMs, size } = fs.statSync(cmd));
  } catch {
    return frxVersion(cmd, []); // let the spawn say what is wrong with it
  }
  if (_known && _known.path === cmd && _known.mtimeMs === mtimeMs && _known.size === size) {
    return _known.version;
  }
  const entry = { path: cmd, mtimeMs, size, version: frxVersion(cmd, []) };
  _known = entry;
  return entry.version.then((version) => {
    if (!version && _known === entry) _known = null;
    return version;
  });
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
  return (await dartSpawns()) ? 'dart' : null;
}

/** The probe that said `dart` spawns, once it has. */
let _dart: Promise<boolean> | null = null;

/**
 * Whether `dart` can be spawned — asked once per session, once the answer is
 * yes. A yes stays true (the SDK does not vanish under a window), and every
 * resolve on the zero-install path asked again: three at activation in one
 * tick, two per change after. A no is not kept: the user may be installing
 * it right now, and the next command should find it.
 */
function dartSpawns(): Promise<boolean> {
  if (_dart) return _dart;
  const probe = canSpawn('dart', ['--version']);
  _dart = probe;
  return probe.then((ok) => {
    if (!ok && _dart === probe) _dart = null;
    return ok;
  });
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

/** How a run's stdout reaches the FRX channel. */
export interface RunOptions {
  /**
   * Log the size of stdout rather than stdout itself.
   *
   * For a read whose stdout is for a parser: the graph behind the tree is a
   * hundred kilobytes of JSON, read on every change, and the channel is where
   * a person looks to see what frx said — not to scroll past the picture's
   * serialised form to find it. Asked for by the caller, never inferred from
   * the arguments: a writing command also takes `--json`, and its stdout
   * carries build_runner's own output — the one place a failed build is
   * explained, and where "Show output" sends the user. Stderr is always shown
   * whole.
   */
  quiet?: boolean;
}

/**
 * Run `inv` with `args` in `cwd`, streaming output to the FRX channel and also
 * capturing it. Never rejects — a spawn error comes back as `{ code: -1 }`.
 */
export function run(
  inv: Invocation,
  args: string[],
  cwd: string,
  { quiet = false }: RunOptions = {},
): Promise<RunResult> {
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
    // Decoded once, by the stream: a Buffer chunk was decoded to append to
    // `stdout` and decoded again to append to the channel.
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d: string) => {
      stdout += d;
      if (!quiet) out.append(d);
    });
    child.stderr.on('data', (d: string) => {
      stderr += d;
      out.append(d);
    });
    child.on('error', (err) => resolve({ code: -1, stdout, stderr: stderr || String(err) }));
    child.on('close', (code) => {
      if (quiet) out.appendLine(`→ exit ${code ?? -1}, ${stdout.length} chars of stdout`);
      resolve({ code: code ?? -1, stdout, stderr });
    });
  });
}

/** Wrap `run` in a cancellable progress notification. */
export function runWithProgress(
  title: string,
  inv: Invocation,
  args: string[],
  cwd: string,
  options: RunOptions = {},
): Thenable<RunResult> {
  return vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title, cancellable: false },
    () => run(inv, args, cwd, options),
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
  if (await dartSpawns()) return 'dart';
  return null;
}
