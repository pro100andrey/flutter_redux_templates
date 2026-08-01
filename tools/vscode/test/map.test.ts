import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as vm from 'node:vm';
import { buildHtml, picture } from '../src/map';
import type { AppGraph, GraphEdge, GraphNode } from '../src/queries';

/* eslint-disable @typescript-eslint/no-explicit-any */

/// The structural picture, folded out of the wiring graph.
///
/// The fold is the whole design: substates and pages are the skeleton, actions and
/// selectors collapse into their owner, and every edge that ended on one is
/// rewritten to that owner. What is worth pinning is that the collapse does not
/// lose relations and does not multiply them — and the division of labour with the
/// tree, which is why hygiene marks are absent here and gaps are present.

/**
 * An edge as the *relation* it states — without the anchors, which are a drawing
 * detail with their own tests in `layout.test.ts`.
 */
const relation = (e: {
  from: string;
  to: string;
  relations: { kind: string; via: string }[];
  side: string;
}) => ({
  from: e.from,
  to: e.to,
  kind: e.relations.map((r) => r.kind).join('+'),
  via: e.relations.map((r) => r.via).join('+'),
  side: e.side,
});

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
  line: 12,
  column: 3,
});
const PAGE = (name: string, path: string): GraphNode => ({
  id: `page:${name}`,
  kind: 'page',
  name,
  path,
  file: `/repo/app/lib/connectors/${name}_page_connector.dart`,
});
const edge = (from: string, to: string, kind: GraphEdge['kind'], via?: string): GraphEdge => ({
  from,
  to,
  kind,
  via,
});

test('the skeleton is substates and the things that act on them', () => {
  const p = picture(
    graphOf({
      nodes: [
        SUB('logIn', 'LogInState'),
        PAGE('logIn', '/login'),
        { id: 'service:SessionDispatcher', kind: 'service', name: 'SessionDispatcher', file: '/s.dart' },
        { id: 'persistor:AppPersistor', kind: 'persistor', name: 'AppPersistor', file: '/p.dart' },
        ACTION('logIn', 'LogInAction'),
        SELECTOR('logIn', 'email'),
      ],
    }),
  );
  assert.deepStrictEqual(p.state.map((n) => n.title), ['logIn']);
  // Sorted the way a reader scans a list — by name, case ignored, which is what
  // `localeCompare` does and what mixes a page's field name with a dispatcher's class
  // name sensibly.
  assert.deepStrictEqual(p.actors.map((n) => n.title), [
    'AppPersistor',
    'logIn',
    'SessionDispatcher',
  ]);
});

test('actions and selectors collapse into their owner, and stay openable', () => {
  const p = picture(
    graphOf({
      nodes: [
        SUB('logIn', 'LogInState'),
        ACTION('logIn', 'LogInAction'),
        ACTION('logIn', 'SetEmailAction'),
        SELECTOR('logIn', 'email'),
      ],
    }),
  );
  const logIn = p.state[0];
  assert.deepStrictEqual(
    logIn.owned.map((o) => [o.title, o.subtitle]),
    [['LogInAction', 'action'], ['SetEmailAction', 'action'], ['email', 'selector']],
    'a selector sheds its Select… qualifier — the row above says it',
  );
  // Clicking any node opens its source, and a selector lands on its getter: every
  // selector in the app shares one file.
  const selector = logIn.owned[2];
  assert.strictEqual(selector.file, '/repo/business/lib/redux/selectors.dart');
  assert.strictEqual(selector.line, 12);
  for (const n of [...p.state, ...p.actors]) assert.ok(n.file, `${n.title} cannot be opened`);
});

test('an edge onto an action is drawn to the substate that owns it', () => {
  const p = picture(
    graphOf({
      nodes: [SUB('logIn', 'LogInState'), PAGE('logIn', '/login'), ACTION('logIn', 'LogInAction')],
      edges: [edge('page:logIn', 'action:logIn.LogInAction', 'dispatches', 'onSubmit')],
    }),
  );
  assert.deepStrictEqual(p.edges.map(relation), [
    {
      from: 'page:logIn',
      to: 'substate:logIn',
      kind: 'dispatches',
      via: 'onSubmit',
      side: 'across',
    },
  ]);
});

