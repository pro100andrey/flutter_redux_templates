import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { JSDOM } from 'jsdom';
import { buildHtml, picture } from '../src/map';
import type { AppGraph, GraphEdge, GraphNode } from '../src/queries';

/// The Map page, run.
///
/// `map.test.ts` reads the page as text and pins what the script *says*; this
/// file loads it into a DOM and pins what it *does* — which is the only way to
/// see a regression the text does not show. Two went past the text tests: a
/// redraw handing the placement to the other column on every click, and the
/// pane dropping a relation's trigger when the fold had not moved it. Both
/// were caught by hand, in a browser.
///
/// jsdom lays nothing out: every rectangle is zero, so `fit()` clamps every
/// column to its floor and `place()` finds two columns the same height and
/// leaves both in flow. What is testable here is everything else — the wires
/// a picture yields, the focus, the pane, the folds, the gaps and what a
/// refresh remembers. Placement stays a browser's to check.

const MEDIA = path.join(__dirname, '..', '..', 'media', 'map');
const CLIENT_JS = fs.readFileSync(path.join(MEDIA, 'map.js'), 'utf8');

/* eslint-disable @typescript-eslint/no-explicit-any */

function graphOf(partial: Partial<AppGraph>): AppGraph {
  return { nodes: [], edges: [], unresolved: [], orphans: [], ...partial };
}
const SUB = (field: string, type: string): GraphNode => ({
  id: `substate:${field}`,
  kind: 'substate',
  name: field,
  type,
  file: `/repo/business/lib/redux/${field}/models/${field}_state.dart`,
});
const ACTION = (sub: string, name: string): GraphNode => ({
  id: `action:${sub}.${name}`,
  kind: 'action',
  name,
  substate: sub,
  file: `/repo/business/lib/redux/${sub}/actions/x.dart`,
});
const SELECTOR = (sub: string, getter: string): GraphNode => ({
  id: `selector:Select${sub}.${getter}`,
  kind: 'selector',
  name: `Select${sub}.${getter}`,
  substate: sub,
  file: '/repo/business/lib/redux/selectors.dart',
});
const PAGE = (name: string, path: string): GraphNode => ({
  id: `page:${name}`,
  kind: 'page',
  name,
  path,
  file: `/repo/app/lib/connectors/${name}_page_connector.dart`,
});
const CONSUMER = (name: string): GraphNode => ({
  id: `consumer:${name}`,
  kind: 'consumer',
  name,
  file: `/repo/app/lib/connectors/${name}.dart`,
});
const edge = (from: string, to: string, kind: GraphEdge['kind'], via?: string): GraphEdge => ({
  from,
  to,
  kind,
  via,
});

/** What the page asked the editor to remember, and what it was handed. */
interface Host {
  state: any;
  posted: any[];
}

/**
 * The page as the webview would run it, over `graph`, with the editor's API
 * stubbed: `getState` answers `state`, and `setState`/`postMessage` are kept.
 */
function load(graph: AppGraph, state: any = null): { window: any; document: any; host: Host } {
  const host: Host = { state, posted: [] };
  let html = buildHtml(picture(graph, '/repo'));
  // The script inline rather than fetched, and no stylesheet or CSP: jsdom
  // runs scripts it is given and lays out nothing, so neither would add a
  // thing the tests could see.
  html = html
    .replace(/<meta http-equiv="Content-Security-Policy"[\s\S]*?\/>/, '')
    .replace(/<link rel="stylesheet"[^>]*\/>/, '')
    .replace(/<script nonce="[^"]*" src="map\.js"><\/script>/, () => `<script>${CLIENT_JS}</script>`);
  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    beforeParse(window) {
      (window as any).acquireVsCodeApi = () => ({
        getState: () => host.state,
        setState: (s: any) => (host.state = s),
        postMessage: (m: any) => host.posted.push(m),
      });
    },
  });
  return { window: dom.window, document: dom.window.document, host };
}

