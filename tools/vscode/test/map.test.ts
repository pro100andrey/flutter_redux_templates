import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vm from 'node:vm';
import { buildHtml as htmlOf, picture } from '../src/map';
import type { AppGraph, GraphEdge, GraphNode } from '../src/queries';
import type { Picture, PictureNode } from '../src/map';

/**
 * The page's stylesheet and script, read from `media/map/` — where they live
 * now. They used to be a template literal inside `buildHtml`, and the tests
 * below read the page as one text; they still do, by putting the three back
 * together, so what each pins about the drawing is unchanged.
 */
const MEDIA = path.join(__dirname, '..', '..', 'media', 'map');
const CLIENT_CSS = fs.readFileSync(path.join(MEDIA, 'map.css'), 'utf8');
const CLIENT_JS = fs.readFileSync(path.join(MEDIA, 'map.js'), 'utf8');

/** The whole page as text: the skeleton `buildHtml` builds plus the two files it loads. */
const buildHtml = (p: Picture): string => htmlOf(p) + '\n' + CLIENT_CSS + '\n' + CLIENT_JS;

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

test('a gap names its file relative to the repo', () => {
  // The CLI names files absolutely; in a box of fixed width that broke
  // mid-word, and the repo-relative form is what the rest of the editor shows.
  const gap = {
    kind: 'dispatch-target',
    owner: 'page:logIn',
    at: '/repo/app/lib/connectors/log_in_page_connector.dart',
    why: 'no imported *_action.dart declares it',
  };
  assert.strictEqual(
    picture(graphOf({ unresolved: [gap] }), '/repo').gaps[0].at,
    'app/lib/connectors/log_in_page_connector.dart',
  );
  assert.strictEqual(
    picture(graphOf({ unresolved: [gap] })).gaps[0].at,
    gap.at,
    'and stays as it came when the root is unknown',
  );
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

test('every row says its kind, so the page can colour it', () => {
  const p = picture(
    graphOf({
      nodes: [
        SUB('logIn', 'LogInState'),
        PAGE('logIn', '/login'),
        CONSUMER('Bar'),
        { id: 'service:S', kind: 'service', name: 'S', file: '/s.dart' },
        { id: 'persistor:P', kind: 'persistor', name: 'P', file: '/p.dart' },
        ACTION('logIn', 'A'),
      ],
    }),
  );
  assert.deepStrictEqual(
    [...p.actors, ...p.state].map((n) => [n.title, n.kind]).sort(),
    [['Bar', 'consumer'], ['P', 'persistor'], ['S', 'service'], ['logIn', 'page'], ['logIn', 'substate']],
  );
  assert.strictEqual(p.state[0].owned[0].kind, 'action');
  assert.match(buildHtml(p), /\.node\.k-substate \{ border-left-color/);
});

test('a folded relation remembers the action or selector it ended on', () => {
  // "dispatches into logIn" is the shape; "dispatches LogInAction (onSubmit)"
  // is what a reader came to find out, and the line cannot say it.
  const p = picture(
    graphOf({
      nodes: [SUB('logIn', 'LogInState'), PAGE('logIn', '/login'), ACTION('logIn', 'A'), ACTION('logIn', 'B'), SELECTOR('logIn', 'email')],
      edges: [
        edge('page:logIn', 'action:logIn.A', 'dispatches', 'onSubmit'),
        edge('page:logIn', 'action:logIn.B', 'dispatches', 'onSubmit'),
        edge('page:logIn', 'selector:SelectlogIn.email', 'uses'),
        edge('page:logIn', 'substate:logIn', 'reads'),
      ],
    }),
  );
  assert.strictEqual(p.edges.length, 1, 'still one line');
  assert.deepStrictEqual(
    p.edges[0].relations.map((r) => [r.kind, r.via, r.through]),
    [
      ['dispatches', 'onSubmit', 'action:logIn.A'],
      ['dispatches', 'onSubmit', 'action:logIn.B'],
      ['uses', '', 'selector:SelectlogIn.email'],
      ['reads', '', undefined],
    ],
    'two actions behind one trigger are two relations; an edge already on the substate has none',
  );
});

test('an edge between two substates\' actions names the action dispatched', () => {
  // Both ends fold. The one the pane names is the target — what got
  // dispatched — not the action doing the dispatching, which used to win by
  // being first in the pair; and two targets are two relations.
  const p = picture(
    graphOf({
      nodes: [SUB('logIn', 'L'), SUB('session', 'S'), ACTION('logIn', 'LogInAction'), ACTION('session', 'SetTokenAction'), ACTION('session', 'ClearTokenAction')],
      edges: [
        edge('action:logIn.LogInAction', 'action:session.SetTokenAction', 'dispatches'),
        edge('action:logIn.LogInAction', 'action:session.ClearTokenAction', 'dispatches'),
      ],
    }),
  );
  assert.strictEqual(p.edges.length, 1);
  assert.deepStrictEqual(
    p.edges[0].relations.map((r) => r.through),
    ['action:session.SetTokenAction', 'action:session.ClearTokenAction'],
  );
});

test('an edge that folds onto a substate the picture does not draw is a gap, not a line', () => {
  // An action's substate is its folder; nothing checks AppState still
  // composes it. Drawn, the line had no row to end on and the page threw.
  const p = picture(
    graphOf({
      nodes: [PAGE('logIn', '/login'), ACTION('theme', 'SetThemeModeAction')],
      edges: [edge('page:logIn', 'action:theme.SetThemeModeAction', 'dispatches', 'onToggle')],
    }),
  );
  assert.deepStrictEqual(p.edges, []);
  assert.strictEqual(p.gaps.length, 1);
  assert.match(p.gaps[0].what, /action:theme\.SetThemeModeAction/);
  assert.match(p.gaps[0].why, /substate:theme/);
});

test('a line is coloured by what it does to state', () => {
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('logIn', '/login'), SUB('a', 'A')],
        edges: [edge('page:logIn', 'substate:a', 'dispatches'), edge('page:logIn', 'substate:a', 'uses')],
      }),
    ),
  );
  // Which lines carry the class is the page's business, pinned in
  // map_page.test.ts; the colour the class means is the stylesheet's.
  assert.match(html, /path\.wire\.changes \{ stroke: var\(--changes\)/);
  assert.match(html, /path\.wire \{ pointer-events: stroke; \}/, 'and its tooltip can be reached');
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
  // needs no per-element bookkeeping beyond one class. Which rows and wires
  // get the class, and when, is the page's: map_page.test.ts.
  assert.match(html, /#board\.focusing[^{]*:not\(\.lit\)/);
  // Dimmed by the row's own head, not the row: a box also holds what it
  // builds, and opacity on the box would dim a lit row inside an unlit one.
  assert.match(html, /\.node:not\(\.lit\) > \.head/);
});