test('four dispatches into one substate are one line, not four', () => {
  // The difference between a shape and a hairball.
  const p = picture(
    graphOf({
      nodes: [
        SUB('logIn', 'LogInState'),
        PAGE('logIn', '/login'),
        ACTION('logIn', 'A'),
        ACTION('logIn', 'B'),
      ],
      edges: [
        edge('page:logIn', 'action:logIn.A', 'dispatches', 'onSubmit'),
        edge('page:logIn', 'action:logIn.B', 'dispatches', 'onTap'),
      ],
    }),
  );
  assert.strictEqual(p.edges.length, 1);
});

test("a substate's own action writing it is not a line to itself", () => {
  const p = picture(
    graphOf({
      nodes: [SUB('logIn', 'LogInState'), ACTION('logIn', 'A')],
      edges: [edge('action:logIn.A', 'substate:logIn', 'writes', 'logIn.email')],
    }),
  );
  assert.deepStrictEqual(p.edges.map(relation), []);
});

test('an action writing a substate that is not its own is a line', () => {
  const p = picture(
    graphOf({
      nodes: [SUB('logIn', 'LogInState'), SUB('session', 'SessionState'), ACTION('logIn', 'A')],
      edges: [edge('action:logIn.A', 'substate:session', 'writes', 'session.token')],
    }),
  );
  assert.deepStrictEqual(p.edges.map(relation), [
    {
      from: 'substate:logIn',
      to: 'substate:session',
      kind: 'writes',
      via: 'session.token',
      side: 'right',
    },
  ]);
});

test('an edge inside a column is marked for its own side channel', () => {
  // Drawn straight, it leaves a node's right edge and enters a neighbour's left
  // edge in the same column — a loop across the whole canvas, crossing everything
  // between. It belongs in the margin on its own side.
  const p = picture(
    graphOf({
      nodes: [
        PAGE('logIn', '/login'), PAGE('home', '/home'),
        SUB('a', 'A'), SUB('b', 'B'),
      ],
      edges: [
        edge('page:logIn', 'page:home', 'navigates', 'onDone'),
        edge('substate:a', 'substate:b', 'reads'),
        edge('page:logIn', 'substate:a', 'dispatches'),
      ],
    }),
  );
  const side = Object.fromEntries(p.edges.map((e) => [`${e.from}>${e.to}`, e.side]));
  assert.strictEqual(side['page:logIn>page:home'], 'left', 'actors keep to the left margin');
  assert.strictEqual(side['substate:a>substate:b'], 'right', 'state keeps to the right');
  assert.strictEqual(side['page:logIn>substate:a'], 'across');
});

test('navigation between pages survives the fold', () => {
  const p = picture(
    graphOf({
      nodes: [PAGE('logIn', '/login'), PAGE('home', '/home')],
      edges: [edge('page:logIn', 'page:home', 'navigates', 'onDone')],
    }),
  );
  assert.deepStrictEqual(p.edges.map(relation), [
    {
      from: 'page:logIn',
      to: 'page:home',
      kind: 'navigates',
      via: 'onDone',
      side: 'left',
    },
  ]);
});

test('unresolved edges are carried into the picture', () => {
  // A diagram reads as exhaustive, so it owes the reader a statement of where its
  // own edges are incomplete.
  const p = picture(
    graphOf({
      unresolved: [
        {
          kind: 'dispatch-target',
          owner: 'page:logIn',
          expr: 'SomeFactory()',
          why: 'no imported *_action.dart declares it',
        },
      ],
    }),
  );
  assert.strictEqual(p.gaps.length, 1);
  assert.match(p.gaps[0].what, /dispatch-target/);
  assert.match(p.gaps[0].what, /SomeFactory/);
  assert.match(p.gaps[0].why, /no imported/);
});

test('hygiene marks do not reach the picture', () => {
  // They describe an absence of relationships and belong to the tree, which has a
  // row to hang them on. The tree keeps showing them — see tree.test.ts.
  const p = picture(
    graphOf({
      nodes: [SUB('session', 'SessionState'), ACTION('session', 'SetTokenAction')],
      orphans: [{ node: 'action:session.SetTokenAction', why: 'no dispatcher found' }],
    }),
  );
  const html = buildHtml(p);
  assert.ok(!html.includes('no dispatcher found'));
  assert.ok(!html.includes('nothing reads it'));
});

