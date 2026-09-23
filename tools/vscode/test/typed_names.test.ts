// What a typed name has to be before it is handed to the CLI.
//
// The pickers fall back to free text when the lists cannot be read, and what
// was typed went to the CLI as-is — untrimmed, and as a positional that a
// leading `-` turns into an option.
import './helpers';
import { vscode, reset } from './helpers';
import { test, beforeEach } from 'node:test';
import * as assert from 'node:assert';
import queries = require('../src/queries');
import ui = require('../src/ui');

const inv = { cmd: 'frx', baseArgs: [], label: 'frx' };

beforeEach(() => {
  reset();
  // No lists: the pickers fall back to the input box.
  (queries as any).listSubstates = async () => null;
  (queries as any).listRoutes = async () => null;
});

test('a typed substate comes back trimmed', async () => {
  vscode._input = '  profile  ';
  assert.strictEqual(await ui.pickSubstate(inv, '/p', 'Add field'), 'profile');
});

test('a typed substate that would read as an option is refused', async () => {
  vscode._input = undefined;
  await ui.pickSubstate(inv, '/p', 'Add field');
  const validate = vscode._lastInput!.opts.validateInput;
  assert.ok(validate('-b'), '`-b` is a flag, not a substate');
  assert.ok(validate('   '));
  assert.strictEqual(validate(' log_in '), undefined);
});

test('a typed artifact comes back trimmed, and a leading dash is refused', async () => {
  vscode._input = ' SetValueAction ';
  assert.deepStrictEqual(await ui.pickArtifact(inv, '/p', 'Remove'), {
    name: 'SetValueAction',
    kind: undefined,
  });
  const validate = vscode._lastInput!.opts.validateInput;
  assert.ok(validate('--force'));
  // What `remove` resolves by name is wider than a new name: a field, a private class.
  assert.strictEqual(validate('profile.email'), undefined);
  assert.strictEqual(validate('_Private'), undefined);
});

test('a new name follows the same rule', () => {
  assert.ok(ui.nameError('-x'));
  assert.ok(ui.nameError('9lives'));
  assert.strictEqual(ui.nameError(' my profile '), undefined);
});
