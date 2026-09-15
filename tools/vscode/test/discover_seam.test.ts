import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { installerBinDirs } from '../src/discover';

/// The install directory, as the two installer scripts state it and as
/// `discover.ts` looks for it.
///
/// The scripts run on machines that have no checkout, so nothing can be
/// generated from them; the comment in discover.ts used to say the two were
/// kept in step by hand. This is the test that keeps them in step instead: it
/// reads each script's default and asks discover.ts where it would look.

const SCRIPTS = path.join(__dirname, '..', '..', '..', 'scripts');
const never = () => false;

test('install.sh installs where discover.ts looks on macOS and Linux', () => {
  const sh = fs.readFileSync(path.join(SCRIPTS, 'install.sh'), 'utf8');
  // `INSTALL_DIR="${FRX_INSTALL_DIR:-$HOME/.frx/bin}"` — the default is what
  // follows `$HOME/`.
  const m = /^INSTALL_DIR="\$\{FRX_INSTALL_DIR:-\$HOME\/([^"}]+)\}"/m.exec(sh);
  assert.ok(m, 'install.sh declares INSTALL_DIR with a $HOME-relative default');
  const under = m![1];

  for (const platform of ['linux', 'darwin'] as const) {
    assert.deepStrictEqual(
      installerBinDirs({ platform, homedir: '/home/dev', isFile: never }),
      [path.posix.join('/home/dev', under)],
      `${platform}: discover.ts looks where install.sh writes`,
    );
  }
});

test('install.ps1 installs where discover.ts looks on Windows', () => {
  const ps = fs.readFileSync(path.join(SCRIPTS, 'install.ps1'), 'utf8');
  // `if (-not $Dir) { $Dir = Join-Path $env:LOCALAPPDATA 'frx\bin' }`.
  const m = /Join-Path \$env:LOCALAPPDATA '([^']+)'/.exec(ps);
  assert.ok(m, 'install.ps1 defaults $Dir under %LOCALAPPDATA%');
  const under = m![1];

  const localAppData = 'C:\\Users\\dev\\AppData\\Local';
  assert.deepStrictEqual(
    installerBinDirs({ platform: 'win32', homedir: 'C:\\Users\\dev', localAppData, isFile: never }),
    [path.win32.join(localAppData, under)],
  );
});

test('without %LOCALAPPDATA% there is nowhere to look on Windows, and that is said as an empty list', () => {
  assert.deepStrictEqual(
    installerBinDirs({ platform: 'win32', homedir: 'C:\\Users\\dev', isFile: never }),
    [],
  );
});
