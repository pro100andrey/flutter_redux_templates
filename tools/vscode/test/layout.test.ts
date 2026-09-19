import { test } from 'node:test';
import * as assert from 'node:assert';
import { countCrossings, nesting, orderColumns } from '../src/layout';
import type { LayoutEdge } from '../src/layout';

/// Ordering the picture's two columns.
///
/// The part with a right answer, and the part that carries the win: against the
/// live monorepo's shape the same lines go from 44 crossings to a handful, by
/// ordering alone. Testable by counting, with no editor, webview or DOM — which
/// is why it is a pure function rather than a step inside the renderer.

const e = (from: string, to: string): LayoutEdge => ({ from, to });

test('countCrossings: two edges that swap order cross', () => {
  // a1→s2 and a2→s1, drawn between two ordered columns, must cross exactly once.
  assert.strictEqual(
    countCrossings(['a1', 'a2'], ['s1', 's2'], [e('a1', 's2'), e('a2', 's1')]),
    1,
  );
});

test('countCrossings: two edges in the same order do not', () => {
  assert.strictEqual(
    countCrossings(['a1', 'a2'], ['s1', 's2'], [e('a1', 's1'), e('a2', 's2')]),
    0,
  );
});

test('countCrossings: direction does not matter, position does', () => {
  // The picture draws `substate → page` edges too (a selector read by a page).
  // A crossing is a fact about where the endpoints sit, not about which way the
  // arrow points.
  assert.strictEqual(
    countCrossings(['a1', 'a2'], ['s1', 's2'], [e('s2', 'a1'), e('a2', 's1')]),
    1,
  );
});

test('countCrossings: an edge to a node in neither column is not counted', () => {
  // A same-column edge has both endpoints on one side, so it has no span across
  // the middle and nothing to cross. Where it is *drawn* is a separate question.
  assert.strictEqual(
    countCrossings(['a1', 'a2'], ['s1'], [e('a1', 'a2'), e('a1', 's1')]),
    0,
  );
});

test('orderColumns: untangles a fully reversed bipartite graph', () => {
  const actors = ['a1', 'a2', 'a3'];
  const state = ['s1', 's2', 's3'];
  const edges = [e('a1', 's3'), e('a2', 's2'), e('a3', 's1')];
  assert.strictEqual(countCrossings(actors, state, edges), 3, 'tangled to begin with');

  const ordered = orderColumns(actors, state, edges);
  assert.strictEqual(countCrossings(ordered.actors, ordered.state, edges), 0);
  assert.strictEqual(ordered.crossings, 0, 'it reports what it achieved');
});

test('orderColumns: never returns a worse order than it was given', () => {
  // The barycenter sweep is not monotonic — a pass can make things worse — so the
  // best order seen is what comes back, not the last one tried.
  const actors = ['a1', 'a2'];
  const state = ['s1', 's2'];
  const edges = [e('a1', 's1'), e('a2', 's2')];
  const before = countCrossings(actors, state, edges);
  const ordered = orderColumns(actors, state, edges);
  assert.ok(ordered.crossings <= before);
});

test('orderColumns: keeps every node, exactly once', () => {
  const actors = ['a1', 'a2', 'lonely'];
  const state = ['s1', 's2'];
  const ordered = orderColumns(actors, state, [e('a1', 's2'), e('a2', 's1')]);
  assert.deepStrictEqual([...ordered.actors].sort(), ['a1', 'a2', 'lonely']);
  assert.deepStrictEqual([...ordered.state].sort(), ['s1', 's2']);
});

test('orderColumns: a node with no edges sinks to the end, keeping its order', () => {
  // Given no neighbours it has no barycenter, so it sorts past everything that
  // has one: floating an edgeless row between connected ones pushes them apart
  // for nothing. Among themselves the edgeless keep the order they arrived in —
  // the caller hands them over sorted by name, so that is what stays.
  const ordered = orderColumns(
    ['alpha', 'connected', 'zeta'],
    ['s1'],
    [e('connected', 's1')],
  );
  assert.deepStrictEqual(ordered.actors, ['connected', 'alpha', 'zeta']);
});

test('orderColumns: it sweeps even when nothing crosses yet', () => {
  // The tie case. Accepting only a strict improvement would return a
  // crossing-free graph exactly as it arrived, edgeless rows and all.
  const ordered = orderColumns(['idle', 'a1'], ['s1'], [e('a1', 's1')]);
  assert.deepStrictEqual(ordered.actors, ['a1', 'idle']);
  assert.strictEqual(ordered.crossings, 0);
});

