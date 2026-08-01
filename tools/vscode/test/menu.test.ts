import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import menu = require('../src/commands/menu');

/* eslint-disable @typescript-eslint/no-explicit-any */

/// The overlay is a rendering of the command inventory, not a second list.
///
/// The defect these pin is drift nobody noticed: the overlay and the palette had
/// come apart in both directions. Routing by command id is what makes them one
/// thing — so what is worth asserting here is that every row carries a command,
/// that the grouping is present, and that the watch keeps the live state which is
/// the only reason this surface exists beside a searchable palette.

/** The rows the overlay offered, and the command the given label routes to. */
function offered(): any[] {
  return vscode._lastQuickPick!.items;
}

function appWith(watch: any): any {
  return { context: {}, watch, doctor: null, refresh: () => {} };
}

test('the overlay groups its rows under family separators', async () => {
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  const separators = offered()
    .filter((r) => r.kind === vscode.QuickPickItemKind.Separator)
    .map((r) => r.label);
  assert.deepStrictEqual(separators, ['Create & wire', 'Edit existing', 'Inspect', 'Workflow']);
});

test('every row routes by command id, and every row has a description', async () => {
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  for (const row of offered()) {
    if (row.kind === vscode.QuickPickItemKind.Separator) continue;
    assert.match(row.command, /^frx\.[A-Za-z]+$/, `row "${row.label}" routes nowhere`);
    assert.ok(row.description, `row "${row.label}" lost its description`);
  }
});

test('the inventory has no duplicate and no submenu row', async () => {
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  const commands = offered()
    .filter((r) => r.command)
    .map((r) => r.command);
  assert.strictEqual(new Set(commands).size, commands.length, 'a capability is listed twice');
  // The seven single-file scaffolders used to hide behind one "New…" row, which
  // is why they had no command identity at all.
  for (const c of ['frx.addWidget', 'frx.addModel', 'frx.addService', 'frx.addTabs']) {
    assert.ok(commands.includes(c), `${c} is not in the overlay`);
  }
  assert.ok(!commands.includes('frx.menu'), 'the overlay must not list itself');
});

test('the report-only audit sits beside the fixing one', async () => {
  // The destructive one used to be the searchable one and the read-only one was
  // reachable only from here.
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  const commands = offered().map((r) => r.command);
  assert.ok(commands.includes('frx.doctor'));
  assert.ok(commands.includes('frx.doctorFix'));
});

test('the watch row reflects its live state', async () => {
  vscode._quickPick = undefined;
  await menu.showMenu(appWith({ running: true, enabled: true }));
  const row = offered().find((r) => r.command === 'frx.toggleWatch');
  assert.match(row.description, /running/);
  assert.match(row.label, /\$\(check\)/);

  vscode._quickPick = undefined;
  await menu.showMenu(appWith({ running: false, enabled: true }));
  const stopped = offered().find((r) => r.command === 'frx.toggleWatch');
  assert.match(stopped.description, /enabled but stopped/);
});

test('outside the monorepo the rows stay, with their static descriptions', async () => {
  // The inventory is one list. Hiding rows here would be the drift the mirror
  // rule exists to prevent; the commands themselves are gated on frx.isMonorepo.
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  const row = offered().find((r) => r.command === 'frx.toggleWatch');
  assert.strictEqual(row.description, 'Start or stop codegen on save');
});

test('picking a row executes its command', async () => {
  const ran: string[] = [];
  (vscode.commands as any).executeCommand = (id: string) => {
    ran.push(id);
  };
  vscode._quickPick = (items: any[]) => items.find((r) => r.command === 'frx.addWidget');
  await menu.showMenu(appWith(null));
  assert.deepStrictEqual(ran, ['frx.addWidget']);
});

test('dismissing the overlay runs nothing', async () => {
  const ran: string[] = [];
  (vscode.commands as any).executeCommand = (id: string) => {
    ran.push(id);
  };
  vscode._quickPick = undefined;
  await menu.showMenu(appWith(null));
  assert.deepStrictEqual(ran, []);
});
