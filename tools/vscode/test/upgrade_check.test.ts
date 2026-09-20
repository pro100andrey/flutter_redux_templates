import './helpers';
import { vscode, reset } from './helpers';
import { test, beforeEach } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import check = require('../src/upgrade_check');

/// Asking the installed binary, once a day, whether a newer release exists.

beforeEach(reset);

test('never checked is due; checked within the interval is not; a full interval later is', () => {
  const DAY = check.CHECK_INTERVAL_MS;
  assert.strictEqual(check.isDue(undefined, 1000), true);
  assert.strictEqual(check.isDue(1000, 1000 + DAY - 1), false);
  assert.strictEqual(check.isDue(1000, 1000 + DAY), true);
});

test('a last check in the future is not a reason to wait', () => {
  // A clock set back. Measured from a time that has not happened yet, the
  // interval could take days to elapse.
  assert.strictEqual(check.isDue(5_000_000, 1000), true);
});

test('what the CLI prints parses, and what is not a check does not', () => {
  assert.deepStrictEqual(check.parseCheck('{"status":"available","from":"0.3.4","to":"0.3.5"}'), {
    status: 'available',
    from: '0.3.4',
    to: '0.3.5',
  });
  assert.strictEqual(check.parseCheck('✗ could not reach GitHub'), null);
  assert.strictEqual(check.parseCheck('{"from":"0.3.4"}'), null, 'no status is no check');
});

/** A context with a recording globalState. */
function context(state: Record<string, unknown> = {}) {
  return {
    state,
    globalState: {
      get: (k: string) => state[k],
      update: async (k: string, v: unknown) => {
        state[k] = v;
      },
    },
  };
}

/** Script `frx.run` and record every invocation. */
function stubRun(result: { code: number; stdout: string; stderr: string }) {
  const calls: string[][] = [];
  (frx as any).run = async (_inv: unknown, args: string[]) => {
    calls.push(args);
    return result;
  };
  return calls;
}

const installed = { cmd: '/home/dev/.frx/bin/frx', baseArgs: [], label: 'frx' };

test('the dart run fallback is never asked — there is nothing installed to upgrade', async () => {
  const calls = stubRun({ code: 1, stdout: '{"status":"available"}', stderr: '' });
  const ctx = context();
  await check.maybeCheckForUpgrade(ctx as any, { cmd: 'dart', baseArgs: ['run', 'x'], label: 'dart' }, 10);
  assert.deepStrictEqual(calls, []);
  assert.strictEqual(ctx.state[check.LAST_CHECK_KEY], undefined, 'and no check is recorded');
});

test('a check within the interval is not repeated', async () => {
  const calls = stubRun({ code: 0, stdout: '{"status":"current"}', stderr: '' });
  const ctx = context({ [check.LAST_CHECK_KEY]: 1000 });
  await check.maybeCheckForUpgrade(ctx as any, installed, 2000);
  assert.deepStrictEqual(calls, []);
});

test('a due check asks with --check --json and records the time before asking', async () => {
  const calls = stubRun({ code: 0, stdout: '{"status":"current","from":"0.3.5","to":"0.3.5"}', stderr: '' });
  const ctx = context();
  await check.maybeCheckForUpgrade(ctx as any, installed, 777);
  assert.deepStrictEqual(calls, [['upgrade', '--check', '--json']]);
  assert.strictEqual(ctx.state[check.LAST_CHECK_KEY], 777);
});

test('an available release is offered, and "Upgrade" runs the upgrade', async () => {
  const calls = stubRun({ code: 1, stdout: '{"status":"available","from":"0.3.4","to":"0.3.5"}', stderr: '' });
  let shown = '';
  let offered: string[] = [];
  const original = vscode.window.showInformationMessage;
  vscode.window.showInformationMessage = async (message: string, ...items: string[]) => {
    shown = message;
    offered = items;
    return 'Upgrade';
  };
  const upgraded: unknown[] = [];
  const originalUpgrade = (frx as any).upgradeFrx;
  (frx as any).upgradeFrx = async (inv: unknown) => {
    upgraded.push(inv);
    return { code: 0, stdout: '', stderr: '' };
  };
  try {
    await check.maybeCheckForUpgrade(context() as any, installed, 1);
  } finally {
    vscode.window.showInformationMessage = original;
    (frx as any).upgradeFrx = originalUpgrade;
  }
  assert.deepStrictEqual(calls, [['upgrade', '--check', '--json']]);
  assert.match(shown, /0\.3\.5 is available/);
  assert.match(shown, /installed: 0\.3\.4/);
  assert.deepStrictEqual(offered, ['Upgrade', 'Not now']);
  assert.deepStrictEqual(upgraded, [installed], 'the upgrade runs on the binary that was checked');
});

test('a check that fails, or prints no JSON, is silent', async () => {
  stubRun({ code: 70, stdout: '', stderr: '✗ could not reach GitHub' });
  let shown = false;
  const original = vscode.window.showInformationMessage;
  vscode.window.showInformationMessage = async () => {
    shown = true;
    return undefined;
  };
  try {
    await check.maybeCheckForUpgrade(context() as any, installed, 1);
  } finally {
    vscode.window.showInformationMessage = original;
  }
  assert.strictEqual(shown, false);
});