const CONSUMER = (name: string): GraphNode => ({
  id: `consumer:${name}`,
  kind: 'consumer',
  name,
  file: `/repo/app/lib/connectors/${name}.dart`,
});

/** The actor rows top to bottom, each with its depth. */
const outline = (nodes: PictureNode[], depth = 0): [string, number][] =>
  nodes.flatMap((n) => [[n.title, depth] as [string, number], ...outline(n.built, depth + 1)]);

test('a connector sits under the row that builds it, and the line is gone', () => {
  // Composition is the one relation the picture says by nesting. On a real
  // console app it was twenty-five lines down the left margin, and the one
  // relation least worth a line: a region is *inside* its screen.
  const p = picture(
    graphOf({
      nodes: [PAGE('console', '/'), CONSUMER('SidebarConnector'), CONSUMER('ProjectPicker'), SUB('a', 'A')],
      edges: [
        edge('page:console', 'consumer:SidebarConnector', 'builds'),
        edge('consumer:SidebarConnector', 'consumer:ProjectPicker', 'builds'),
        edge('consumer:ProjectPicker', 'substate:a', 'uses', 'projects'),
      ],
    }),
  );
  assert.deepStrictEqual(outline(p.actors), [
    ['console', 0],
    ['SidebarConnector', 1],
    ['ProjectPicker', 2],
  ]);
  assert.deepStrictEqual(
    p.edges.map(relation),
    [{ from: 'consumer:ProjectPicker', to: 'substate:a', kind: 'uses', via: 'projects', side: 'across' }],
    'what the nested row does to state is still a line; what builds it is not',
  );
});

test('a row built by two things sits under one and keeps a line to the other', () => {
  // A page constructs a region, and so does a bar inside that page. The row can
  // only be in one place; the second builder is the relation the nesting cannot
  // say, so it stays a wire.
  const p = picture(
    graphOf({
      nodes: [PAGE('console', '/'), CONSUMER('StatusBar'), CONSUMER('Embedder')],
      edges: [
        edge('page:console', 'consumer:StatusBar', 'builds'),
        edge('page:console', 'consumer:Embedder', 'builds'),
        edge('consumer:StatusBar', 'consumer:Embedder', 'builds'),
      ],
    }),
  );
  assert.deepStrictEqual(outline(p.actors), [
    ['console', 0],
    ['Embedder', 1],
    ['StatusBar', 1],
  ]);
  assert.deepStrictEqual(p.edges.map(relation), [
    { from: 'consumer:StatusBar', to: 'consumer:Embedder', kind: 'builds', via: '', side: 'left' },
  ]);
});

test('two connectors that build each other still both appear, once', () => {
  // There is no top to a cycle; one of them has to be it. What must not happen
  // is a row vanishing, or appearing twice, or the ordering and the drawing
  // disagreeing about which is under which.
  const p = picture(
    graphOf({
      nodes: [CONSUMER('A'), CONSUMER('B')],
      edges: [edge('consumer:A', 'consumer:B', 'builds'), edge('consumer:B', 'consumer:A', 'builds')],
    }),
  );
  const rows = outline(p.actors);
  assert.deepStrictEqual(rows.map(([t]) => t).sort(), ['A', 'B']);
  assert.deepStrictEqual(rows.map(([, d]) => d), [0, 1], 'one is the root, the other under it');
  assert.strictEqual(p.edges.length, 1, 'the builder-of-the-root relation keeps its line');
});

