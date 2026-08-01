import { vscode, reset } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import queries = require('../src/queries');
import ui = require('../src/ui');

/** Stub frx.run so list-substates / list-routes return the given payloads. */
function stubList(map: Record<string, unknown>): void {
  // Deliberately reaching past the types: the point is to replace the real
  // export so the module under test sees the stub.
  (frx as any).run = async (_inv: unknown, args: string[]) => ({
    code: 0,
    stdout: JSON.stringify(map[args[0]] ?? {}),
    stderr: '',
  });
}

test('pickSubstate: builds items, drops file-less wait, returns picked field', async () => {
  reset();
  stubList({
    'list-substates': {
      substates: [
        { field: 'logIn', type: 'LogInState', file: '/x' },
        { field: 'wait', type: 'Wait', file: null },
      ],
    },
  });
  vscode._quickPick = (items: any[]) => items[0];
  const s = await ui.pickSubstate({} as any, '/r', 'T');
  assert.deepStrictEqual(vscode._lastQuickPick!.items, [{ label: 'logIn', description: 'LogInState' }]);
  assert.strictEqual(vscode._lastQuickPick!.opts.matchOnDescription, true);
  assert.strictEqual(s, 'logIn');
});

test('pickSubstate: falls back to a free-text box when the list is empty', async () => {
  reset();
  stubList({ 'list-substates': { substates: [] } });
  vscode._input = 'typedName';
  const s = await ui.pickSubstate({} as any, '/r', 'T');
  assert.strictEqual(vscode._lastQuickPick, null); // never offered a quick pick
  assert.strictEqual(s, 'typedName');
});

test('pickSubstate: returns undefined when cancelled', async () => {
  reset();
  stubList({ 'list-substates': { substates: [{ field: 'a', type: 'A', file: '/a' }] } });
  vscode._quickPick = undefined; // Esc
  assert.strictEqual(await ui.pickSubstate({} as any, '/r', 'T'), undefined);
});

test('pickArtifact: groups substates/pages with separators, returns { name, kind }', async () => {
  reset();
  stubList({
    'list-substates': { substates: [{ field: 'logIn', type: 'LogInState', file: '/x' }] },
    'list-routes': {
      routes: [
        { route: 'LogInRoute', path: '/login', connector: '/c' },
        { route: 'SplashRoute', path: '/splash', connector: '/s' },
      ],
    },
  });
  vscode._quickPick = (items: any[]) => items[3]; // the LogIn page row (after both separators)
  const a = await ui.pickArtifact({} as any, '/r', 'T');

  assert.deepStrictEqual(vscode._lastQuickPick!.items, [
    { label: 'Substates', kind: -1 },
    { label: 'logIn', description: 'LogInState', frxKind: 'substate' },
    { label: 'Pages', kind: -1 },
    { label: 'LogIn', description: '/login', frxKind: 'page' },
    { label: 'Splash', description: '/splash', frxKind: 'page' },
  ]);
  // The artifact kind must NOT ride on `kind` — that's the reserved separator prop.
  assert.deepStrictEqual(a, { name: 'LogIn', kind: 'page' });
});

test('pickArtifact: omits a group that has no rows', async () => {
  reset();
  stubList({
    'list-substates': { substates: [{ field: 'logIn', type: 'LogInState', file: '/x' }] },
    'list-routes': { routes: [] },
  });
  vscode._quickPick = (items: any[]) => items[1];
  await ui.pickArtifact({} as any, '/r', 'T');
  assert.deepStrictEqual(
    vscode._lastQuickPick!.items.map((i: any) => i.label),
    ['Substates', 'logIn'],
  );
});

test('pickArtifact: free-text fallback yields an unknown kind', async () => {
  reset();
  stubList({ 'list-substates': { substates: [] }, 'list-routes': { routes: [] } });
  vscode._input = 'typedName';
  assert.deepStrictEqual(await ui.pickArtifact({} as any, '/r', 'T'), { name: 'typedName', kind: undefined });
});

/** Lets the event loop turn, the way a pause between two clicks does. */
const tick = () => new Promise((r) => setImmediate(r));

/** The real export, restored after a test that replaces it. */
const realListMixins = queries.listMixins;

/** Scripted `frx list-mixins --json`, in the shape the CLI emits. */
function stubMixins(): void {
  // Replacing a module export outlives the test that did it; `reset()` only
  // restores the vscode stub, so a later test would run against this one and
  // pass for the wrong reason.
  test.afterEach(() => {
    (queries as any).listMixins = realListMixins;
  });
  (queries as any).listMixins = async () => [
    { name: 'checkInternet', clause: 'CheckInternet', summary: 'connectivity', implies: null,
      conflictsWith: ['abortWhenNoInternet'] },
    { name: 'noDialog', clause: 'NoDialog', summary: 'no dialog', implies: 'checkInternet',
      conflictsWith: ['abortWhenNoInternet'] },
    { name: 'abortWhenNoInternet', clause: 'AbortWhenNoInternet', summary: 'abort', implies: null,
      conflictsWith: ['checkInternet', 'noDialog'] },
    { name: 'retry', clause: 'Retry', summary: 'retry', implies: null,
      conflictsWith: ['debounce'] },
    { name: 'debounce', clause: 'Debounce', summary: 'debounce', implies: null,
      conflictsWith: ['retry'] },
  ];
}