test('the columns are ordered by their edges, not by name', () => {
  // Alphabetically `a`/`b`/`c` face `s3`/`s2`/`s1` and every line crosses every
  // other. The picture is the same three relations either way; only the order of
  // the rows decides whether a reader can follow one. Which column gets moved to
  // untangle it is the solver's business — the property is that nothing crosses
  // and each page ends up level with the substate it reads.
  const p = picture(
    graphOf({
      nodes: [
        PAGE('a', '/a'), PAGE('b', '/b'), PAGE('c', '/c'),
        SUB('s1', 'S1'), SUB('s2', 'S2'), SUB('s3', 'S3'),
      ],
      edges: [
        edge('page:a', 'substate:s3', 'reads'),
        edge('page:b', 'substate:s2', 'reads'),
        edge('page:c', 'substate:s1', 'reads'),
      ],
    }),
  );
  assert.strictEqual(p.crossings, 0, 'this shape untangles completely');

  const reads: Record<string, string> = { a: 's3', b: 's2', c: 's1' };
  const rows = p.actors.map((n) => n.title);
  const facing = p.state.map((n) => n.title);
  assert.deepStrictEqual(
    rows.map((r) => reads[r]),
    facing,
    'each page sits level with the substate it reads',
  );
});

test('an edgeless node sinks below the connected ones', () => {
  // Named so that alphabetical order is the *wrong* answer: `aWait` would sort
  // first, and it is the row nothing touches.
  const p = picture(
    graphOf({
      nodes: [SUB('zCart', 'CartState'), SUB('aWait', 'Wait'), PAGE('home', '/home')],
      edges: [edge('page:home', 'substate:zCart', 'reads')],
    }),
  );
  assert.deepStrictEqual(p.state.map((n) => n.title), ['zCart', 'aWait']);
});

test('no graph at all draws an empty picture rather than throwing', () => {
  const p = picture(null);
  assert.deepStrictEqual(p, { actors: [], state: [], edges: [], gaps: [], crossings: 0 });
  assert.match(buildHtml(p), /none/);
});

test('two kinds of relation between one pair are drawn once', () => {
  // A page that both dispatches into a substate and reads it is two relations
  // with the same two endpoints. Drawn as two lines they lie exactly on top of
  // each other — indistinguishable anywhere, and doubling every crossing they
  // take part in.
  const p = picture(
    graphOf({
      nodes: [PAGE('logIn', '/login'), SUB('a', 'A')],
      edges: [
        edge('page:logIn', 'substate:a', 'dispatches', 'onSubmit'),
        edge('page:logIn', 'substate:a', 'uses', 'email'),
      ],
    }),
  );
  assert.strictEqual(p.edges.length, 1, 'one line');
  assert.deepStrictEqual(
    p.edges[0].relations.map((r) => [r.kind, r.via]),
    [['dispatches', 'onSubmit'], ['uses', 'email']],
    'and it says which kinds, and what triggers each',
  );
});

test('a pair related both ways is still one line', () => {
  // Two pages that navigate to each other. The picture draws no arrowheads, so
  // the two directions are the same stroke; saying it twice says nothing twice.
  const p = picture(
    graphOf({
      nodes: [PAGE('logIn', '/login'), PAGE('home', '/home')],
      edges: [
        edge('page:logIn', 'page:home', 'navigates', 'onDone'),
        edge('page:home', 'page:logIn', 'navigates', 'onBack'),
      ],
    }),
  );
  assert.strictEqual(p.edges.length, 1);
  assert.deepStrictEqual(
    p.edges[0].relations.map((r) => [r.via, r.reversed]),
    [['onDone', false], ['onBack', true]],
    'the one running against the drawn direction says so',
  );
});

test('two relations leaving one node get different anchors', () => {
  // The picture-level half of the slot: without it, a page that both dispatches
  // into a substate and reads it drew one line twice, and its two relations to
  // different substates left from the same point.
  const p = picture(
    graphOf({
      nodes: [PAGE('logIn', '/login'), SUB('a', 'A'), SUB('b', 'B'), SUB('c', 'C')],
      edges: [
        edge('page:logIn', 'substate:a', 'dispatches'),
        edge('page:logIn', 'substate:b', 'reads'),
        edge('page:logIn', 'substate:c', 'uses'),
      ],
    }),
  );
  const slots = p.edges.map((e) => e.anchors.from.slot);
  assert.strictEqual(new Set(slots).size, 3, 'three lines, three anchors');
  for (const e of p.edges) assert.strictEqual(e.anchors.from.of, 3);
});

