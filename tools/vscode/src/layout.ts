// Ordering the structural picture's two columns so its edges cross as little as
// possible.
//
// The picture is a two-layer drawing: things that act on state on the left, the
// state on the right, edges between them. For that shape the number of crossings
// is decided entirely by the *order* of each column — not by where the lines are
// drawn — and ordering each column by the mean position of its neighbours in the
// other is the standard heuristic for it (the barycenter sweep of a Sugiyama
// layered layout).
//
// It is worth its own module, pure and with no `vscode` import, because it is the
// part with a right answer and the part that carries the win: on this repository
// the same fourteen lines across the middle go from 44 crossings to two, by
// ordering alone. Counting crossings is how you test that, and counting needs no
// DOM.
//
// Same-column edges (a page navigating to a page, a substate read by another) do
// not count as crossings: both endpoints sit in one column, so they have no span
// across the middle to cross anything with — they are drawn out into that
// column's own margin instead. They still get a say in the *order*, or a node
// whose only relation is one of them would read as unconnected and sink to the
// bottom, stretching its margin arc down the whole column.

/** An edge between two drawn nodes, by id. Direction does not affect crossings. */
export interface LayoutEdge {
  from: string;
  to: string;
}

/** The two column orders, and how many crossings they leave. */
export interface Ordering {
  actors: string[];
  state: string[];
  crossings: number;
}

/** How many passes of one sweep to try. Well past the point it settles at this size. */
const PASSES = 16;

/**
 * How many starting orders to sweep from.
 *
 * The barycenter sweep finds a local minimum, and which one it finds depends
 * entirely on where it starts: from the alphabetical order this repository's shape
 * settles at 21 crossings, and from other starts the same sweep reaches **3**. The
 * cost of looking is nothing at this size — twenty nodes, a few dozen edges — and
 * the difference is the whole readability of the picture.
 */
const RESTARTS = 24;

/**
 * How many pairs of edges cross, given these two column orders.
 *
 * Two edges cross exactly when their endpoints run in opposite directions: one
 * starts above the other on the left and ends below it on the right. Edges whose
 * endpoints are not one per column are not part of a two-layer drawing and are
 * not counted.
 */
export function countCrossings(
  actors: string[],
  state: string[],
  edges: readonly LayoutEdge[],
): number {
  const left = indexOf(actors);
  const right = indexOf(state);
  const spans: Array<[number, number]> = [];
  for (const edge of edges) {
    const span = spanOf(edge, left, right);
    if (span) spans.push(span);
  }

  let crossings = 0;
  for (let i = 0; i < spans.length; i++) {
    for (let j = i + 1; j < spans.length; j++) {
      const [a1, b1] = spans[i];
      const [a2, b2] = spans[j];
      if ((a1 - a2) * (b1 - b2) < 0) crossings++;
    }
  }
  return crossings;
}

/**
 * Reorder both columns to reduce crossings, keeping every node.
 *
 * Sweeps back and forth: hold one column still, and sort the other by each
 * node's barycenter — the mean position of its neighbours. The sweep is **not
 * monotonic**, a pass can leave things worse than it found them, so the best
 * order seen is what comes back rather than the last one tried. That also makes
 * the result never worse than the order it was handed.
 *
 * A node with no edges has no barycenter. It keeps its incoming relative order,
 * at the end of its column: floating it into the middle would push connected
 * rows apart for nothing.
 */
