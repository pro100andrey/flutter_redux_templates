// The FRX Map's panel around its one read: what it shows when the read fails,
// and what happens when the panel or a newer read gets there first.
import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import paths = require('../src/paths');
import queries = require('../src/queries');
import { showMap } from '../src/map';
import type { AppGraph } from '../src/queries';

const GRAPH: AppGraph = {
  nodes: [{ id: 'substate:profile', kind: 'substate', name: 'profile', type: 'ProfileState' } as any],
  edges: [],
  unresolved: [],
  orphans: [],
};

/** A webview panel as far as the Map drives one; `close()` is the user closing it. */
function fakePanel() {
  const disposers: (() => void)[] = [];
  const panel = {
    webview: {
      html: '',
      cspSource: '',
      asWebviewUri: (u: any) => u,
      onDidReceiveMessage: () => ({ dispose() {} }),
    },
    reveal() {},
    onDidDispose: (h: () => void) => (disposers.push(h), { dispose() {} }),
    close() {
      for (const h of disposers) h();
    },
  };
  return panel;
}

const context = { extensionUri: vscode.Uri.file('/ext') } as any;

/** Scripts the reads: each call to `frx graph` returns a promise settled by the test. */
function setup() {
  const panels: ReturnType<typeof fakePanel>[] = [];
  vscode.window.createWebviewPanel = () => {
    const p = fakePanel();
    panels.push(p);
    return p;
  };
  const reads: ((g: AppGraph | null) => void)[] = [];
  (paths as any).findWorkspaceRoot = () => '/repo';
  (frx as any).resolveFrx = async () => ({ cmd: 'frx', baseArgs: [], label: 'frx' });
  (queries as any).graph = () => new Promise<AppGraph | null>((r) => reads.push(r));
  const errors: string[] = [];
  vscode.window.showErrorMessage = async (m: string) => void errors.push(m);
  return { panels, reads, errors };
}

const tick = (): Promise<void> => new Promise((r) => setImmediate(r));

test('a failed read says so and keeps the last picture, rather than drawing an empty app', async () => {
  const s = setup();
  const first = showMap(context);
  await tick();
  s.reads[0](GRAPH);
  await first;
  const drawn = s.panels[0].webview.html;
  assert.match(drawn, /profile/);

  const again = showMap(context);
  await tick();
  s.reads[1](null);
  await again;

  assert.strictEqual(s.panels[0].webview.html, drawn, 'the previous picture stays');
  assert.match(s.errors[0] ?? '', /could not read the app graph/);
  s.panels[0].close();
});

test('a first read that fails shows why instead of "none"', async () => {
  const s = setup();
  const shown = showMap(context);
  await tick();
  s.reads[0](null);
  await shown;

  assert.match(s.panels[0].webview.html, /could not read the app graph/);
  assert.strictEqual(s.errors.length, 1);
  s.panels[0].close();
});

test('closing the Map while it loads is not an error', async () => {
  const s = setup();
  const shown = showMap(context);
  await tick();
  s.panels[0].close();
  s.reads[0](GRAPH);

  await assert.doesNotReject(shown);
  assert.strictEqual(s.panels[0].webview.html, '', 'nothing is drawn into a closed panel');
});

test('an older read landing after a newer one does not draw over it', async () => {
  const s = setup();
  const older = showMap(context);
  await tick();
  const newer = showMap(context);
  await tick();

  s.reads[1]({ ...GRAPH, nodes: [{ ...GRAPH.nodes[0], id: 'substate:fresh', name: 'fresh' }] });
  await newer;
  s.reads[0](GRAPH);
  await older;

  assert.match(s.panels[0].webview.html, /fresh/);
  assert.strictEqual(s.panels.length, 1, 'one panel for both reads');
  s.panels[0].close();
});