test('a same-column edge is not drawn as a straight chord', () => {
  // The rendering half: `across` stays a straight segment, a side-channel edge
  // becomes a curve that leaves and re-enters on one side.
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('logIn', '/login'), PAGE('home', '/home')],
        edges: [edge('page:logIn', 'page:home', 'navigates', 'onDone')],
      }),
    ),
  );
  assert.match(html, /e\.side === 'across'/, 'the drawing branches on the side');
  assert.match(html, /' C '/, 'a side-channel edge is a curve');
  assert.ok(!/createElementNS\([^)]*'line'\)/.test(html), 'no straight-chord lines remain');
});

test('hovering a row dims what it is not attached to', () => {
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('logIn', '/login'), SUB('a', 'A')],
        edges: [edge('page:logIn', 'substate:a', 'reads')],
      }),
    ),
  );
  // The rule is in the stylesheet, so it applies to rows and wires alike and
  // needs no per-element bookkeeping beyond one class.
  assert.match(html, /#board\.focusing[^{]*:not\(\.lit\)/);
  assert.match(html, /mouseenter/);
  assert.match(html, /mouseleave/, 'and it lets go again');
  // The wires carry their endpoints, which is what lets a wire be lit without
  // re-deriving the picture in the DOM.
  assert.match(html, /wire\.dataset\.from/);
});

test('a redraw restores the focus instead of half-dimming the picture', () => {
  // Expanding a row rebuilds every wire, and the pointer never leaves the row
  // while you do it — so without this the focused row's own relations go dim
  // along with everything else, during exactly the interaction the picture is
  // built around.
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('logIn', '/login'), SUB('a', 'A')],
        edges: [edge('page:logIn', 'substate:a', 'reads')],
      }),
    ),
  );
  const draw = html.slice(html.indexOf('function draw()'));
  assert.match(
    draw.slice(0, draw.indexOf('function ', 20)),
    /applyFocus\(\)/,
    'draw() re-applies the focus it just rebuilt the wires out of',
  );
  // And the ways the pointer can leave without a row saying so.
  assert.match(html, /pointerleave/);
  assert.match(html, /visibilitychange/);
});

test('the page it builds is JavaScript that actually parses', () => {
  // The webview's script is written inside a template literal, which means the
  // build has *two* levels of escaping and TypeScript checks neither: a lone
  // `\n` in a string became a real newline in the emitted script, inside a
  // string literal, and the whole page stopped parsing — a blank map, with
  // nothing anywhere saying why. Every other test here reads the page as text
  // and so could not see it.
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('logIn', '/login'), SUB('a', 'A'), SUB('b', 'B')],
        edges: [
          edge('page:logIn', 'substate:a', 'dispatches', 'onSubmit'),
          edge('page:logIn', 'substate:a', 'uses', 'email'),
          edge('substate:a', 'substate:b', 'reads'),
        ],
      }),
    ),
  );
  const script = /<script nonce="[^"]*">([\s\S]*?)<\/script>/.exec(html)?.[1];
  assert.ok(script, 'the page carries a script');
  assert.doesNotThrow(
    () => new vm.Script(script!),
    'the webview script must parse',
  );
});

test('the html is self-contained and script-safe', () => {
  const p = picture(
    graphOf({ nodes: [SUB('logIn', 'LogInState'), PAGE('logIn', '/login')] }),
  );
  const html = buildHtml(p);
  assert.match(html, /Content-Security-Policy/);
  assert.match(html, /script-src 'nonce-/);
  assert.ok(!/<script(?![^>]*nonce)/.test(html), 'every script carries the nonce');
});

test('a value that looks like markup cannot close the script', () => {
  const p = picture(
    graphOf({
      nodes: [{ id: 'page:x', kind: 'page', name: '</script><b>', path: '/x', file: '/x.dart' }],
    }),
  );
  const html = buildHtml(p);
  assert.ok(!html.includes('</script><b>'), 'the payload is escaped inside the JSON');
});
