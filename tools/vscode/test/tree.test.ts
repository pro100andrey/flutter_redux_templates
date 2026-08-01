import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import paths = require('../src/paths');
import queries = require('../src/queries');
import tree = require('../src/tree');
import type { AppGraph, GraphNode } from '../src/queries';

/* eslint-disable @typescript-eslint/no-explicit-any */

const SUB = (name: string, type: string, file?: string): GraphNode => ({
  id: `substate:${name}`,
  kind: 'substate',
  name,
  type,
  file: file ?? null,
});

const ACTION = (substate: string, name: string, extra: Partial<GraphNode> = {}): GraphNode => ({
  id: `action:${substate}.${name}`,
  kind: 'action',
  name,
  substate,
  file: `/repo/${substate}/${name}.dart`,
  ...extra,
});

const SELECTOR = (substate: string, name: string): GraphNode => ({
  id: `selector:${name}`,
  kind: 'selector',
  name,
  substate,
  file: '/repo/selectors.dart',
});

const PAGE = (name: string, extra: Partial<GraphNode> = {}): GraphNode => ({
  id: `page:${name}`,
  kind: 'page',
  name,
  route: `${name[0].toUpperCase()}${name.slice(1)}Route`,
  file: null,
  ...extra,
});

/** A provider whose graph is `graph`, counting how often the CLI is read. */
/**
 * A graph literal with the sections a tree test does not care about filled in.
 *
 * The tree reads nodes and orphans; `edges` and `unresolved` are the structural
 * picture's business (see map.ts). Defaulted here so a test says only what it is
 * about.
 */
function graphOf(partial: Partial<AppGraph>): AppGraph {
  return { nodes: [], edges: [], unresolved: [], orphans: [], ...partial };
}

function provider(graph: AppGraph | null): {
  p: tree.FrxTreeProvider;
  reads: () => number;
} {
  let reads = 0;
  (paths as any).findWorkspaceRoot = () => '/repo';
  (frx as any).resolveFrx = async () => ({} as any);
  (queries as any).graph = async () => {
    reads++;
    return graph;
  };
  return { p: new tree.FrxTreeProvider({} as any), reads: () => reads };
}

const groups = (p: tree.FrxTreeProvider) => p.getChildren();
const of = (p: tree.FrxTreeProvider, i: number) =>
  groups(p).then((g) => p.getChildren(g[i]));

test('routeDescription: path alone, and what makes a route special', () => {
  assert.strictEqual(tree.routeDescription(PAGE('home', { path: '/home' })), '/home');
  assert.strictEqual(
    tree.routeDescription(PAGE('splash', { path: '/splash', initial: true })),
    '/splash · initial',
  );
  assert.strictEqual(
    tree.routeDescription(PAGE('logIn', { path: '/login', public: true })),
    '/login · public',
  );
});

test('actionDescription: how it runs, then whether anything reaches it', () => {
  assert.strictEqual(
    tree.actionDescription(
      ACTION('logIn', 'LogInAction', {
        isAsync: true,
        mixins: ['WaitingAction'],
        throwsUserException: true,
      }),
      false,
    ),
    'async · WaitingAction · throws',
  );
  assert.strictEqual(
    tree.actionDescription(ACTION('session', 'SetTokenAction'), true),
    'nothing dispatches',
  );
});

test('substates and routes come from the one graph', async () => {
  const { p } = provider(graphOf({
    nodes: [SUB('logIn', 'LogInState'), PAGE('home', { path: '/home' })],
    orphans: [],
  }));
  const [subs, routes] = [await of(p, 0), await of(p, 1)];
  assert.deepStrictEqual(
    subs.map((i) => [i.label, i.description]),
    [['logIn', 'LogInState']],
  );
  assert.deepStrictEqual(
    routes.map((i) => [i.label, i.description]),
    [['HomeRoute', '/home']],
  );
});

test('one CLI read backs the whole tree, and refresh() re-reads', async () => {
  const { p, reads } = provider(graphOf({
    nodes: [SUB('logIn', 'LogInState'), ACTION('logIn', 'LogInAction')],
    orphans: [],
  }));
  const g = await groups(p);
  await p.getChildren(g[0]);
  await p.getChildren(g[1]);
  const subs = await p.getChildren(g[0]);
  await p.getChildren(subs[0]);
  assert.strictEqual(reads(), 1, 'the graph is read once per refresh cycle');

  p.refresh();
  await p.getChildren(g[0]);
  assert.strictEqual(reads(), 2, 'refresh() drops the cache');
});