export function orderColumns(
  actors: readonly string[],
  state: readonly string[],
  edges: readonly LayoutEdge[],
): Ordering {
  const { across, along } = adjacency(actors, state, edges);

  let bestActors = [...actors];
  let bestState = [...state];
  let best = countCrossings(bestActors, bestState, edges);

  // Restart 0 is the order we were handed, so the answer can never be worse than
  // it. The rest are shuffled, from a fixed seed — the result has to be a function
  // of the input alone, or the same picture would re-arrange itself every time it
  // was opened.
  const random = seededRandom();
  for (let restart = 0; restart < RESTARTS; restart++) {
    let currentActors =
      restart === 0 ? [...actors] : shuffled([...actors], random);
    let currentState = restart === 0 ? [...state] : shuffled([...state], random);

    for (let pass = 0; pass < PASSES; pass++) {
      currentActors = sortByBarycenter(currentActors, currentState, across, along);
      currentState = sortByBarycenter(currentState, currentActors, across, along);
      const crossings = countCrossings(currentActors, currentState, edges);
      // `<=` within a sweep, `<` across restarts. A swept order that ties is
      // still the better picture — that is the pass which sinks the edgeless rows
      // to the end — but a *later start* that merely ties has earned nothing, and
      // taking it would throw away the order closest to the one asked for.
      const better = restart === 0 ? crossings <= best : crossings < best;
      if (better) {
        best = crossings;
        bestActors = currentActors;
        bestState = currentState;
      }
      if (best === 0) break;
    }
    // Checked after the first sweep, never before it: arriving at zero crossings
    // does not mean the order is good, only that nothing crosses — the sweep is
    // still what sinks the edgeless rows out of the way.
    if (best === 0) break;
  }

  return { actors: bestActors, state: bestState, crossings: best };
}

/**
 * A deterministic pseudo-random source.
 *
 * A fixed seed rather than `Math.random`: the ordering must be a function of the
 * graph, so that re-opening the picture, or refreshing it after an unrelated edit,
 * does not silently rearrange every row. The generator is the standard 32-bit
 * multiplicative one — nothing here needs statistical quality, only repeatability.
 */
function seededRandom(): () => number {
  let state = 0x2f6e2b1;
  return () => {
    // `>>> 0`, not `%`: `Math.imul` returns a *signed* 32-bit result, and JS's
    // remainder keeps the sign — so the state went negative, the shuffle indexed
    // an array with it, and a node became `undefined`. Coerce to unsigned first.
    state = (Math.imul(state, 48271) + 11) >>> 0;
    return state / 0x100000000;
  };
}

/** `items`, shuffled in place and returned (Fisher-Yates). */
function shuffled(items: string[], random: () => number): string[] {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
}

/**
 * Each node's neighbours, either `across` the middle or `along` its own column.
 *
 * Both matter, for different reasons. Across is what decides crossings. Along is
 * what stops a node whose only relation is same-column — a page that merely
 * navigates to another — reading as unconnected and sinking to the bottom, which
 * would stretch its side channel down the whole column.
 */
function adjacency(
  actors: readonly string[],
  state: readonly string[],
  edges: readonly LayoutEdge[],
): { across: Map<string, string[]>; along: Map<string, string[]> } {
  const left = new Set(actors);
  const right = new Set(state);
  const across = new Map<string, string[]>();
  const along = new Map<string, string[]>();
  const link = (into: Map<string, string[]>, a: string, b: string) => {
    const of = into.get(a);
    if (of) of.push(b);
    else into.set(a, [b]);
  };
  for (const { from, to } of edges) {
    const bothKnown =
      (left.has(from) || right.has(from)) && (left.has(to) || right.has(to));
    if (!bothKnown) continue;
    // Whichever way round the edge points — a selector read by a page runs
    // state → actor, and it is the same relation to lay out.
    const into = left.has(from) !== left.has(to) ? across : along;
    link(into, from, to);
    link(into, to, from);
  }
  return { across, along };
}

/**
 * `column`, ordered by each node's mean position in `against`.
 *
 * A node with no neighbour across the middle takes the mean **key** of its
 * neighbours within this column — a page that only navigates to another sits
 * where that page sits. The key, not the position: a position in this column and
 * a position in the facing one are different coordinate spaces, and mixing them
 * puts the node anywhere at all whenever the two columns differ in length.
 *
 * With neither kind of neighbour it has no place to be near, and sorts past
 * everything that has one.
 *
 * A stable sort, so nodes that share a key keep the order they arrived in.
 */
function sortByBarycenter(
  column: readonly string[],
  against: readonly string[],
  across: Map<string, string[]>,
  along: Map<string, string[]>,
): string[] {
  const facing = indexOf(against);
  const key = new Map<string, number>();
  for (const node of column) {
    const barycentre = mean(across.get(node), facing);
    if (barycentre !== null) key.set(node, barycentre);
  }
  // Second pass, over the keys the first produced — so the borrowed value is on
  // the same scale as everything it will be compared with.
  for (const node of column) {
    if (key.has(node)) continue;
    const borrowed = mean(along.get(node), key);
    if (borrowed !== null) key.set(node, borrowed);
  }

  return [...column].sort(
    (a, b) =>
      (key.get(a) ?? Number.POSITIVE_INFINITY) -
      (key.get(b) ?? Number.POSITIVE_INFINITY),
  );
}