/** A picture with the shapes the pane and the wires have to get right. */
function typical(): AppGraph {
  return graphOf({
    nodes: [
      SUB('logIn', 'LogInState'),
      SUB('session', 'SessionState'),
      PAGE('logIn', '/login'),
      PAGE('registration', '/register'),
      ACTION('logIn', 'LogInAction'),
      ACTION('session', 'SetTokenAction'),
      ACTION('session', 'ClearTokenAction'),
      SELECTOR('logIn', 'email'),
    ],
    edges: [
      // Two actions of one substate through one callback: one line, said once.
      edge('page:logIn', 'action:session.SetTokenAction', 'dispatches', 'onSubmit'),
      edge('page:logIn', 'action:session.ClearTokenAction', 'dispatches', 'onSubmit'),
      // The same page reads the substate it dispatches into: still one line.
      edge('page:logIn', 'selector:SelectlogIn.email', 'uses'),
      edge('page:logIn', 'action:logIn.LogInAction', 'dispatches', 'onSubmit'),
      // A relation the fold never touches, carrying a trigger of its own.
      edge('page:logIn', 'page:registration', 'navigates', 'onPressedRegister'),
      edge('page:registration', 'page:logIn', 'navigates', 'onPressedBackToLogin'),
    ],
  });
}

const rows = (document: any) => [...document.querySelectorAll('.node')].map((n: any) => n.dataset.id);
const wires = (document: any) => [...document.querySelectorAll('#wires path.wire')];
const hover = (window: any, el: any) =>
  el.dispatchEvent(new window.MouseEvent('mouseover', { bubbles: true }));
const paneText = (document: any) =>
  document.getElementById('pane').textContent.replace(/\s+/g, ' ').trim();

test('the page draws one wire per pair of rows, state-changing ones last', () => {
  const { document } = load(typical());
  assert.deepStrictEqual(
    rows(document).sort(),
    ['page:logIn', 'page:registration', 'substate:logIn', 'substate:session'],
    'actions and selectors are rows of nobody — they fold into their substate',
  );
  const drawn = wires(document);
  assert.strictEqual(drawn.length, 3, 'logIn↔session, logIn↔logIn(state), logIn↔registration');
  const classes = drawn.map((w) => w.getAttribute('class'));
  // A line that dispatches among other things is a changing line, and every
  // changing line comes after every line that only reads or navigates.
  const changing = classes.map((c) => c.includes(' changes'));
  const firstChanging = changing.indexOf(true);
  assert.ok(firstChanging >= 0, 'something changes state');
  assert.ok(changing.slice(firstChanging).every(Boolean), `changing lines are drawn last: ${classes}`);
  assert.ok(classes.some((c) => c.includes('navigates') && !c.includes(' changes')));
});

test('hovering a row lights it, its wires and the rows across; leaving lets go', () => {
  const { window, document } = load(typical());
  const board = document.getElementById('board');
  hover(window, document.querySelector('[data-id="substate:session"]'));
  assert.ok(board.classList.contains('focusing'));
  assert.deepStrictEqual(
    [...document.querySelectorAll('.node.lit')].map((n: any) => n.dataset.id).sort(),
    ['page:logIn', 'substate:session'],
  );
  assert.strictEqual(document.querySelectorAll('path.wire.lit').length, 1);
  board.dispatchEvent(new window.Event('pointerleave'));
  assert.ok(!board.classList.contains('focusing'));
  assert.strictEqual(document.querySelectorAll('.lit').length, 0);
});

test('the pane says each row across once, with what is behind the line under it', () => {
  const { window, document } = load(typical());
  hover(window, document.querySelector('[data-id="substate:session"]'));
  const pane = document.getElementById('pane');
  assert.deepStrictEqual(
    [...pane.querySelectorAll('h4')].map((h: any) => h.textContent),
    ['Changed by'],
  );
  const entries = [...pane.querySelectorAll('li')];
  assert.strictEqual(entries.length, 1, 'one page, said once — not once per action');
  const [entry] = entries;
  const far = entry.querySelector('.far');
  assert.strictEqual(far.firstChild.textContent, 'logIn');
  // The trigger every action shares is said beside the row, not per action.
  assert.strictEqual(far.querySelector('.via').textContent.trim(), 'onSubmit');
  assert.deepStrictEqual(
    [...entry.querySelectorAll('.what')].map((w: any) => w.textContent),
    ['SetTokenAction', 'ClearTokenAction'],
  );
  assert.strictEqual(entry.querySelectorAll('.item .via').length, 0, 'and not again per item');
});

test('a relation the fold did not move still shows its trigger', () => {
  // A page navigating to another carries the callback that does it, and the
  // pane used to show it only for actions the fold had hidden — so every
  // `navigates` entry was a bare page name.
  const { window, document } = load(typical());
  hover(window, document.querySelector('[data-id="page:registration"]'));
  const pane = document.getElementById('pane');
  const groups = [...pane.querySelectorAll('h4')].map((h: any) => h.textContent);
  assert.ok(groups.includes('navigates'), `${groups}`);
  assert.match(paneText(document), /logIn\s*onPressedBackToLogin/);
  assert.match(paneText(document), /onPressedRegister/);
});