test('orderColumns: every node survives a shape that needs many restarts', () => {
  // The restarts only run while crossings remain, so a shape that untangles at
  // once never shuffles anything. This one cannot reach zero, so it exercises the
  // shuffling — where a signed pseudo-random state once produced a negative index
  // and dropped a node out of the picture entirely.
  const actors = ['a1', 'a2', 'a3', 'a4', 'a5'];
  const state = ['s1', 's2', 's3', 's4', 's5'];
  const edges = actors.flatMap((a) => state.map((s) => e(a, s)));
  const ordered = orderColumns(actors, state, edges);
  assert.ok(ordered.crossings > 0, 'a complete graph cannot be untangled');
  assert.deepStrictEqual([...ordered.actors].sort(), actors);
  assert.deepStrictEqual([...ordered.state].sort(), state);
  assert.ok(
    ordered.actors.every((id) => typeof id === 'string'),
    'no node fell out of the ordering',
  );
});

test('orderColumns: a node linked only within its column sits by its partner', () => {
  // A page that merely navigates to another has no neighbour across the middle
  // and so no barycenter of its own. Sinking it to the bottom with the genuinely
  // unconnected would stretch the side channel across the whole column; it
  // belongs beside the page it navigates to.
  // `idle` comes first in the input, so a stable sort that treats both as
  // barycenter-less would leave it above `navigatesOnly`. Getting this right
  // means moving `navigatesOnly` up beside `reader` — *which* side of it is the
  // solver's business, adjacency is the property.
  const ordered = orderColumns(['idle', 'navigatesOnly', 'reader'], ['s1'], [
    e('reader', 's1'),
    e('navigatesOnly', 'reader'), // same column: navigation
  ]);
  const at = (id: string) => ordered.actors.indexOf(id);
  assert.strictEqual(Math.abs(at('navigatesOnly') - at('reader')), 1, 'they are neighbours');
  assert.strictEqual(at('idle'), 2, 'the genuinely unconnected row is last');
});

test('orderColumns: borrowing a place uses the partner\'s key, not its row', () => {
  // A position in this column and a position in the facing one are different
  // coordinate spaces. Mixing them put the node anywhere at all as soon as the
  // columns differed in length — here twelve against three.
  const actors = [
    'a1', 'a2', 'a3', 'a4', 'mid', 'b1', 'b2', 'b3', 'c1', 'c2', 'c3', 'navOnly',
  ];
  const ordered = orderColumns(actors, ['s1', 's2', 's3'], [
    e('a1', 's1'), e('a2', 's1'), e('a3', 's1'), e('a4', 's1'),
    e('mid', 's2'),
    e('b1', 's3'), e('b2', 's3'), e('b3', 's3'),
    e('c1', 's3'), e('c2', 's3'), e('c3', 's3'),
    e('navOnly', 'mid'), // same column, and its only relation
  ]);
  const gap = Math.abs(ordered.actors.indexOf('navOnly') - ordered.actors.indexOf('mid'));
  assert.strictEqual(gap, 1, `navOnly should sit next to mid, was ${gap} rows away`);
});

test('orderColumns: a same-column link does not count as a crossing', () => {
  // It never spans the middle, so it has nothing to cross.
  assert.strictEqual(
    orderColumns(['a1', 'a2'], ['s1'], [e('a1', 'a2'), e('a1', 's1')]).crossings,
    0,
  );
});

test('orderColumns: an empty picture is not a special case for the caller', () => {
  const ordered = orderColumns([], [], []);
  assert.deepStrictEqual(ordered, { actors: [], state: [], crossings: 0 });
});

test('orderColumns: it is a function of the input, not of call order', () => {
  const actors = ['a1', 'a2', 'a3'];
  const state = ['s1', 's2', 's3'];
  const edges = [e('a1', 's3'), e('a2', 's1'), e('a3', 's2')];
  assert.deepStrictEqual(orderColumns(actors, state, edges), orderColumns(actors, state, edges));
});