test('a substate expands into its own actions and selectors — not another\'s', async () => {
  const { p } = provider(graphOf({
    nodes: [
      SUB('logIn', 'LogInState'),
      SUB('session', 'SessionState'),
      ACTION('logIn', 'SetEmailAction'),
      SELECTOR('logIn', 'SelectLogIn.isWaiting'),
      // The name a flat list could not tell apart — this repo has three.
      ACTION('session', 'SetEmailAction'),
    ],
    orphans: [],
  }));
  const subs = await of(p, 0);
  const children = await p.getChildren(subs[0]);
  assert.deepStrictEqual(
    children.map((i) => i.label),
    ['SetEmailAction', 'isWaiting'],
    'the selector sheds the Select… prefix — the row above already says it',
  );
});

test('a substate that owns nothing does not offer an expand arrow', async () => {
  const { p } = provider(graphOf({
    nodes: [SUB('logIn', 'LogInState'), SUB('wait', 'Wait'), ACTION('logIn', 'LogInAction')],
    orphans: [],
  }));
  const [logIn, wait] = await of(p, 0);
  assert.strictEqual(logIn.collapsibleState, 1, 'Collapsed');
  assert.strictEqual(wait.collapsibleState, 0, 'None — expanding would show "(none)"');
});

test('a selector nothing reads is marked with why', async () => {
  const { p } = provider(graphOf({
    nodes: [
      SUB('session', 'SessionState'),
      SELECTOR('session', 'SelectSession.token'),
      SELECTOR('session', 'SelectSession.isAvailable'),
    ],
    orphans: [{ node: 'selector:SelectSession.token', why: 'nothing reads it' }],
  }));
  const subs = await of(p, 0);
  const [dead, live] = await p.getChildren(subs[0]);
  assert.strictEqual(dead.description, 'nothing reads it');
  assert.strictEqual((dead.iconPath as any).id, 'warning');
  assert.strictEqual(live.description, '');
  assert.strictEqual((live.iconPath as any).id, 'symbol-property');
});

test('an action nothing dispatches is marked, not hidden', async () => {
  const { p } = provider(graphOf({
    nodes: [
      SUB('session', 'SessionState'),
      ACTION('session', 'SetTokenAction'),
      ACTION('session', 'LogOutAction'),
    ],
    orphans: [{ node: 'action:session.SetTokenAction', why: 'no dispatcher found' }],
  }));
  const subs = await of(p, 0);
  const [orphan, reached] = await p.getChildren(subs[0]);
  assert.strictEqual(orphan.description, 'nothing dispatches');
  assert.strictEqual((orphan.iconPath as any).id, 'warning');
  assert.strictEqual(reached.description, '', 'the reached one carries no marker');
  assert.strictEqual((reached.iconPath as any).id, 'zap');
});

test('empty groups say so; an unreadable CLI says something else', async () => {
  const empty = provider(graphOf({}));
  assert.deepStrictEqual((await of(empty.p, 0)).map((i) => i.label), ['(none)']);

  const broken = provider(null);
  assert.deepStrictEqual(
    (await of(broken.p, 0)).map((i) => i.label),
    ['(frx unavailable — see FRX output)'],
  );
});

test('selectionAt: 1-based from frx becomes 0-based for the API', () => {
  const sel = tree.selectionAt({ line: 69, column: 15 }) as any;
  assert.strictEqual(sel.selection.start.line, 68);
  assert.strictEqual(sel.selection.start.character, 14);
  assert.strictEqual(sel.selection.end.line, 68, 'a caret, not a range');
});

test('selectionAt: no position means open the file at its top', () => {
  // An action's file *is* the action — there is nothing to scroll to.
  assert.strictEqual(tree.selectionAt({}), undefined);
  assert.strictEqual(tree.selectionAt({ line: 0 }), undefined);
});

test('selectionAt: a line without a column lands at its start, not off it', () => {
  const sel = tree.selectionAt({ line: 3 }) as any;
  assert.strictEqual(sel.selection.start.character, 0);
});

test('a route keeps the base name the CLI resolves, not the Route class', async () => {
  const { p } = provider(graphOf({ nodes: [PAGE('logIn', { path: '/login' })] }));
  const [route] = await of(p, 1);
  assert.strictEqual(route.label, 'LogInRoute');
  assert.strictEqual(route.frxName, 'LogIn');
  assert.strictEqual(route.frxKind, 'page');
});
