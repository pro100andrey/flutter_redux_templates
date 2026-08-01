// Smoke test: every module (through the whole extension.js require graph) loads
// under the vscode stub — catches a broken require path, a missing export, or a
// circular-load break the moment it's introduced.
import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';

const MODULES = [
  'src/config', 'src/naming', 'src/paths', 'src/queries', 'src/ui', 'src/diagnostics',
  'src/scaffold', 'src/doctor', 'src/frx', 'src/buildlog', 'src/code_actions', 'src/codelens',
  'src/map', 'src/flow_view', 'src/rename_provider', 'src/tree', 'src/watch',
  'src/commands/create', 'src/commands/artifact', 'src/commands/menu', 'extension',
];

for (const m of MODULES) {
  test(`loads ${m}`, () => {
    assert.doesNotThrow(() => require(path.join(__dirname, '..', '..', 'out', m)));
  });
}
