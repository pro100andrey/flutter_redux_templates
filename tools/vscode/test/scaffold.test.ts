// The scaffold engine's overwrite offer.
//
// Exit 70 is every refusal the CLI makes, so the offer to overwrite has to be
// keyed on the collision guard's own sentence — anything else sent a refusal
// like "Create it with `frx add-package models`" round the "already exists.
// Overwrite?" modal and back through `--force`.
import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import scaffold = require('../src/scaffold');
import { OVERWRITE_HINT } from '../src/generated/contract';
import type { RunResult } from '../src/frx';

const inv = { cmd: 'frx', baseArgs: [], label: 'frx' };

/** Scripts the CLI's answers in order; records the argument lists it was run with. */
function scriptRuns(answers: RunResult[]): string[][] {
  const runs: string[][] = [];
  (frx as any).runWithProgress = async (_t: string, _i: unknown, args: string[]) => {
    runs.push(args);
    return answers.shift() ?? { code: 0, stdout: '', stderr: '' };
  };
  return runs;
}

/** Captures what the user was shown: modal warnings (the overwrite offer) and errors. */
function capture(answer: string | undefined) {
  const shown = { warnings: [] as string[], errors: [] as string[] };
  vscode.window.showWarningMessage = async (m: string) => (shown.warnings.push(m), answer);
  vscode.window.showErrorMessage = async (m: string) => (shown.errors.push(m), undefined);
  return shown;
}

const opts = (afterChange = () => {}) => ({
  inv,
  args: ['add-model', 'user', '--root', '/p'],
  cwd: '/p',
  afterChange,
  title: 'creating',
  overwritePrompt: '"user" already exists. Overwrite?',
});

test('a refusal that is not a collision is reported, never offered as an overwrite', async () => {
  const runs = scriptRuns([
    { code: 70, stdout: '', stderr: '✗ No models package. Create it with `frx add-package models`.\n' },
  ]);
  const shown = capture('Overwrite');

  const res = await scaffold.runScaffold(opts());

  assert.strictEqual(res, null);
  assert.deepStrictEqual(shown.warnings, [], 'no "already exists" modal for a missing package');
  assert.strictEqual(runs.length, 1, 'and no --force retry');
  assert.match(shown.errors[0] ?? '', /add-package models/, 'the real reason is what is said');
});

test('a collision offers the overwrite and retries with --force', async () => {
  const runs = scriptRuns([
    { code: 70, stdout: '', stderr: `✗ models/lib/user.dart already exists.\n${OVERWRITE_HINT}\n` },
    { code: 0, stdout: '', stderr: '' },
  ]);
  const shown = capture('Overwrite');
  let changed = 0;

  const res = await scaffold.runScaffold(opts(() => changed++));

  assert.ok(res);
  assert.strictEqual(shown.warnings.length, 1);
  assert.deepStrictEqual(runs[1], [...runs[0], '--force']);
  assert.strictEqual(changed, 1);
});

test('the substate guard says the same sentence, so it is a collision too', () => {
  assert.strictEqual(
    scaffold.isCollision({
      code: 70,
      stdout: '',
      stderr: `✗ business/lib/redux/profile already exists. ${OVERWRITE_HINT}\n`,
    }),
    true,
  );
  assert.strictEqual(scaffold.isCollision({ code: 1, stdout: '', stderr: OVERWRITE_HINT }), false);
});