test('clicking a row pins it, and the editor is told; Escape lets go', () => {
  const { window, document, host } = load(typical());
  const row = document.querySelector('[data-id="substate:session"]');
  row.querySelector('.head').dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  assert.ok(row.classList.contains('pinned'));
  assert.strictEqual(host.state.pinned, 'substate:session');
  document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape' }));
  assert.ok(!row.classList.contains('pinned'));
  assert.strictEqual(host.state.pinned, null);
});

test('a pinned row and the folds come back on a refresh', () => {
  const { document } = load(typical(), { pinned: 'substate:session', folded: [], placed: -1 });
  assert.ok(document.querySelector('[data-id="substate:session"]').classList.contains('pinned'));
  assert.ok(document.getElementById('board').classList.contains('focusing'), 'and the picture is about it');
});

test("expanding a substate lists what it owns, and a redraw keeps the picture's wires", () => {
  const { window, document } = load(typical());
  const session = document.querySelector('[data-id="substate:session"]');
  const list = session.querySelector('.owned ul');
  assert.ok(list.hidden, 'folded to a count at first');
  assert.match(session.querySelector('.count').textContent, /2 actions/);
  session.querySelector('.count').dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  assert.ok(!list.hidden);
  assert.deepStrictEqual(
    [...list.querySelectorAll('li')].map((li: any) => li.textContent),
    ['SetTokenAction', 'ClearTokenAction'],
  );
  assert.strictEqual(wires(document).length, 3, 'redrawn, not lost');
});

test('a row with many regions starts folded, and their lines land on it', () => {
  const { window, document, host } = load(
    graphOf({
      nodes: [PAGE('home', '/home'), CONSUMER('R1'), CONSUMER('R2'), CONSUMER('R3'), CONSUMER('R4'), SUB('a', 'A')],
      edges: [
        ...['R1', 'R2', 'R3', 'R4'].map((r) => edge('page:home', `consumer:${r}`, 'builds')),
        edge('consumer:R1', 'substate:a', 'uses'),
      ],
    }),
  );
  const home = document.querySelector('[data-id="page:home"]');
  assert.ok(home.classList.contains('folded'), 'four regions is past the fold');
  assert.strictEqual(wires(document).length, 1, 'the region\'s line lands on the folded page');
  home.querySelector('.regions').dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  assert.ok(!home.classList.contains('folded'));
  // `deepEqual`, not strict: the value crossed from the page's realm, whose
  // Array is not this one's.
  assert.deepEqual(host.state.folded, [], 'the unfold is remembered');
  assert.strictEqual(wires(document).length, 1, 'the region now carries its own line');
});

test('the gaps are grouped by reason, one line per edge', () => {
  const { document } = load(
    graphOf({
      nodes: [SUB('a', 'A')],
      unresolved: [
        { kind: 'dispatch-target', expr: 'One()', at: '/repo/a.dart', why: 'no file declares it', owner: 'x' },
        { kind: 'dispatch-target', expr: 'Two()', at: '/repo/b.dart', why: 'no file declares it', owner: 'x' },
        { kind: 'pop-destination', expr: 'pop()', at: '/repo/c.dart', why: 'the stack is not static', owner: 'x' },
      ],
    }),
  );
  const box = document.querySelector('.gaps');
  assert.match(box.querySelector('h2').textContent, /3 unresolved/);
  assert.deepStrictEqual(
    [...box.querySelectorAll('.why')].map((p: any) => p.textContent),
    ['no file declares it', 'the stack is not static'],
  );
  const gaps = [...box.querySelectorAll('.gap')];
  assert.strictEqual(gaps.length, 3);
  assert.match(gaps[0].querySelector('code').textContent, /One\(\)/);
  assert.strictEqual(gaps[0].querySelector('.at').textContent, 'a.dart', 'relative to the root');
});

test('the refresh button asks the editor for a fresh picture', () => {
  const { window, document, host } = load(typical());
  document.getElementById('refresh').dispatchEvent(new window.MouseEvent('click'));
  assert.deepEqual(host.posted, [{ type: 'refresh' }]);
});