test('pickMixins: ticking one of a conflicting pair unticks the other', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'retry' }];
    await tick();
    qp.selectedItems = [{ label: 'retry' }, { label: 'debounce' }];
    await tick();
    qp.accept();
  };
  const picked = await ui.pickMixins({} as any, '/r', 'T');
  // async_redux makes the pair a compile error; keeping both would scaffold a
  // file that cannot build.
  assert.deepStrictEqual(picked, ['debounce']);
  assert.match(vscode._lastCreatedQuickPick.placeholder, /Unticked retry/);
  assert.match(vscode._lastCreatedQuickPick.placeholder, /debounce/);
});

test('pickMixins: the list itself never changes', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'debounce' }];
    await tick();
    qp.accept();
  };
  await ui.pickMixins({} as any, '/r', 'T');
  // Removing rows was the first design: assigning `items` clears the selection
  // and reports it a tick later, wiping the pick that caused the rebuild.
  const offered = vscode._lastCreatedQuickPick.items.map((i: any) => i.label);
  assert.strictEqual(offered.length, 5);
  assert.ok(offered.includes('retry'), 'the excluded one is still shown');
});

test('pickMixins: compatible picks all survive', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'checkInternet' }];
    await tick();
    qp.selectedItems = [{ label: 'checkInternet' }, { label: 'retry' }];
    await tick();
    qp.accept();
  };
  const picked = await ui.pickMixins({} as any, '/r', 'T');
  assert.deepStrictEqual(picked!.sort(), ['checkInternet', 'retry']);
});

test('pickMixins: unticking by hand is respected', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'debounce' }];
    await tick();
    qp.selectedItems = [];
    await tick();
    qp.accept();
  };
  assert.deepStrictEqual(await ui.pickMixins({} as any, '/r', 'T'), []);
});

test('pickMixins: a set reached again by hand is a click, not an echo', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'retry' }];
    await tick();
    qp.selectedItems = [{ label: 'retry' }, { label: 'debounce' }]; // retry unticked
    await tick();
    qp.selectedItems = [];
    await tick();
    qp.selectedItems = [{ label: 'debounce' }]; // the same set as the write-back
    await tick();
    qp.accept();
  };
  // Left uncleared, the echo guard swallows this tick: the box shows it
  // checked and Enter yields nothing.
  assert.deepStrictEqual(await ui.pickMixins({} as any, '/r', 'T'), ['debounce']);
});

test('pickMixins: a conflicting pair arriving at once does not survive', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'retry' }, { label: 'debounce' }];
    await tick();
    qp.accept();
  };
  const picked = await ui.pickMixins({} as any, '/r', 'T');
  // Both are new, so a rule phrased over what *changed* never fires — and the
  // CLI then refuses the pair the picker exists to prevent.
  assert.deepStrictEqual(picked, ['debounce']);
});

test('pickMixins: an unreadable catalogue is reported, not passed off as none', async () => {
  reset();
  (queries as any).listMixins = async () => null;
  let warned = '';
  vscode.window.showWarningMessage = async (m: string) => ((warned = m), undefined);
  assert.deepStrictEqual(await ui.pickMixins({} as any, '/r', 'T'), []);
  // A `list-mixins` that refused `--root` looked exactly like skipping the
  // step; the only trace was in the output channel.
  assert.match(warned, /could not read the action mixins/);
});

test('pickMixins: an implication is shown, not hidden', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = (qp: any) => qp.accept();
  await ui.pickMixins({} as any, '/r', 'T');
  const noDialog = vscode._lastCreatedQuickPick.items.find((i: any) => i.label === 'noDialog');
  assert.match(noDialog.description, /implies checkInternet/);
});

test('pickMixins: dismissing is not the same as picking none', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = (qp: any) => qp.hide();
  assert.strictEqual(await ui.pickMixins({} as any, '/r', 'T'), undefined);
});


test('pickMixins: a pick survives the pause before the next click', async () => {
  reset();
  stubMixins();
  vscode._driveQuickPick = async (qp: any) => {
    qp.selectedItems = [{ label: 'debounce' }];
    // Rebuilding `items` clears the selection and reports it on a later tick.
    // Accepting in the same turn hid that; a user pausing between clicks does
    // not, and saw the tick vanish the instant they made it.
    await tick();
    await tick();
    qp.accept();
  };
  const picked = await ui.pickMixins({} as any, '/r', 'T');
  assert.deepStrictEqual(picked, ['debounce']);
});