/** The mean of `of`'s values in `values`, or null when none of them have one. */
function mean(
  of: readonly string[] | undefined,
  values: Map<string, number>,
): number | null {
  const known = (of ?? []).filter((n) => values.has(n));
  if (known.length === 0) return null;
  return known.reduce((sum, n) => sum + values.get(n)!, 0) / known.length;
}

function indexOf(column: readonly string[]): Map<string, number> {
  return new Map(column.map((id, i) => [id, i]));
}

/** An edge's `[left position, right position]`, or null when it is not one per column. */
function spanOf(
  edge: LayoutEdge,
  left: Map<string, number>,
  right: Map<string, number>,
): [number, number] | null {
  const forward = left.get(edge.from);
  if (forward !== undefined) {
    const target = right.get(edge.to);
    return target === undefined ? null : [forward, target];
  }
  const backward = left.get(edge.to);
  if (backward === undefined) return null;
  const source = right.get(edge.from);
  return source === undefined ? null : [backward, source];
}

/** Where one end of an edge attaches: which of its node's edges it is, and of how many. */
export interface Anchor {
  slot: number;
  of: number;
}

/** Both ends of one edge. */
export interface EdgeAnchors {
  from: Anchor;
  to: Anchor;
}

/**
 * A slot for each end of each edge, so two relations leaving one node do not
 * leave from the same point.
 *
 * Every line used to start at a fixed offset from its node's top, which made two
 * relations out of one row a single stroke until they had drifted far enough
 * apart to tell — and made two relations *between the same pair* one line drawn
 * twice, indistinguishable anywhere.
 *
 * Ordered by the row the other end lands on, so a node's fan does not cross
 * itself: the edge going furthest up attaches highest. Ties — two relations
 * between the same pair — keep the order they arrived in, so each still gets its
 * own slot.
 *
 * Pure, and returns slots rather than pixels: how tall a row is, and therefore how
 * far apart the slots sit, is the drawing's business and only the DOM knows it.
 *
 * One pool per node, not one per side of it. An edge across the middle and one
 * into the margin leave on opposite sides and could share a slot without
 * colliding; giving them separate ones costs nothing and keeps them from starting
 * at the same height, which reads better where both meet the box.
 */
export function anchorSlots(
  edges: readonly LayoutEdge[],
  rowOf: (id: string) => number,
): EdgeAnchors[] {
  /** Each node's edge indices, ordered by where the other end lands. */
  const ends = new Map<string, number[]>();
  const attach = (node: string, index: number) => {
    const of = ends.get(node);
    if (of) of.push(index);
    else ends.set(node, [index]);
  };
  edges.forEach((edge, index) => {
    attach(edge.from, index);
    attach(edge.to, index);
  });

  const anchors: EdgeAnchors[] = edges.map(() => ({
    from: { slot: 0, of: 1 },
    to: { slot: 0, of: 1 },
  }));
  for (const [node, indices] of ends) {
    const other = (index: number) => {
      const edge = edges[index];
      return rowOf(edge.from === node ? edge.to : edge.from);
    };
    // A stable sort by the far row, so two relations between the same pair keep
    // their order and still take a slot each. The rows are compared rather than
    // subtracted: two ends both off the picture are both `Infinity`, and
    // `Infinity - Infinity` is `NaN`, which a comparator must never be handed.
    const ordered = indices
      .map((index, arrival) => ({ index, arrival, row: other(index) }))
      .sort((a, b) =>
        a.row === b.row ? a.arrival - b.arrival : a.row < b.row ? -1 : 1,
      );

    ordered.forEach(({ index }, slot) => {
      const end = edges[index].from === node ? 'from' : 'to';
      anchors[index][end] = { slot, of: ordered.length };
    });
  }
  return anchors;
}