test('the live monorepo shape: 44 crossings become a handful', () => {
  // The shape `frx graph --json` folds to on this repository, written out rather
  // than read from it: the test then says what it is about, and cannot go quiet
  // when the app gains a page. Both columns are seeded by **name**, which is how
  // `picture()` hands them over — seeding by id measures a layout nobody sees.
  //
  // One entry per *pair*: several relations between two rows are one line, so the
  // layout sees fourteen across the middle and six alongside, not thirty.
  const actors = [
    'consumer:AppConnector',
    'persistor:AppPersistor',
    'service:ConnectivityDispatcher',
    'page:forgotPassword',
    'page:home',
    'page:logIn',
    'page:registration',
    'page:resetPassword',
    'page:splash',
    'consumer:TopLevelPageConnector',
  ];
  const state = [
    'substate:connectivity',
    'substate:forgotPassword',
    'substate:language',
    'substate:logIn',
    'substate:registration',
    'substate:resetPassword',
    'substate:session',
    'substate:theme',
    'substate:wait',
  ];
  const edges = [
    e('consumer:AppConnector', 'substate:language'),
    e('consumer:AppConnector', 'substate:theme'),
    e('consumer:TopLevelPageConnector', 'substate:connectivity'),
    e('consumer:TopLevelPageConnector', 'substate:logIn'),
    e('consumer:TopLevelPageConnector', 'substate:registration'),
    e('page:forgotPassword', 'substate:forgotPassword'),
    e('page:logIn', 'substate:logIn'),
    e('page:logIn', 'substate:theme'),
    e('page:registration', 'substate:registration'),
    e('page:resetPassword', 'substate:resetPassword'),
    e('persistor:AppPersistor', 'substate:language'),
    e('persistor:AppPersistor', 'substate:session'),
    e('persistor:AppPersistor', 'substate:theme'),
    e('service:ConnectivityDispatcher', 'substate:connectivity'),
  ];
  // The six that join two rows of one column: navigation between pages, and
  // substates read by other substates. They cross nothing — but they steer the
  // order, so a shape measured without them is not this shape.
  const alongside = [
    e('page:logIn', 'page:forgotPassword'),
    e('page:logIn', 'page:registration'),
    e('substate:forgotPassword', 'substate:wait'),
    e('substate:logIn', 'substate:wait'),
    e('substate:registration', 'substate:wait'),
    e('substate:resetPassword', 'substate:wait'),
  ];

  assert.strictEqual(
    countCrossings(actors, state, edges),
    44,
    'the order the picture used to draw really did leave 44 crossings',
  );

  const ordered = orderColumns(actors, state, [...edges, ...alongside]);
  // Two, and pinned at two: the ordering is deterministic, and this is the number
  // the extension README quotes. A change to the sweep that costs crossings should
  // have to say so here.
  assert.ok(
    ordered.crossings <= 2,
    `ordering should leave two crossings, got ${ordered.crossings}`,
  );
  assert.strictEqual(
    countCrossings(ordered.actors, ordered.state, edges),
    ordered.crossings,
    'the count it reports is the count its own order produces',
  );

  // Not asserted here: that pages which navigate to each other end up adjacent.
  // A same-column relation only places a row that has *no* relation across the
  // middle — where it would otherwise sink to the bottom — because crossings are
  // what the ordering is for, and pulling a row toward its navigation partner
  // would trade them away. That narrower guarantee has its own case above.
});

// --- nesting: a built row follows its builder ---------------------------------

test('orderColumns: a built row follows its builder, wherever the builder goes', () => {
  // `a1` builds `r`; `r` reads `s2`, `a2` reads `s1`. Alphabetical order puts
  // `a1 a2 r` against `s1 s2` — one crossing. Free ordering would fix it by
  // moving `r` alone; nested, `r` may only move with `a1`.
  const builtBy = new Map([['r', 'a1']]);
  const ordered = orderColumns(['a1', 'a2', 'r'], ['s1', 's2'], [e('r', 's2'), e('a2', 's1')], builtBy);
  assert.strictEqual(ordered.crossings, 0);
  assert.strictEqual(
    ordered.actors.indexOf('r'),
    ordered.actors.indexOf('a1') + 1,
    'the built row is directly under its builder',
  );
});

test('orderColumns: a builder is placed by the barycenter of its whole subtree', () => {
  // The builder itself has no edge across. Its key must come from what it
  // builds, or the block would sink to the end as edgeless and drag `r` with it.
  const builtBy = new Map([['r', 'page']]);
  const ordered = orderColumns(
    ['idle', 'page', 'r', 'other'],
    ['s1', 's2'],
    [e('r', 's1'), e('other', 's2')],
    builtBy,
  );
  assert.deepStrictEqual(ordered.actors, ['page', 'r', 'other', 'idle']);
  assert.strictEqual(ordered.crossings, 0);
});

test('orderColumns: siblings are ordered among themselves', () => {
  const builtBy = new Map([['r1', 'page'], ['r2', 'page']]);
  const ordered = orderColumns(
    ['page', 'r1', 'r2'],
    ['s1', 's2'],
    [e('r1', 's2'), e('r2', 's1')],
    builtBy,
  );
  assert.strictEqual(ordered.crossings, 0);
  assert.strictEqual(ordered.actors[0], 'page');
});

