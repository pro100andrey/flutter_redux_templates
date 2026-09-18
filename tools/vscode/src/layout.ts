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
//
// The actor column may be **nested**: a page holds the connectors it builds, and
// a connector the ones it builds. Nesting is a constraint on the order, not a
// separate layout — a built row follows its builder, and a builder is sorted by
// the barycenter of everything under it, so a screen and its regions move as one
// block. Handed as a child → builder map so a flat column is the same call with
// nothing nested, which is every call the picture used to make.

/** An edge between two drawn nodes, by id. Direction does not affect crossings. */
export interface LayoutEdge {
  from: string;
  to: string;
}

/**
 * The two column orders, and how many crossings they leave.
 *
 * `actors` is flat even when the column is nested: the rows top to bottom, each
 * builder immediately followed by what it builds. That is the order the crossing
 * count needs, and the one thing a nested drawing has to agree with it about;
 * re-nesting it is one pass with the same map that flattened it.
 */
export interface Ordering {
  actors: string[];
  state: string[];
  crossings: number;
}

/** A row and, beneath it, the rows it builds. */
interface Tree {
  id: string;
  built: Tree[];
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
 *
 * Counted as inversions, not by comparing every pair. This runs once per pass
 * of every restart — a few hundred times per picture — and a pairwise count is
 * quadratic in the edges, which is fine at twenty and not at a thousand. With
 * the spans sorted by their left end, a crossing is an earlier span whose right
 * end sits below this one's, and a Fenwick tree answers "how many inserted so
 * far sit below" in logarithmic time. Spans that share a left end are queried
 * together before any of them is inserted, since two edges leaving one row do
 * not cross each other; a shared right end is excluded by the strict query.
 * The spans travel as packed numbers in one typed array, so a count allocates
 * two arrays however many edges there are.
 */
export function countCrossings(
  actors: string[],
  state: string[],
  edges: readonly LayoutEdge[],
): number {
  const left = indexOf(actors);
  const right = indexOf(state);
  const width = state.length;
  const keys = new Float64Array(edges.length);
  let count = 0;
  for (const edge of edges) {
    const span = spanOf(edge, left, right, width);
    if (span >= 0) keys[count++] = span;
  }
  if (count < 2) return 0;
  const sorted = keys.subarray(0, count).sort();

  // 1-based Fenwick tree over right positions: `tree` holds partial counts of
  // the spans inserted so far, by where they land on the right.
  const tree = new Int32Array(width + 1);
  const insertedBelowOrAt = (b: number): number => {
    let sum = 0;
    for (let i = b + 1; i > 0; i -= i & -i) sum += tree[i];
    return sum;
  };
  const insert = (b: number): void => {
    for (let i = b + 1; i <= width; i += i & -i) tree[i]++;
  };

  let crossings = 0;
  let inserted = 0;
  let i = 0;
  while (i < count) {
    const a = Math.floor(sorted[i] / width);
    let j = i;
    for (; j < count && Math.floor(sorted[j] / width) === a; j++) {
      crossings += inserted - insertedBelowOrAt(sorted[j] - a * width);
    }
    for (let k = i; k < j; k++) insert(sorted[k] - a * width);
    inserted += j - i;
    i = j;
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
 *
 * `builtBy` nests the actor column: each entry is a row and the row it sits
 * under. A row whose builder is not in the column, or whose builders form a
 * cycle, is a root. Built rows are only ever moved among their siblings; a
 * builder is placed by the barycenter of its whole subtree.
 */
export function orderColumns(
  actors: readonly string[],
  state: readonly string[],
  edges: readonly LayoutEdge[],
  builtBy: ReadonlyMap<string, string> = new Map(),
): Ordering {
  const { across, along } = adjacency(actors, state, edges);
  const forest = forestOf(actors, builtBy);
  const under = idsUnder(forest);

  let bestActors = rowsOf(forest);
  let bestState = [...state];
  let best = countCrossings(bestActors, bestState, edges);

  // Restart 0 is the order we were handed, so the answer can never be worse than
  // it. The rest are shuffled, from a fixed seed — the result has to be a function
  // of the input alone, or the same picture would re-arrange itself every time it
  // was opened.
  const random = seededRandom();
  for (let restart = 0; restart < RESTARTS; restart++) {
    let currentForest = restart === 0 ? forest : shuffledForest(forest, random);
    let currentActors = rowsOf(currentForest);
    let currentState = restart === 0 ? [...state] : shuffled([...state], random);

    for (let pass = 0; pass < PASSES; pass++) {
      currentForest = sortForest(currentForest, currentState, across, along, under);
      currentActors = rowsOf(currentForest);
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
function shuffled<T>(items: T[], random: () => number): T[] {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
}

/** The forest with every sibling list shuffled, at every depth. A new tree. */
function shuffledForest(forest: readonly Tree[], random: () => number): Tree[] {
  return shuffled(
    forest.map((tree) => ({ id: tree.id, built: shuffledForest(tree.built, random) })),
    random,
  );
}

/**
 * The nesting `builtBy` actually yields over `actors`: each row that sits under
 * another, mapped to that row.
 *
 * Less than `builtBy` says. A builder outside the column is no builder, a row
 * cannot sit under itself, and a cycle has no top — two connectors that build
 * each other — so one of them has to be it: the first row met (in column order)
 * whose chain of builders comes back to it is cut loose, which is deterministic
 * and no worse than any other cut.
 *
 * Exported because the picture has to make the same cut: a `builds` relation the
 * nesting shows is not drawn as a line, and one the cut left out *is* — so the
 * question "does the nesting show this" has to have one answer, and this is it.
 */
export function nesting(
  actors: readonly string[],
  builtBy: ReadonlyMap<string, string>,
): Map<string, string> {
  const present = new Set(actors);
  const under = new Map<string, string>();
  for (const id of actors) {
    const builder = builtBy.get(id);
    if (builder !== undefined && present.has(builder) && builder !== id) {
      under.set(id, builder);
    }
  }
  for (const id of actors) {
    let at = under.get(id);
    while (at !== undefined && at !== id) at = under.get(at);
    if (at === id) under.delete(id);
  }
  return under;
}

/**
 * `actors` as a forest: roots in the order given, each row's built rows under it
 * in the order given. See [nesting] for which rows are roots.
 */
function forestOf(actors: readonly string[], builtBy: ReadonlyMap<string, string>): Tree[] {
  const under = nesting(actors, builtBy);
  const trees = new Map(actors.map((id) => [id, { id, built: [] as Tree[] }]));
  const roots: Tree[] = [];
  for (const id of actors) {
    const builder = under.get(id);
    const tree = trees.get(id)!;
    if (builder === undefined) roots.push(tree);
    else trees.get(builder)!.built.push(tree);
  }
  return roots;
}

/** The forest's rows top to bottom: each builder, then what it builds. */
function rowsOf(forest: readonly Tree[]): string[] {
  const rows: string[] = [];
  const walk = (tree: Tree) => {
    rows.push(tree.id);
    tree.built.forEach(walk);
  };
  forest.forEach(walk);
  return rows;
}

/**
 * Every id in each tree, the root included, by the tree's id — for every tree
 * at every depth of the forest.
 *
 * Computed once per ordering. The sweep rebuilds the forest on every pass, but
 * only the order of siblings changes, never what sits under what — and the
 * sort used to flatten each subtree again on every pass at every depth, which
 * is the one allocation in the loop that grew with the depth of the nesting.
 */
function idsUnder(forest: readonly Tree[]): Map<string, string[]> {
  const under = new Map<string, string[]>();
  const walk = (tree: Tree): string[] => {
    const ids = [tree.id];
    for (const built of tree.built) ids.push(...walk(built));
    under.set(tree.id, ids);
    return ids;
  };
  forest.forEach(walk);
  return under;
}

/**
 * The forest, siblings at every depth ordered by barycenter.
 *
 * A tree's key is the mean facing position over the across-neighbours of its
 * *whole* subtree — a page that reads nothing itself sits where the regions it
 * builds read. Same fallback as the flat sort: a tree with no across-neighbour
 * borrows the mean key of the rows it relates to along the column, and one with
 * neither sorts last among its siblings.
 */
function sortForest(
  forest: readonly Tree[],
  against: readonly string[],
  across: Map<string, string[]>,
  along: Map<string, string[]>,
  under: Map<string, string[]>,
): Tree[] {
  const facing = indexOf(against);

  const key = new Map<string, number>();
  for (const tree of forest) {
    const barycentre = meanOverNeighbours(under.get(tree.id)!, across, facing, (id) => id);
    if (barycentre !== null) key.set(tree.id, barycentre);
  }
  // The borrowed key comes off rows, and rows inside a sibling tree are that
  // sibling's business: a row linked along the column to one is keyed by the
  // sibling that holds it.
  const holder = new Map<string, string>();
  for (const tree of forest) for (const id of under.get(tree.id)!) holder.set(id, tree.id);
  for (const tree of forest) {
    if (key.has(tree.id)) continue;
    const borrowed = meanOverNeighbours(under.get(tree.id)!, along, key, (id) => {
      const held = holder.get(id);
      return held === tree.id ? undefined : held;
    });
    if (borrowed !== null) key.set(tree.id, borrowed);
  }

  return [...forest]
    .sort(
      (a, b) =>
        (key.get(a.id) ?? Number.POSITIVE_INFINITY) -
        (key.get(b.id) ?? Number.POSITIVE_INFINITY),
    )
    .map((tree) => ({
      id: tree.id,
      built: sortForest(tree.built, against, across, along, under),
    }));
}

/**
 * The mean of `values` over the neighbours (in `of`) of every id in `ids`,
 * each neighbour first passed through `as` — or null when none has a value.
 *
 * A neighbour `as` maps to undefined is skipped, which is how a tree keeps its
 * own rows out of its borrowed key. Summed in place: this is the inner loop of
 * the sweep, and it used to flatten the neighbours into a list, map that list,
 * filter it, and reduce it — four arrays per tree per pass.
 */
function meanOverNeighbours(
  ids: readonly string[],
  of: Map<string, string[]>,
  values: Map<string, number>,
  as: (neighbour: string) => string | undefined,
): number | null {
  let sum = 0;
  let known = 0;
  for (const id of ids) {
    const neighbours = of.get(id);
    if (!neighbours) continue;
    for (const neighbour of neighbours) {
      const at = as(neighbour);
      if (at === undefined) continue;
      const value = values.get(at);
      if (value === undefined) continue;
      sum += value;
      known++;
    }
  }
  return known === 0 ? null : sum / known;
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
  if (!of) return null;
  let sum = 0;
  let known = 0;
  for (const n of of) {
    const value = values.get(n);
    if (value === undefined) continue;
    sum += value;
    known++;
  }
  return known === 0 ? null : sum / known;
}

function indexOf(column: readonly string[]): Map<string, number> {
  return new Map(column.map((id, i) => [id, i]));
}

/**
 * An edge's span, packed as `left position × width + right position` — or -1
 * when the edge is not one per column. A number rather than a pair, so the
 * count's inner loop allocates nothing per edge.
 */
function spanOf(
  edge: LayoutEdge,
  left: Map<string, number>,
  right: Map<string, number>,
  width: number,
): number {
  const forward = left.get(edge.from);
  if (forward !== undefined) {
    const target = right.get(edge.to);
    return target === undefined ? -1 : forward * width + target;
  }
  const backward = left.get(edge.to);
  if (backward === undefined) return -1;
  const source = right.get(edge.from);
  return source === undefined ? -1 : backward * width + source;
}
