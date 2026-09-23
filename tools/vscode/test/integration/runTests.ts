// Launches a real VS Code with this extension loaded and runs the suite under
// test/integration/suite/ inside it.
//
// The unit suite (`npm test`) runs under plain `node --test` against a
// hand-written `vscode` stub, which is what makes it fast and what keeps it
// from proving anything about the real host: activation, command
// registration, `when` clauses, the diagnostic collection — all of it goes
// through the stub. This is the one place those are exercised against the API
// they were written for, so a rename in `package.json` that `validate-manifest`
// cannot see, or an activation that throws on a real `ExtensionContext`, fails
// here rather than on a user's first open.
//
// `npm run test:integration`. Downloads a VS Code into `.vscode-test/` on first
// run (git- and vsce-ignored); on a headless runner it needs a display —
// `xvfb-run -a npm run test:integration`, which is what CI does.
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import { runTests } from '@vscode/test-electron';

/**
 * [pathVar] without the directories that hold a `dart` or an `frx`.
 *
 * The suite runs as a Marketplace user without either does: the extension's
 * no-CLI path — activation, the command guards — is the one only this suite
 * covers, and it went uncovered the moment CI's job installed Dart to run its
 * tasks. With Dart visible, `frx.doctor` also took the `dart run` fallback and
 * JIT-compiled the CLI inside mocha's timeout.
 */
function withoutCli(pathVar: string): string {
  const names = process.platform === 'win32' ? ['dart.exe', 'dart.bat', 'frx.exe'] : ['dart', 'frx'];
  return pathVar
    .split(path.delimiter)
    .filter((dir) => dir && !names.some((n) => fs.existsSync(path.join(dir, n))))
    .join(path.delimiter);
}

async function main(): Promise<void> {
  // out/test/integration → the extension root, which holds package.json.
  const extensionDevelopmentPath = path.resolve(__dirname, '..', '..', '..');
  const extensionTestsPath = path.resolve(__dirname, 'suite', 'index');
  // The monorepo itself is the workspace: it has the marker file, so the
  // extension takes its monorepo branch and everything gated on
  // `frx.isMonorepo` is live.
  const workspace = path.resolve(extensionDevelopmentPath, '..', '..');
  // An empty home too: an installed frx is also looked for under it
  // (~/.frx/bin, ~/.pub-cache/bin, ~/.dart/install/bin).
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'frx-integration-home-'));

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    extensionTestsEnv: {
      PATH: withoutCli(process.env.PATH ?? ''),
      HOME: home,
      USERPROFILE: home,
      LOCALAPPDATA: home,
    },
    launchArgs: [
      workspace,
      // Nothing else installed on the user's machine may take part.
      '--disable-extensions',
      // The manifest declares `untrustedWorkspaces.supported: false`, so the
      // extension does not activate in an untrusted folder; with trust off,
      // every folder is trusted.
      '--disable-workspace-trust',
      '--skip-welcome',
      '--skip-release-notes',
      // On Linux and macOS the extension host otherwise re-reads the login
      // shell's environment, and the PATH above comes back with `dart` on it.
      '--force-disable-user-env',
    ],
  });
}

main().catch((error) => {
  console.error('integration tests failed to run:', error);
  process.exit(1);
});
