// Starting a process: which file `dart` is, how a batch file is launched, and
// what happens when the start itself fails. Every spawn in the extension — the
// CLI, the `dart --version` probe, `build_runner watch`/`stop`/`build`, the
// signals that stop a watch — goes through here, so each of those three rules is
// stated once.
//
// The facts the rules read (platform, PATH, `%ComSpec%`, whether a file exists)
// arrive as a `HostEnv`, so a test can describe a Windows machine from Linux —
// the same seam `discover.ts` uses for finding `frx`.
import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/** The ambient facts a spawn depends on. */
export interface HostEnv {
  platform: NodeJS.Platform;
  /** The raw `PATH` variable, unsplit. */
  pathVar?: string;
  /** `%ComSpec%` — the shell a batch file runs in on Windows. */
  comspec?: string;
  /** True when the path names an existing file. */
  isFile: (candidate: string) => boolean;
}

/** This machine, as `HostEnv` describes one. */
export function hostEnv(): HostEnv {
  return {
    platform: process.platform,
    pathVar: process.env.PATH ?? process.env.Path,
    comspec: process.env.ComSpec ?? process.env.COMSPEC,
    isFile: (candidate) => {
      try {
        return fs.statSync(candidate).isFile();
      } catch {
        return false;
      }
    },
  };
}

function pathFor(platform: NodeJS.Platform): typeof path.posix {
  return platform === 'win32' ? path.win32 : path.posix;
}

/**
 * The command that runs `dart` here, or null when there is none to run.
 *
 * **Off Windows, the bare name.** `execvp` searches `PATH` for it, and a `dart`
 * that is a symlink into a Flutter checkout is an executable like any other.
 *
 * **On Windows, a file, found here.** Node spawns with `CreateProcess`, which
 * tries `.com` and `.exe` and nothing else — and a Flutter-only install puts
 * `flutter\bin\dart.bat` on `PATH`, not an `.exe`, so bare `dart` was
 * "not found" on exactly the machines this template is for. So `dart.exe` on
 * `PATH` first (a standalone SDK); then, beside a `dart.bat`, the SDK Flutter
 * keeps under `cache\dart-sdk` — the executable that batch file ends up running,
 * started without a `cmd.exe` in between; and the batch file itself last, which
 * `spawn` below knows how to launch.
 */
export function findDart(env: HostEnv): string | null {
  if (env.platform !== 'win32') return 'dart';
  const p = pathFor(env.platform);
  const dirs = (env.pathVar ?? '').split(p.delimiter).filter(Boolean);
  for (const dir of dirs) {
    const exe = p.join(dir, 'dart.exe');
    if (env.isFile(exe)) return exe;
  }
  for (const dir of dirs) {
    for (const shim of ['dart.bat', 'dart.cmd']) {
      if (!env.isFile(p.join(dir, shim))) continue;
      const cached = p.join(dir, 'cache', 'dart-sdk', 'bin', 'dart.exe');
      return env.isFile(cached) ? cached : p.join(dir, shim);
    }
  }
  return null;
}

/** What `child_process.spawn` is actually handed. */
export interface Launch {
  command: string;
  args: string[];
  /** Set when the command line was quoted here, for `cmd.exe`, and must not be again. */
  windowsVerbatimArguments?: boolean;
}

/** Whether [cmd] is a batch file, which Windows only runs inside `cmd.exe`. */
function isBatch(cmd: string, env: HostEnv): boolean {
  return env.platform === 'win32' && /\.(bat|cmd)$/i.test(cmd);
}

/**
 * How to launch [cmd] with [args] — itself, or a batch file through `cmd.exe`.
 *
 * Node refuses to spawn a `.bat`/`.cmd` without a shell (EINVAL, since the
 * CVE-2024-27980 fix), and `shell: true` would hand every argument to `cmd.exe`
 * unquoted — a name with a space, or an `&`, in a path the user chose. So a
 * batch file is run as `cmd.exe /d /s /c "<line>"` with the line quoted here,
 * the way `cross-spawn` does it: each argument in double quotes with its
 * backslash-quote runs escaped for the C runtime, then every `cmd.exe`
 * metacharacter caret-escaped — twice for arguments, because a batch file's
 * `%*` is parsed by `cmd.exe` a second time.
 */
export function launchSpec(cmd: string, args: readonly string[], env: HostEnv): Launch {
  if (!isBatch(cmd, env)) return { command: cmd, args: [...args] };
  const line = [escapeCommand(cmd), ...args.map(escapeArgument)].join(' ');
  return {
    command: env.comspec || 'cmd.exe',
    args: ['/d', '/s', '/c', `"${line}"`],
    windowsVerbatimArguments: true,
  };
}

const META = /([()\][%!^"`<>&|;, *?])/g;

function escapeCommand(cmd: string): string {
  return cmd.replace(META, '^$1');
}

function escapeArgument(arg: string): string {
  // Backslashes before a quote, and at the end, are doubled: the C runtime
  // reads `\"` as a literal quote, so a trailing `C:\dir\` would swallow the
  // closing one.
  const quoted = arg.replace(/(\\*)"/g, '$1$1\\"').replace(/(\\*)$/, '$1$1');
  return `"${quoted}"`.replace(META, '^$1').replace(META, '^$1');
}

/**
 * `child_process.spawn`, through [launchSpec], never with a shell.
 *
 * Throws synchronously where `spawn` does (EINVAL, EMFILE); a missing or
 * unexecutable file arrives later as the child's `'error'` event, and a caller
 * that does not listen for it takes the extension host down with an uncaught
 * exception — see [spawnAndForget] for the fire-and-forget case.
 */
export function spawn(
  cmd: string,
  args: readonly string[],
  options: cp.SpawnOptions = {},
  env: HostEnv = hostEnv(),
): cp.ChildProcess {
  const launch = launchSpec(cmd, args, env);
  return cp.spawn(launch.command, launch.args, {
    ...options,
    shell: false,
    ...(launch.windowsVerbatimArguments ? { windowsVerbatimArguments: true } : {}),
  });
}

/** The `spawn` signature the injectable seams take; [spawn] is one. */
export type SpawnFn = (command: string, args: string[], options: cp.SpawnOptions) => cp.ChildProcess;

/**
 * Start a helper whose outcome nobody waits for — `pkill`, `taskkill` — and
 * make sure its failure to start stays a non-event.
 *
 * `pkill` is not installed everywhere (a minimal container, some BSDs), and a
 * spawn that cannot find its file reports it as an `'error'` event: with no
 * listener that is an uncaught exception in the extension host, raised from a
 * stop the user asked for.
 */
export function spawnAndForget(
  spawnFn: SpawnFn,
  command: string,
  args: string[],
): cp.ChildProcess | null {
  try {
    const child = spawnFn(command, args, { stdio: 'ignore' });
    child.on('error', () => {});
    return child;
  } catch {
    return null;
  }
}
