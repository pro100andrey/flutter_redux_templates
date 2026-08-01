import { test } from 'node:test';
import * as assert from 'node:assert';
import { dartInstallBinDirs, findInstalledFrx } from '../src/discover';
import type { DiscoveryEnv } from '../src/discover';

/// Finding the installed CLI.
///
/// The defect this pins is expensive and quiet: asking the OS to find `frx` by
/// spawning the bare name depends on the editor's `PATH`, a GUI-launched editor
/// does not have the shell's, and the fallback re-compiles the CLI on every call
/// — seconds against milliseconds, on every file event.
///
/// No `vscode`, no filesystem, and no dependence on the platform this runs on:
/// the environment is injected, so a Linux CI run describes a Windows machine.

/** An environment where `files` (and nothing else) exists. */
function env(partial: Partial<DiscoveryEnv> & { files?: string[] }): DiscoveryEnv {
  const files = new Set(partial.files ?? []);
  return {
    platform: partial.platform ?? 'linux',
    pathVar: partial.pathVar,
    homedir: partial.homedir ?? '/home/dev',
    localAppData: partial.localAppData,
    isFile: partial.isFile ?? ((c) => files.has(c)),
  };
}

test('PATH is searched, and the first hit wins', () => {
  assert.strictEqual(
    findInstalledFrx(
      env({ pathVar: '/a:/b', files: ['/b/frx', '/a/frx'] }),
    ),
    '/a/frx',
    'a deliberately arranged PATH still decides which binary wins',
  );
});

test('the dart install directory is searched even when PATH lacks it', () => {
  // The whole point. A GUI-launched editor's PATH comes from the desktop
  // session, which never reads a shell rc file, so the directory `dart install`
  // told you to add is simply absent.
  assert.strictEqual(
    findInstalledFrx(
      env({
        pathVar: '/usr/bin:/bin',
        files: ['/home/dev/.local/state/Dart/install/bin/frx'],
      }),
    ),
    '/home/dev/.local/state/Dart/install/bin/frx',
  );
});

test('no PATH at all still finds the installed binary', () => {
  assert.strictEqual(
    findInstalledFrx(
      env({ files: ['/home/dev/.local/state/Dart/install/bin/frx'] }),
    ),
    '/home/dev/.local/state/Dart/install/bin/frx',
  );
});

test('PATH beats the dart install directory', () => {
  assert.strictEqual(
    findInstalledFrx(
      env({
        pathVar: '/opt/bin',
        files: ['/opt/bin/frx', '/home/dev/.local/state/Dart/install/bin/frx'],
      }),
    ),
    '/opt/bin/frx',
  );
});

test('nothing installed is undefined, not a guess', () => {
  // Undefined is what sends the caller to the `dart run` fallback; a guessed
  // path would spawn something that does not exist.
  assert.strictEqual(findInstalledFrx(env({ pathVar: '/usr/bin' })), undefined);
});

test('empty PATH entries are skipped', () => {
  // A trailing `:` yields an empty segment, and joining it would look in the cwd.
  assert.strictEqual(
    findInstalledFrx(env({ pathVar: '/usr/bin::', files: ['frx'] })),
    undefined,
  );
});

test('macOS: Application Support, described from anywhere', () => {
  const macos = env({
    platform: 'darwin',
    homedir: '/Users/dev',
    files: ['/Users/dev/Library/Application Support/Dart/install/bin/frx'],
  });
  assert.deepStrictEqual(dartInstallBinDirs(macos), [
    '/Users/dev/Library/Application Support/Dart/install/bin',
  ]);
  assert.strictEqual(
    findInstalledFrx(macos),
    '/Users/dev/Library/Application Support/Dart/install/bin/frx',
  );
});

test('Windows: LOCALAPPDATA, frx.exe, and `;` as the delimiter', () => {
  const win = env({
    platform: 'win32',
    homedir: 'C:\\Users\\dev',
    localAppData: 'C:\\Users\\dev\\AppData\\Local',
    files: ['C:\\Users\\dev\\AppData\\Local\\Dart\\install\\bin\\frx.exe'],
  });
  assert.deepStrictEqual(dartInstallBinDirs(win), [
    'C:\\Users\\dev\\AppData\\Local\\Dart\\install\\bin',
  ]);
  assert.strictEqual(
    findInstalledFrx({ ...win, pathVar: 'C:\\Windows;C:\\Windows\\System32' }),
    'C:\\Users\\dev\\AppData\\Local\\Dart\\install\\bin\\frx.exe',
  );
});

test('Windows without LOCALAPPDATA has no install directory to offer', () => {
  assert.deepStrictEqual(
    dartInstallBinDirs(env({ platform: 'win32', homedir: 'C:\\Users\\dev' })),
    [],
  );
});

test('a directory named frx is not an executable', () => {
  // `isFile`, not `exists`: `~/bin/frx/` is a folder someone keeps sources in.
  assert.strictEqual(
    findInstalledFrx({
      ...env({ pathVar: '/home/dev/bin' }),
      isFile: () => false,
    }),
    undefined,
  );
});
