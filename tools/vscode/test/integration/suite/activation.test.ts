/// <reference types="mocha" />
// Runs inside a real VS Code — see ../runTests.ts.
import * as assert from 'assert';

import * as vscode from 'vscode';

const EXTENSION_ID = 'pro100dev.frx';

/** Every command the manifest contributes, read from the manifest itself. */
function contributedCommands(): string[] {
  const ext = vscode.extensions.getExtension(EXTENSION_ID);
  assert.ok(ext, `${EXTENSION_ID} is not installed in the test host`);
  const commands = (ext.packageJSON?.contributes?.commands ?? []) as { command: string }[];
  return commands.map((c) => c.command);
}

suite('FRX in a real VS Code', () => {
  test('activates in the monorepo', async () => {
    const ext = vscode.extensions.getExtension(EXTENSION_ID);
    assert.ok(ext, `${EXTENSION_ID} is not installed in the test host`);
    await ext.activate();
    assert.strictEqual(ext.isActive, true);
  });

  test('every contributed command is registered', async () => {
    // `validate-manifest` checks this against the *source*; this checks it
    // against the running host, which is the only reader that matters.
    const registered = new Set(await vscode.commands.getCommands(true));
    const missing = contributedCommands().filter((c) => !registered.has(c));
    assert.deepStrictEqual(missing, [], 'contributed but never registered');
  });

  test('frx.doctor runs to completion', async () => {
    // The audit needs an `frx` — installed, or `dart run` from tools/ — and a
    // runner may have neither. What is asserted is therefore the shape, not the
    // findings: the command returns rather than throwing, and whatever it did
    // publish under the `frx` source is a doctor finding.
    await vscode.commands.executeCommand('frx.doctor');
    for (const [, diagnostics] of vscode.languages.getDiagnostics()) {
      for (const d of diagnostics) {
        if (d.source !== 'frx') continue;
        assert.match(d.message, /^frx doctor: /);
      }
    }
  });
});