test('orderColumns: a builder outside the column is no builder', () => {
  const ordered = orderColumns(['a'], ['s'], [e('a', 's')], new Map([['a', 'ghost']]));
  assert.deepStrictEqual(ordered.actors, ['a']);
});

test('orderColumns: a build cycle is cut, and every row survives it', () => {
  // `a` is built by `b`, `b` by `c`, `c` by `a`. The first row met is cut loose
  // and heads the block; what is left is a chain, `a` builds `c` builds `b`.
  const builtBy = new Map([['a', 'b'], ['b', 'c'], ['c', 'a']]);
  const ordered = orderColumns(['a', 'b', 'c'], ['s'], [e('b', 's')], builtBy);
  assert.deepStrictEqual(ordered.actors, ['a', 'c', 'b']);
  assert.deepStrictEqual(
    [...nesting(['a', 'b', 'c'], builtBy)],
    [['b', 'c'], ['c', 'a']],
    'and the nesting says the same, so the picture can drop the same lines',
  );
});

test('orderColumns: with nothing nested, the map changes nothing', () => {
  const actors = ['a1', 'a2', 'a3'];
  const state = ['s1', 's2', 's3'];
  const edges = [e('a1', 's3'), e('a2', 's2'), e('a3', 's1')];
  assert.deepStrictEqual(
    orderColumns(actors, state, edges, new Map()),
    orderColumns(actors, state, edges),
  );
});

test('countCrossings: agrees with the pairwise definition on random pictures', () => {
  // The count is an inversion count over a Fenwick tree; the definition is
  // "pairs whose endpoints run in opposite directions". Checked against each
  // other on pictures with shared endpoints (two edges leaving one row never
  // cross, nor two landing on one), same-column edges and edges to nowhere —
  // the cases where a strict-versus-loose slip would not show on a hand-drawn
  // example.
  let seed = 7;
  const random = () => {
    seed = (seed * 48271) % 2147483647;
    return seed / 2147483647;
  };
  const pairwise = (actors: string[], state: string[], edges: LayoutEdge[]): number => {
    const left = new Map(actors.map((id, i) => [id, i]));
    const right = new Map(state.map((id, i) => [id, i]));
    const spans: [number, number][] = [];
    for (const { from, to } of edges) {
      const a = left.get(from) ?? left.get(to);
      const b = right.get(to) ?? right.get(from);
      if (a !== undefined && b !== undefined && left.has(from) !== left.has(to)) spans.push([a, b]);
    }
    let crossings = 0;
    for (let i = 0; i < spans.length; i++) {
      for (let j = i + 1; j < spans.length; j++) {
        if ((spans[i][0] - spans[j][0]) * (spans[i][1] - spans[j][1]) < 0) crossings++;
      }
    }
    return crossings;
  };
  for (let round = 0; round < 200; round++) {
    const actors = Array.from({ length: 1 + Math.floor(random() * 8) }, (_, i) => `a${i}`);
    const state = Array.from({ length: 1 + Math.floor(random() * 8) }, (_, i) => `s${i}`);
    const pool = [...actors, ...state, 'nowhere'];
    const pick = () => pool[Math.floor(random() * pool.length)];
    const edges = Array.from({ length: Math.floor(random() * 30) }, () => e(pick(), pick()));
    assert.strictEqual(
      countCrossings(actors, state, edges),
      pairwise(actors, state, edges),
      `round ${round}: ${JSON.stringify(edges)}`,
    );
  }
});

test('nesting: a row whose builders go round a cycle it is not on keeps its builder', () => {
  // `a` is built by `b`; `b` and `c` build each other. Walking `a`'s chain
  // of builders never comes back to `a`, and used to never come back at all —
  // the Map froze the extension host on the picture that has this shape.
  // `a` stays under `b`; the cycle is cut at `b`, the first of its rows met.
  const under = nesting(['a', 'b', 'c'], new Map([['a', 'b'], ['b', 'c'], ['c', 'b']]));
  assert.deepStrictEqual([...under], [['a', 'b'], ['c', 'b']]);
  const ordered = orderColumns(['a', 'b', 'c'], ['s'], [e('a', 's')], new Map([['a', 'b'], ['b', 'c'], ['c', 'b']]));
  assert.deepStrictEqual([...ordered.actors].sort(), ['a', 'b', 'c'], 'and the ordering keeps every row');
});