test('a screen is ordered by what its regions read, not only by what it reads', () => {
  // The page itself reads nothing. Its regions read `s2`; an unrelated actor
  // reads `s1`. The page and its regions must move as one block to sit level
  // with `s2`, which is the barycenter of the subtree rather than of the row.
  const p = picture(
    graphOf({
      nodes: [
        PAGE('a', '/a'), CONSUMER('Region'), PAGE('b', '/b'),
        SUB('s1', 'S1'), SUB('s2', 'S2'),
      ],
      edges: [
        edge('page:a', 'consumer:Region', 'builds'),
        edge('consumer:Region', 'substate:s2', 'uses'),
        edge('page:b', 'substate:s1', 'uses'),
      ],
    }),
  );
  assert.strictEqual(p.crossings, 0);
  const rows = outline(p.actors).map(([t]) => t);
  const facing = p.state.map((n) => n.title);
  assert.strictEqual(
    rows.indexOf('a') < rows.indexOf('b'),
    facing.indexOf('s2') < facing.indexOf('s1'),
    'the block holding the region faces the substate the region reads',
  );
  assert.strictEqual(rows.indexOf('Region'), rows.indexOf('a') + 1, 'and the region stays under its page');
});

test('the shorter column is placed level with what it relates to', () => {
  // Thirty-four rows facing nine put every line on a long diagonal into a short
  // stack, bundled into a rope beside the taller column. The order was right;
  // the heights were not.
  const html = buildHtml(
    picture(
      graphOf({
        nodes: [PAGE('a', '/a'), PAGE('b', '/b'), SUB('s', 'S')],
        edges: [edge('page:a', 'substate:s', 'uses'), edge('page:b', 'substate:s', 'uses')],
      }),
    ),
  );
  // The placement itself needs a layout engine and has none here; what the
  // stylesheet promises it — rows taken out of flow inside their column —
  // can be read.
  assert.match(html, /\.rows\.placed > \.node \{ position: absolute/);
});

test('the page\'s script is JavaScript that actually parses', () => {
  // The webview's script used to be written inside a template literal, which
  // meant the build had *two* levels of escaping and TypeScript checked
  // neither: a lone `\n` in a string became a real newline in the emitted
  // script, inside a string literal, and the whole page stopped parsing — a
  // blank map, with nothing anywhere saying why. It is TypeScript now
  // (src/page/map.ts), compiled to the file the page loads, and this parses
  // that file: the one thing a type check of the source cannot say about
  // its output.
  assert.doesNotThrow(() => new vm.Script(CLIENT_JS), 'media/map/map.js must parse');
  // And the page reaches it: the data block it reads, and the script itself.
  const html = htmlOf(
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
  assert.match(html, /<script type="application\/json" id="picture"/);
  assert.match(CLIENT_JS, /getElementById\('picture'\)\.textContent/);
  assert.match(html, /<script nonce="[^"]+" src="[^"]*map\.js"><\/script>/);
});

test('the page loads its stylesheet and script by the URIs it is given, under the nonce', () => {
  // `buildHtml` is pure in its three inputs, which is what lets this be read:
  // the same picture, assets and nonce give the same page.
  const p = picture(graphOf({ nodes: [SUB('logIn', 'LogInState'), PAGE('logIn', '/login')] }));
  const assets = {
    css: 'vscode-resource://ext/media/map/map.css',
    js: 'vscode-resource://ext/media/map/map.js',
    cspSource: 'vscode-resource://ext',
  };
  const html = htmlOf(p, assets, 'N0NCE');
  assert.strictEqual(html, htmlOf(p, assets, 'N0NCE'), 'pure');
  assert.match(html, /<link rel="stylesheet" href="vscode-resource:\/\/ext\/media\/map\/map\.css" \/>/);
  assert.match(html, /<script nonce="N0NCE" src="vscode-resource:\/\/ext\/media\/map\/map\.js"><\/script>/);
  assert.match(html, /style-src vscode-resource:\/\/ext;/, 'the stylesheet origin is allowed by the policy');
  assert.match(html, /script-src 'nonce-N0NCE';/);
  // The picture travels as data, not as code: a JSON block the script parses.
  const block = /<script type="application\/json" id="picture" nonce="N0NCE">([\s\S]*?)<\/script>/.exec(html);
  assert.ok(block, 'the page carries the picture as a JSON block');
  const parsed = JSON.parse(block![1]);
  assert.deepStrictEqual(
    parsed.state.map((n: PictureNode) => n.title),
    ['logIn'],
  );
  assert.strictEqual(parsed.crossings, undefined, 'what the ordering achieved is not drawn');
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
