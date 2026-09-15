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
import * as path from 'path';

import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  // out/test/integration → the extension root, which holds package.json.
  const extensionDevelopmentPath = path.resolve(__dirname, '..', '..', '..');
  const extensionTestsPath = path.resolve(__dirname, 'suite', 'index');
  // The monorepo itself is the workspace: it has the marker file, so the
  // extension takes its monorepo branch and everything gated on
  // `frx.isMonorepo` is live.
  const workspace = path.resolve(extensionDevelopmentPath, '..', '..');

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
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
    ],
  });
}

main().catch((error) => {
  console.error('integration tests failed to run:', error);
  process.exit(1);
});
