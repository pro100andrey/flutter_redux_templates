// Finding an already-installed `frx` binary, factored out of `resolveFrx` as a
// pure function so it is unit-testable without `vscode`, without a real
// filesystem, and without being on the platform it describes. Everything the
// search depends on arrives as `DiscoveryEnv`; this module performs no I/O.
//
// The shape is ported from this author's `lake` extension
// (`vscode/src/server/discover.ts`), which solved the same problem — a second
// invention of it would be a second thing to keep right.
import * as path from 'path';

/**
 * The ambient facts the search reads. Injected rather than taken from
 * `process`/`fs` directly, so a test can describe a Windows or macOS machine
 * without being on one.
 */
export interface DiscoveryEnv {
  platform: NodeJS.Platform;
  /** The raw `PATH` variable, unsplit. */
  pathVar?: string;
  homedir: string;
  /** `%LOCALAPPDATA%`, consulted on Windows only. */
  localAppData?: string;
  /** True when the path names an existing file. */
  isFile: (candidate: string) => boolean;
}

/**
 * Where `dart install` puts executables, per platform.
 *
 * Searched **in addition to** `PATH`, because the editor's `PATH` is not the
 * shell's. A GUI-launched editor inherits the desktop session's environment — on
 * Linux that comes from systemd, which never reads your shell rc files, so the
 * directory `dart install` told you to add is simply absent; a Dock-launched
 * VSCode on macOS has the same hole. Without this, `dart install` followed by
 * installing the extension works or not depending on whether the editor happened
 * to be started from a terminal, which is not a distinction anyone should have to
 * know about.
 */
export function dartInstallBinDirs(env: DiscoveryEnv): string[] {
  const p = pathFor(env.platform);
  switch (env.platform) {
    case 'darwin':
      return [p.join(env.homedir, 'Library', 'Application Support', 'Dart', 'install', 'bin')];
    case 'win32':
      return env.localAppData ? [p.join(env.localAppData, 'Dart', 'install', 'bin')] : [];
    default:
      return [p.join(env.homedir, '.local', 'state', 'Dart', 'install', 'bin')];
  }
}

/**
 * Where `tools/scripts/install.sh` and `install.ps1` put the released binary.
 *
 * The same reason as [dartInstallBinDirs], for the other way frx arrives. The
 * installer offers to add this to the shell profile, and a shell profile is
 * precisely what a GUI-launched editor never reads — so for the people who take
 * the one-line install, this directory *is* where frx lives and `PATH` will not
 * say so.
 *
 * Kept in step with the two scripts by hand, because there is nothing to
 * generate it from: they run on machines that have no checkout. If one moves,
 * this moves.
 */
export function installerBinDirs(env: DiscoveryEnv): string[] {
  const p = pathFor(env.platform);
  if (env.platform === 'win32') {
    return env.localAppData ? [p.join(env.localAppData, 'frx', 'bin')] : [];
  }
  return [p.join(env.homedir, '.frx', 'bin')];
}

/**
 * The path flavour matching the platform being described, rather than the one
 * this process happens to run on.
 *
 * In production the two always agree — `process.platform === 'win32'` means
 * `path` already *is* `path.win32` — so this changes nothing at runtime. It
 * exists so that `DiscoveryEnv` means what it says: a test describing a Windows
 * machine gets Windows separators and `;` as the `PATH` delimiter, instead of
 * silently mixing in the host's.
 */
function pathFor(platform: NodeJS.Platform): typeof path.posix {
  return platform === 'win32' ? path.win32 : path.posix;
}

/**
 * The absolute path of an installed `frx` (`frx.exe` on Windows), or undefined.
 *
 * `PATH` is searched first, so a deliberately arranged `PATH` still decides which
 * binary wins. The result is absolute on purpose: the caller spawns *that*, so
 * the child process's own `PATH` decides nothing — which is the whole failure
 * this replaces.
 *
 * Then the two install directories, `dart install` before the installer's. They
 * collide only on a machine that has both, and there the `dart install` one was
 * built from a checkout — somebody working on frx itself, whose next question is
 * whether the change they just made behaves. Losing that to a downloaded release
 * reproduces the exact failure the version constant's test was written for: the
 * fix is not in the tool you are running, and the tool says nothing about why.
 */
export function findInstalledFrx(env: DiscoveryEnv): string | undefined {
  const p = pathFor(env.platform);
  const name = env.platform === 'win32' ? 'frx.exe' : 'frx';
  const dirs = [
    ...(env.pathVar ?? '').split(p.delimiter).filter(Boolean),
    ...dartInstallBinDirs(env),
    ...installerBinDirs(env),
  ];

  for (const dir of dirs) {
    const candidate = p.join(dir, name);
    if (env.isFile(candidate)) return candidate;
  }

  return undefined;
}
