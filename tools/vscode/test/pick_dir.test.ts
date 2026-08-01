import { vscode, reset } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import ui = require('../src/ui');

/**
 * The `--dir` picker. `--dir` is deliberately open — a name that names no
 * existing folder creates one — which is why this drives a `QuickPick` rather
 * than calling `showQuickPick`, and why most of what is worth testing is what
 * happens as the user types.
 */

/** Stub `list-widget-dirs --json` with the given payload (null = frx failed). */
function stubDirs(payload: unknown | null): void {
  // Deliberately reaching past the types: replace the export so the module
  // under test sees the stub.
  (frx as any).run = async () =>
    payload === null
      ? { code: 1, stdout: '', stderr: 'boom' }
      : { code: 0, stdout: JSON.stringify(payload), stderr: '' };
}

const DIRS = { dirs: ['alerts', 'buttons', 'inputs'], home: { field: 'inputs', action: 'buttons' } };

test('pickDir: the kind\'s usual folder is offered first, and labelled', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    qp.selectedItems = [qp.items[0]];
    qp.accept();
  };
  const dir = await ui.pickDir({} as any, '/r', 'field');

  assert.strictEqual(dir, 'inputs');
  const labels = vscode._lastCreatedQuickPick.items.map((i: any) => i.label);
  assert.deepStrictEqual(labels, ['inputs', 'alerts', 'buttons']);
  assert.match(vscode._lastCreatedQuickPick.items[0].description, /where a field usually goes/);
});

test('pickDir: a kind with no usual folder keeps the CLI order', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    qp.selectedItems = [qp.items[0]];
    qp.accept();
  };
  await ui.pickDir({} as any, '/r', 'view');

  const labels = vscode._lastCreatedQuickPick.items.map((i: any) => i.label);
  assert.deepStrictEqual(labels, ['alerts', 'buttons', 'inputs']);
});

test('pickDir: typing an unknown name offers it as a row to create', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    qp.value = 'cards';
    // The user accepts the create row.
    qp.selectedItems = [qp.items[0]];
    qp.accept();
  };
  const dir = await ui.pickDir({} as any, '/r', 'view');

  assert.strictEqual(dir, 'cards');
  assert.strictEqual(vscode._lastCreatedQuickPick.items[0].label, 'cards');
  assert.match(vscode._lastCreatedQuickPick.items[0].description, /new folder/);
});

test('pickDir: typing an existing name adds no duplicate create row', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    qp.value = 'inputs';
    qp.selectedItems = [qp.items[0]];
    qp.accept();
  };
  await ui.pickDir({} as any, '/r', 'view');

  const labels = vscode._lastCreatedQuickPick.items.map((i: any) => i.label);
  assert.deepStrictEqual(labels, ['alerts', 'buttons', 'inputs']);
});

test('pickDir: a name the CLI would reject is not offered', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    // Not a single lower_snake_case segment — the CLI refuses it, so the
    // picker must not present it as creatable.
    qp.value = '../etc';
    qp.hide();
  };
  const dir = await ui.pickDir({} as any, '/r', 'view');

  assert.strictEqual(dir, undefined);
  const labels = vscode._lastCreatedQuickPick.items.map((i: any) => i.label);
  assert.deepStrictEqual(labels, ['alerts', 'buttons', 'inputs']);
});

test('pickDir: accepting with nothing selected takes the typed value', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => {
    qp.value = 'cards';
    qp.selectedItems = [];
    qp.accept();
  };
  assert.strictEqual(await ui.pickDir({} as any, '/r', 'view'), 'cards');
});

test('pickDir: dismissing returns undefined, so the caller aborts', async () => {
  reset();
  stubDirs(DIRS);
  vscode._driveQuickPick = (qp) => qp.hide();
  assert.strictEqual(await ui.pickDir({} as any, '/r', 'view'), undefined);
});

test('pickDir: an unreadable frx falls back to a plain input box', async () => {
  reset();
  stubDirs(null);
  vscode._input = 'cards';
  const dir = await ui.pickDir({} as any, '/r', 'field');

  assert.strictEqual(dir, 'cards');
  assert.ok(vscode._lastInput, 'the fallback must actually prompt');
  assert.strictEqual(vscode._lastCreatedQuickPick, null);
});

test('pickDir: an existing folder is accepted however it is named', async () => {
  // The CLI takes a folder that is already there as it is named, and only
  // enforces snake_case for one it has to create. The picker used to apply the
  // new-folder rule to everything — so it listed a camelCase folder returned by
  // `list-widget-dirs` and then silently refused the pick.
  reset();
  stubDirs({ dirs: ['alerts', 'myWidgets'], home: {} });
  vscode._driveQuickPick = (qp) => {
    qp.selectedItems = [qp.items.find((i: any) => i.label === 'myWidgets')];
    qp.accept();
  };
  assert.strictEqual(await ui.pickDir({} as any, '/repo', 'widget'), 'myWidgets');
});

test('pickDir: a typed folder that is not there still has to be snake_case', async () => {
  reset();
  stubDirs({ dirs: ['alerts'], home: {} });
  vscode._driveQuickPick = (qp) => {
    qp.value = 'myNewWidgets';
    qp.accept();
  };
  assert.strictEqual(await ui.pickDir({} as any, '/repo', 'widget'), undefined);
});
