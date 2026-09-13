// FRX Map — the app's structure, drawn from the wiring graph.
//
// Its purpose is **orientation**: arriving in unfamiliar code and seeing how the
// app is put together. It used to read two flat lists and draw two hub-and-spoke
// diagrams — strictly less than the tree already shows, in a heavier container.
// But the poverty was in the *data source*, not in the idea of a picture: one
// `frx graph --json` read carries substates, their actions and selectors,
// services, the persistor, consumer connectors and every edge between them, and
// that data had no visual form at all.
//
// **Legibility comes from a skeleton, not from filtering.** Substates and pages
// are always visible and form the shape of "how it is built"; actions and
// selectors collapse into counts on their owner and expand on demand. The count
// of substates and pages grows slowly as an app grows while the count of actions
// and selectors grows fast, and that asymmetry is what keeps the view readable at
// ten times this template's size — where an overview matters most and drawing
// everything degenerates into a hairball.
//
// **Composition is nesting, not wires.** A screen is built out of connectors, and
// those out of more: on a real console app that is one page, twenty-six
// connectors and twenty-five `builds` edges — drawn as lines they were a rope
// down the left margin, and the one relation the eye could follow least was the
// one that says how the screen is put together. A built row now sits indented
// under its builder, and the line is gone. What remains a wire is what a row does
// to state, and to other rows it does not build.
//
// **Two surfaces, one stated division:**
//
//   The tree is an actionable inventory of what exists.
//   The picture is the relationships between what exists.
//
// So **hygiene marks are not shown here.** "Nothing dispatches this" describes an
// absence of relationships and belongs to the tree, which has a row to hang it
// on. **Unresolved edges are** shown: a diagram reads as exhaustive, so it owes
// the reader a statement of where its own edges are incomplete.
//
// No CLI change was needed to build this — the graph output already carries each
// action's and selector's owning substate, and each substate's state file.
import * as crypto from 'crypto';
import * as vscode from 'vscode';

import * as frx from './frx';
import * as paths from './paths';
import * as queries from './queries';
import { nesting, orderColumns } from './layout';
import type { AppGraph, GraphNode } from './queries';
import { selectionAt } from './tree';

/** One drawable node: what it says, and what opening it reveals. */
export interface PictureNode {
  id: string;
  /** The graph's kind — `page`, `consumer`, `service`, `persistor`, `substate`, `action`, `selector`. */
  kind: string;
  title: string;
  subtitle: string;
  file: string | null;
  line?: number;
  column?: number;
  /** What it owns, collapsed — shown as a count, expanded on demand. */
  owned: PictureNode[];
  /** What it builds — drawn nested under it, in place of a `builds` wire. */
  built: PictureNode[];
}

/** Which way an edge is routed. */
type Side = 'across' | 'left' | 'right';

/** One relation between two nodes: what kind, what triggers it, which way it runs. */
interface Relation {
  kind: string;
  /** A view-model callback, a `copyWith` field list, a getter name — or ''. */
  via: string;
  /** True when it runs against the direction the line is drawn in. */
  reversed: boolean;
  /**
   * The action or selector the relation actually ends on, when the fold moved
   * the end to its substate — the id of a node in that substate's `owned`. The
   * line does not need it; the pane does: "dispatches into logIn" is the shape,
   * "dispatches LogInAction (onSubmit)" is what a reader came to find out.
   */
  through?: string;
}

/**
 * A line between two drawn nodes, carrying every relation between them.
 *
 * **One line per pair, not per relation.** A page that both dispatches into a
 * substate and reads it is two relations with the same two endpoints; drawn
 * separately they lie exactly on top of each other — indistinguishable anywhere,
 * and doubling every crossing they take part in. Direction is folded in too: the
 * picture draws no arrowheads, so two pages that navigate to each other are one
 * stroke, and saying it twice says nothing twice.
 */
interface PictureEdge {
  from: string;
  to: string;
  relations: Relation[];
  /**
   * `across` the middle, or out into the margin on its own side.
   *
   * Decided here rather than in the webview so it can be tested, and so the
   * drawing stays a drawing. An edge joining two nodes of one column has no
   * business crossing the middle: drawn straight it leaves a node's right edge
   * and enters a neighbour's left edge in the *same* column, looping across the
   * whole canvas and crossing everything in between.
   */
  side: Side;
}

/** What the webview draws. */
export interface Picture {
  /**
   * Everything that acts on state: pages, services, the persistor, consumers.
   *
   * The roots only — a connector something here builds is under its builder's
   * `built`, however deep, and appears nowhere else.
   */
  actors: PictureNode[];
  /** The state itself: the substates. */
  state: PictureNode[];
  edges: PictureEdge[];
  /** Where the picture's own edges are incomplete. */
  gaps: {
    /** The kind of gap and the expression that hit it. */
    what: string;
    /** The file, relative to the repo when the root is known — or ''. */
    at: string;
    why: string;
  }[];
  /** How many pairs of edges cross the middle, after ordering. */
  crossings: number;
}

/** Node kinds that act on state rather than being state. */
const ACTOR_KINDS = new Set(['page', 'service', 'persistor', 'consumer']);

/** Node kinds that belong to a substate and collapse into it. */
const OWNED_KINDS = new Set(['action', 'selector']);

let panel: vscode.WebviewPanel | null = null;

/** Open (or reveal) the FRX Map and draw the current structure. */
export async function showMap(context: vscode.ExtensionContext): Promise<void> {
  const root = paths.findWorkspaceRoot();
  if (!root) {
    vscode.window.showErrorMessage('FRX: open the monorepo to see the map.');
    return;
  }
  const inv = await frx.resolveFrx(context, root);
  if (!inv) {
    vscode.window.showErrorMessage('FRX: could not find the `frx` CLI.');
    return;
  }

  if (!panel) {
    panel = vscode.window.createWebviewPanel(
      'frxMap',
      'FRX Map',
      vscode.ViewColumn.Active,
      { enableScripts: true, retainContextWhenHidden: true },
    );
    panel.onDidDispose(() => (panel = null));
    panel.webview.onDidReceiveMessage((m) => {
      if (m?.type === 'open' && m.file) {
        vscode.commands.executeCommand(
          'vscode.open',
          vscode.Uri.file(m.file),
          selectionAt({ line: m.line, column: m.column }),
        );
      } else if (m?.type === 'refresh') {
        showMap(context);
      }
    });
  }

  // One read. The two list reads it replaces carried strictly less: no edges, no
  // ownership, and nothing about what frx could not follow.
  const graph = await queries.graph(inv, root);
  panel.webview.html = buildHtml(picture(graph, root));
  panel.reveal();
}

/**
 * Fold the graph into what gets drawn.
 *
 * Actions and selectors are **collapsed into their owning substate**, and every
 * edge that ends on one is rewritten to that substate. So a page that dispatches
 * `SetEmailAction` draws one line to `logIn`, and a page that dispatches four of
 * its actions still draws one — which is the difference between a shape and a
 * hairball.
 */
export function picture(graph: AppGraph | null, root = ''): Picture {
  if (!graph) return { actors: [], state: [], edges: [], gaps: [], crossings: 0 };

  const byId = new Map(graph.nodes.map((n) => [n.id, n]));
  /** The node an id is drawn as: itself, or the substate that owns it. */
  const drawnAs = (id: string): string | null => {
    const n = byId.get(id);
    if (!n) return null;
    if (OWNED_KINDS.has(n.kind)) return n.substate ? `substate:${n.substate}` : null;
    return id;
  };

  const owned = new Map<string, PictureNode[]>();
  for (const n of graph.nodes) {
    if (!OWNED_KINDS.has(n.kind) || !n.substate) continue;
    const key = `substate:${n.substate}`;
    const list = owned.get(key) ?? [];
    list.push(leaf(n, n.kind));
    owned.set(key, list);
  }

  const state: PictureNode[] = [];
  const actors: PictureNode[] = [];
  for (const n of graph.nodes) {
    if (n.kind === 'substate') {
      state.push({ ...leaf(n, n.type ?? ''), owned: owned.get(n.id) ?? [] });
    } else if (ACTOR_KINDS.has(n.kind)) {
      actors.push(leaf(n, n.kind === 'page' ? (n.path ?? 'page') : n.kind));
    }
  }
  // By name first, so what follows is a function of the graph rather than of the
  // order the reader happened to arrive in — and so the rows that end up with no
  // barycenter stay alphabetical among themselves.
  sortByTitle(state);
  sortByTitle(actors);

  // De-duplicated: several callbacks reaching the same substate are one relation.
  const inState = new Set(state.map((n) => n.id));
  const inActors = new Set(actors.map((n) => n.id));
  // What the nesting shows, decided once — the layout cuts a build cycle the
  // same way, so a relation the cut left out is still drawn as a line.
  const under = nesting(actors.map((n) => n.id), builders(graph.edges, actors));
  // One line per pair, carrying every relation between them.
  const edges = new Map<string, PictureEdge>();
  for (const e of graph.edges) {
    const from = drawnAs(e.from);
    const to = drawnAs(e.to);
    if (!from || !to || from === to) continue;
    // The one relation the nesting says: a row sits under the row that builds
    // it, so the line would say it twice. A second builder keeps its line —
    // the row can only sit under one.
    if (e.kind === 'builds' && under.get(to) === from) continue;
    // Keyed by the *unordered* pair: one line joins two rows however many
    // relations run between them and whichever way round they run.
    const key = [from, to].sort().join('|');
    let line = edges.get(key);
    if (!line) {
      line = {
        from,
        to,
        relations: [],
        side: sideOf(from, to, inState, inActors),
      };
      edges.set(key, line);
    }
    // The end the fold moved, if either: an edge into an action or a selector
    // is drawn to the substate, and the pane says which one it was.
    const folded = [e.from, e.to].find((id) => id !== from && id !== to);
    const relation: Relation = {
      kind: e.kind,
      via: e.via ?? '',
      reversed: line.from !== from,
      ...(folded ? { through: folded } : {}),
    };
    // Two callbacks that dispatch the same action the same way, by the same
    // trigger, are one relation — but two different triggers are two, and so
    // are two different actions behind one trigger; the pane names each.
    const said = line.relations.some(
      (r) =>
        r.kind === relation.kind &&
        r.via === relation.via &&
        r.reversed === relation.reversed &&
        r.through === relation.through,
    );
    if (!said) line.relations.push(relation);
  }

  // Ordered to reduce crossings. At this size the number of crossings is decided
  // entirely by the order of the two columns, and alphabetical order has nothing
  // to do with the edges — on this repository it left 44 of them where two were
  // available. Same-column edges are left out of the count because they have
  // no span across the middle to cross anything with, not because of where they
  // are drawn.
  const drawn = [...edges.values()];
  const ordering = orderColumns(
    actors.map((n) => n.id),
    state.map((n) => n.id),
    drawn,
    under,
  );

  // Where along a row each line attaches is not decided here. It used to be —
  // a slot per edge end, by the row the far end lands on — but which lines
  // exist is now the drawing's business: a folded row takes over the lines of
  // everything under it, and the slots have to follow. See `slotsOf` in the page.

  return {
    actors: nested(inOrder(actors, ordering.actors), under),
    state: inOrder(state, ordering.state),
    edges: drawn,
    gaps: graph.unresolved.map((u) => ({
      what: [u.kind, u.expr].filter(Boolean).join('  '),
      at: u.at ? relativeTo(root, u.at) : '',
      why: u.why,
    })),
    crossings: ordering.crossings,
  };
}

/**
 * `nodes`, arranged as `order` says.
 *
 * The ordering is a permutation of the ids it was given, so every lookup hits.
 * Asserted rather than defended with a filter: a filter would silently drop a
 * node from the picture, which is the one failure here nobody would notice.
 */
function inOrder(nodes: PictureNode[], order: string[]): PictureNode[] {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  return order.map((id) => {
    const node = byId.get(id);
    if (!node) throw new Error(`the layout invented a node: ${id}`);
    return node;
  });
}

/**
 * `file` without the `root` prefix, when it has one.
 *
 * The CLI names files absolutely, and an absolute path in a 700px box breaks
 * mid-word at the width. The repo-relative form is what the rest of the editor
 * shows for the same file, and it is the part that says anything.
 */
function relativeTo(root: string, file: string): string {
  if (!root) return file;
  const prefix = root.endsWith('/') || root.endsWith('\\') ? root : root + '/';
  return file.startsWith(prefix) ? file.slice(prefix.length) : file;
}

/**
 * Each actor that something builds, mapped to the row it is drawn under.
 *
 * A row can sit under one builder. When several build it — a page constructs a
 * region, and so does a bar inside that page — it goes under the first by name,
 * which is the order `actors` arrives in, and the others keep their wire. First
 * by name rather than by some measure of which builder is "closer": there is no
 * such measure that does not depend on the answer, and the picture has to be a
 * function of the graph.
 */
function builders(
  edges: readonly { from: string; to: string; kind: string }[],
  actors: readonly PictureNode[],
): Map<string, string> {
  const rank = new Map(actors.map((n, i) => [n.id, i]));
  const builtBy = new Map<string, string>();
  for (const e of edges) {
    if (e.kind !== 'builds' || !rank.has(e.from) || !rank.has(e.to)) continue;
    const held = builtBy.get(e.to);
    if (held === undefined || rank.get(e.from)! < rank.get(held)!) builtBy.set(e.to, e.from);
  }
  return builtBy;
}

/**
 * `rows`, re-nested by `under`: the roots, each holding what it builds.
 *
 * The rows arrive flat from the ordering, builder before built — which is what
 * lets one pass do it: a row's builder is already placed when the row is met.
 * Asserted rather than tolerated: `under` is the nesting the ordering laid the
 * rows out by, so a builder that is not yet placed is the two disagreeing, and
 * a row silently promoted to a root is the failure nobody would notice.
 */
function nested(rows: readonly PictureNode[], under: ReadonlyMap<string, string>): PictureNode[] {
  const roots: PictureNode[] = [];
  const placed = new Map<string, PictureNode>();
  for (const row of rows) {
    const builder = under.get(row.id);
    if (builder === undefined) {
      roots.push(row);
    } else {
      const holder = placed.get(builder);
      if (!holder) throw new Error(`the layout put ${row.id} before ${builder}, which builds it`);
      holder.built.push(row);
    }
    placed.set(row.id, row);
  }
  return roots;
}

/**
 * Which way an edge runs: across the middle, or out into one column's margin.
 *
 * Both columns are tested rather than one — "not in state" is not the same claim
 * as "in actors", and reading it that way would quietly label an edge to a node
 * in neither column as belonging to the left margin. Nothing produces such an
 * edge today; a new node kind would.
 */
function sideOf(
  from: string,
  to: string,
  inState: ReadonlySet<string>,
  inActors: ReadonlySet<string>,
): Side {
  if (inState.has(from) && inState.has(to)) return 'right';
  if (inActors.has(from) && inActors.has(to)) return 'left';
  return 'across';
}

/** A graph node as a drawable leaf. A selector sheds its `Select…` qualifier. */
function leaf(n: GraphNode, subtitle: string): PictureNode {
  return {
    id: n.id,
    kind: n.kind,
    title: n.kind === 'selector' ? (n.name.split('.').pop() ?? n.name) : n.name,
    subtitle,
    file: n.file ?? null,
    line: n.line,
    column: n.column,
    owned: [],
    built: [],
  };
}

function sortByTitle(nodes: PictureNode[]): void {
  nodes.sort((a, b) => a.title.localeCompare(b.title));
}

/**
 * Build the webview HTML: two columns of nodes with the relations drawn between,
 * and a pane beside them that says in words what the focused row's lines mean.
 */
export function buildHtml(data: Picture): string {
  const nonce = crypto.randomBytes(16).toString('base64');
  // Embed as JSON, with `<` neutralized so a value can never close the script.
  // `crossings` stays out: it is what the ordering achieved, which the tests
  // assert and the drawing has no use for.
  const { crossings: _crossings, ...drawable } = data;
  const json = JSON.stringify(drawable).replace(/</g, '\\u003c');

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
<style>
  /* The palette is the editor's chart palette, so it follows the theme. One
     colour means one thing everywhere it appears: a page's edge and a line
     into state are both "changes", a substate's edge is "state". */
  :root {
    --changes: var(--vscode-charts-blue, #3794ff);
    --reads: var(--vscode-charts-lines, #6e6e6e);
    --page: var(--vscode-charts-blue, #3794ff);
    --consumer: var(--vscode-descriptionForeground, #8b8b8b);
    --service: var(--vscode-charts-purple, #b180d7);
    --persistor: var(--vscode-charts-orange, #d18616);
    --substate: var(--vscode-charts-green, #89d185);
  }
  body { font-family: var(--vscode-font-family); color: var(--vscode-foreground);
    background: var(--vscode-editor-background); margin: 0; padding: 16px; }
  h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .06em;
    opacity: .7; margin: 0 0 8px; font-weight: 600; }
  .toolbar { margin-bottom: 12px; display: flex; align-items: center; gap: 16px;
    flex-wrap: wrap; }
  .legend { font-size: 12px; opacity: .75; display: flex; gap: 14px; flex-wrap: wrap; }
  .legend .line { display: inline-block; width: 22px; vertical-align: middle;
    border-top: 2px solid var(--reads); margin: 0 4px 3px 0; }
  .legend .line.changes { border-top-color: var(--changes); }
  .legend .line.navigates { border-top-style: dashed; border-top-width: 1.5px; }
  .legend .line.builds { border-top-style: dotted; border-top-width: 1.5px; }
  button { font: inherit; color: var(--vscode-button-foreground);
    background: var(--vscode-button-background); border: none; padding: 4px 10px;
    border-radius: 4px; cursor: pointer; }
  /* The picture and, beside it, the pane. The pane keeps to the top of the
     viewport while the picture scrolls under it: what it describes is whatever
     is focused, which is on screen by definition. On a panel too narrow for
     both it becomes a sheet along the bottom, shown only while something is
     focused, so it never covers a picture nobody asked about. */
  #wrap { display: flex; gap: 24px; align-items: flex-start; }
  #board { flex: 0 0 auto; }
  #pane { position: sticky; top: 16px; flex: 0 0 auto; width: 300px;
    box-sizing: border-box; font-size: 12px; max-height: calc(100vh - 32px);
    overflow: auto; border: 1px solid var(--vscode-panel-border); border-radius: 6px;
    padding: 10px 12px; background: var(--vscode-editorWidget-background); }
  @media (max-width: 1000px) {
    #pane { position: fixed; left: 16px; right: 16px; bottom: 0; top: auto; width: auto;
      max-height: 40vh; border-radius: 6px 6px 0 0; z-index: 2; }
    #pane.idle { display: none; }
  }
  #pane .hint { opacity: .5; font-style: italic; }
  #pane h3 { margin: 0 0 2px; font-size: 13px; cursor: pointer; }
  #pane h3:hover { text-decoration: underline; }
  #pane .kind { opacity: .7; margin-bottom: 6px; }
  #pane h4 { margin: 10px 0 4px; font-size: 11px; text-transform: uppercase;
    letter-spacing: .05em; opacity: .7; }
  #pane h4.changes { color: var(--changes); opacity: 1; }
  #pane ul { list-style: none; margin: 0; padding: 0; }
  #pane li { padding: 2px 0; cursor: pointer; }
  #pane li:hover { text-decoration: underline; }
  #pane li .via { opacity: .6; font-family: var(--vscode-editor-font-family); }
  /* The side padding is the channel: an edge joining two nodes of one column
     leaves and re-enters on that column's outer side, and needs room to do it.
     Both it and the gap give way on a narrow panel — the columns do not, they
     are sized to their content and hold it; what is left over is what the
     lines get, and past that the page scrolls sideways rather than squeezing a
     name onto two lines. */
  #board { position: relative; display: flex; align-items: flex-start;
    gap: clamp(48px, 9vw, 120px); padding: 0 clamp(28px, 5vw, 70px); }
  /* The lines sit under the rows and take no pointer, except along their own
     stroke: a line in the gap can be hovered for what it carries, and a line
     under a row yields to the row. */
  svg { position: absolute; inset: 0; pointer-events: none; overflow: visible; }
  path.wire { pointer-events: stroke; }
  .col { position: relative; z-index: 1; flex: 0 0 auto; width: 280px; }
  /* The rows of the shorter column are placed, not stacked: each at the height of
     the rows it relates to, so its lines run level instead of down the whole
     canvas. The container is what the placement measures against. */
  .rows { position: relative; }
  .rows.placed > .node { position: absolute; left: 0; right: 0; margin: 0; }
  .node { box-sizing: border-box; border-radius: 6px; padding: 6px 10px;
    margin-bottom: 10px; border: 1px solid var(--vscode-panel-border);
    border-left-width: 3px; background: var(--vscode-editorWidget-background); }
  /* The kind, as a coloured edge: the column mixes screens, regions, services
     and the persistor, and the subtitle says which — this lets the eye sort
     them without reading. */
  .node.k-page { border-left-color: var(--page); }
  .node.k-consumer { border-left-color: var(--consumer); }
  .node.k-service { border-left-color: var(--service); }
  .node.k-persistor { border-left-color: var(--persistor); }
  .node.k-substate { border-left-color: var(--substate); }
  /* One line each, and the column is measured to hold them (see fit()): a
     class name broken across two lines reads as two names. */
  .node .t { font-weight: 600; cursor: pointer; white-space: nowrap; }
  .node .t:hover { text-decoration: underline; }
  .node .s { opacity: .7; font-size: 12px; white-space: nowrap; }
  .owned, .regions { margin-top: 4px; font-size: 12px; }
  .owned .count, .regions { cursor: pointer; opacity: .8; user-select: none;
    white-space: nowrap; }
  .owned ul { list-style: none; margin: 4px 0 0; padding: 0 0 0 10px;
    border-left: 1px solid var(--vscode-panel-border); }
  .owned li { padding: 1px 0; cursor: pointer; }
  .owned li:hover { text-decoration: underline; }
  /* What a row builds sits inside it, indented: the composition reads as
     containment, which is what it is. The last built row keeps no bottom margin,
     so the builder's box closes tight around it. Folded, the regions are gone
     and their lines land on the builder. */
  .built { margin: 8px 0 0 14px; }
  .built > .node:last-child { margin-bottom: 0; }
  .node.folded > .built { display: none; }
  .empty { opacity: .6; font-style: italic; }
  /* Focus and context: hovering a row dims everything not attached to it. The
     crossings that remain stop mattering when one row's relations can be read on
     their own. A transition, so the picture settles rather than flickering as the
     pointer crosses rows. Dimmed by the row's own head rather than the row: a box
     also holds what it builds, and opacity on the box would dim a lit row inside
     an unlit one. */
  .node > .head, path.wire { transition: opacity .12s ease; }
  #board.focusing .node:not(.lit) > .head,
  #board.focusing path.wire:not(.lit) { opacity: .12; }
  #board.focusing path.wire.lit { stroke-width: 2; }
  /* A pinned row holds the focus after the pointer leaves, and says so. */
  .node.pinned > .head { outline: 1px solid var(--changes); outline-offset: 3px;
    border-radius: 3px; }
  .gaps { margin-top: 20px; border: 1px solid var(--vscode-panel-border);
    border-radius: 6px; padding: 8px 12px; max-width: min(700px, 100%);
    box-sizing: border-box; }
  .gaps .at, .gaps .why { opacity: .7; font-size: 12px; margin: 0 0 0 14px; }
  .gaps .why { margin-bottom: 8px; }
  /* A path has no space to break at; without this it runs out of the box. */
  .gaps code { font-family: var(--vscode-editor-font-family); overflow-wrap: anywhere; }
  /* A line's colour is what it does to state: a line that changes it, and a
     line that only reads it. The first question on arriving anywhere is "who
     can change this", and it used to take a hover per line to answer. */
  path.wire { fill: none; stroke: var(--reads); stroke-width: 1.5; opacity: .7; }
  path.wire.changes { stroke: var(--changes); opacity: .85; }
  path.navigates { stroke-dasharray: 4 3; }
  path.builds { stroke-dasharray: 1.5 3; }
</style>
</head>
<body>
  <div class="toolbar">
    <button id="refresh">↻ Refresh</button>
    <span class="legend">
      <span><span class="line changes"></span>changes state</span>
      <span><span class="line"></span>reads it</span>
      <span><span class="line navigates"></span>navigates</span>
      <span><span class="line builds"></span>also built by</span>
      <span>indented = built by</span>
    </span>
  </div>
  <div id="wrap">
    <div id="board">
      <div class="col" id="actors"><h2>Screens &amp; actors</h2><div class="rows"></div></div>
      <div class="col" id="state"><h2>State</h2><div class="rows"></div></div>
      <svg id="wires"></svg>
    </div>
    <div id="pane" class="idle"></div>
  </div>
  <div id="gaps"></div>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const DATA = ${json};
    /** What a relation does to state, by its kind. */
    const CHANGES = new Set(['dispatches', 'writes', 'restores']);
    const READS = new Set(['uses', 'reads']);
    /** A row with more of them than this starts folded — see fold(). */
    const FOLD_OVER = 3;
    const boxes = new Map();
    /** Every node by id — rows, and the actions and selectors a row owns. */
    const nodes = new Map();
    /** A row's builder, by the nesting drawn. */
    const builderOf = new Map();
    (function index(list, builder) {
      for (const n of list) {
        nodes.set(n.id, n);
        if (builder) builderOf.set(n.id, builder);
        index(n.owned || [], null);
        index(n.built || [], n.id);
      }
    })(DATA.actors.concat(DATA.state), null);

    // What the page remembers across a refresh: which rows are folded and
    // which is pinned. Rebuilding the page is how it refreshes, and losing the
    // fold you just made to see the refreshed picture would be the page
    // undoing your last action.
    const remembered = vscode.getState() || {};
    const folded = new Set(remembered.folded || []);
    let pinned = remembered.pinned && nodes.has(remembered.pinned) ? remembered.pinned : null;
    function remember() {
      vscode.setState({ folded: [...folded], pinned });
    }

    function open(n) {
      if (n && n.file) vscode.postMessage({ type: 'open', file: n.file, line: n.line, column: n.column });
    }

    function nodeEl(n) {
      const el = document.createElement('div');
      el.className = 'node k-' + n.kind;
      el.dataset.id = n.id;
      // The head is the row's own content; what it builds comes after, inside
      // the same box, so the focus rule can dim one without the other.
      const head = document.createElement('div');
      head.className = 'head';
      el.appendChild(head);
      const t = document.createElement('div');
      t.className = 't';
      t.textContent = n.title;
      if (n.file) t.addEventListener('click', () => open(n));
      else t.style.cursor = 'default';
      const s = document.createElement('div');
      s.className = 's';
      s.textContent = n.subtitle;
      head.append(t, s);

      // Actions and selectors arrive as a count and expand on demand — the whole
      // reason the view stays readable as the app grows.
      if (n.owned && n.owned.length) {
        const wrap = document.createElement('div');
        wrap.className = 'owned';
        const actions = n.owned.filter((o) => o.kind === 'action').length;
        const selectors = n.owned.length - actions;
        const list = document.createElement('ul');
        list.hidden = true;
        for (const o of n.owned) {
          const li = document.createElement('li');
          li.textContent = o.title;
          li.title = o.kind;
          li.addEventListener('click', () => open(o));
          list.appendChild(li);
        }
        let shown = false;
        const label = () =>
          (shown ? '▾ ' : '▸ ') +
          [actions ? actions + (actions === 1 ? ' action' : ' actions') : null,
           selectors ? selectors + (selectors === 1 ? ' selector' : ' selectors') : null]
            .filter(Boolean).join(' · ');
        const count = document.createElement('div');
        count.className = 'count';
        count.textContent = label();
        count.addEventListener('click', () => {
          shown = !shown;
          list.hidden = !shown;
          count.textContent = label();
          draw();
        });
        wrap.append(count, list);
        head.appendChild(wrap);
      }
      // What it builds folds the same way, for the same reason: a screen with
      // ten regions is one row of the overview and ten of the detail. A row
      // with many regions starts folded — the overview is what a reader
      // arrives for — and the choice is remembered.
      if (n.built && n.built.length) {
        if (!remembered.folded && n.built.length > FOLD_OVER) folded.add(n.id);
        const count = n.built.length;
        const toggle = document.createElement('div');
        toggle.className = 'regions';
        const label = () =>
          (folded.has(n.id) ? '▸ ' : '▾ ') + count + (count === 1 ? ' region' : ' regions');
        toggle.textContent = label();
        toggle.addEventListener('click', () => {
          if (folded.has(n.id)) folded.delete(n.id);
          else folded.add(n.id);
          el.classList.toggle('folded', folded.has(n.id));
          toggle.textContent = label();
          remember();
          draw();
        });
        head.appendChild(toggle);
        const built = document.createElement('div');
        built.className = 'built';
        for (const b of n.built) built.appendChild(nodeEl(b));
        el.appendChild(built);
        el.classList.toggle('folded', folded.has(n.id));
      }
      boxes.set(n.id, el);
      return el;
    }

    function fill(id, list) {
      const rows = document.querySelector('#' + id + ' .rows');
      if (!list.length) {
        const e = document.createElement('div');
        e.className = 'node empty';
        e.textContent = 'none';
        rows.appendChild(e);
        return;
      }
      for (const n of list) rows.appendChild(nodeEl(n));
    }

    /**
     * Size each column to its widest row, so nothing wraps and nothing spills.
     *
     * A fixed width was right for two flat columns of short names and wrong
     * for everything since: a name three levels deep has lost 72px to indents
     * before it starts, and a narrow panel had flex squeezing the columns
     * until a count broke across two lines. The width is a property of the
     * content — the longest name at its own indent — so it is measured, once,
     * before the first draw. Expanding a row changes heights, not this.
     *
     * The text is measured as text (a Range around it), not as its block: a
     * block is as wide as its container whatever it holds, which is exactly
     * the number that says nothing. The insets on either side are what the
     * enclosing boxes take at that depth, read off the flow layout — with
     * every row unfolded, so a fold does not change the width.
     */
    function fit() {
      const wasFolded = [...document.querySelectorAll('.node.folded')];
      for (const el of wasFolded) el.classList.remove('folded');
      for (const id of ['actors', 'state']) {
        const col = document.getElementById(id);
        col.style.width = '';
        const rect = col.getBoundingClientRect();
        let widest = 0;
        const range = document.createRange();
        for (const head of col.querySelectorAll('.head')) {
          const box = head.getBoundingClientRect();
          const insets = (box.left - rect.left) + (rect.right - box.right);
          for (const line of head.querySelectorAll('.t, .s, .count, .regions')) {
            range.selectNodeContents(line);
            widest = Math.max(widest, insets + range.getBoundingClientRect().width);
          }
        }
        // A little air after the longest line; bounded so one absurd name
        // cannot take the panel, and so an empty column still looks like one.
        col.style.width = Math.min(480, Math.max(160, Math.ceil(widest) + 6)) + 'px';
      }
      for (const el of wasFolded) el.classList.add('folded');
    }

    /** The row an id is drawn on: itself, or the folded row it is under. */
    function shownAs(id) {
      let at = id;
      let builder = builderOf.get(at);
      while (builder !== undefined) {
        if (folded.has(builder)) at = builder;
        builder = builderOf.get(builder);
      }
      return at;
    }

    /**
     * The lines to draw: the picture's edges, each end moved to the row it is
     * shown on, and lines that now join the same two rows merged. What a folded
     * region did to state is still there, on its builder — the same fold that
     * puts an action's edges on its substate. A line with both ends on one row
     * is a region relating to its own builder, which the fold has said already.
     */
    function lines() {
      const byPair = new Map();
      for (const e of DATA.edges) {
        const from = shownAs(e.from), to = shownAs(e.to);
        if (from === to) continue;
        const key = from < to ? from + '|' + to : to + '|' + from;
        let line = byPair.get(key);
        if (!line) {
          line = { from, to, side: e.side, kinds: new Set(), edges: [] };
          byPair.set(key, line);
        }
        line.edges.push(e);
        for (const r of e.relations) line.kinds.add(r.kind);
      }
      return [...byPair.values()];
    }

    /**
     * Where along its row each end of each line attaches.
     *
     * A slot per line end, spread along the row's edge so two lines never leave
     * one point, ordered by where the far end lands so a row's fan does not
     * cross itself. By the far end's height on the page rather than its row
     * number: the rows are placed, and a fold changes which rows there are.
     */
    function slotsOf(drawn) {
      const ends = new Map();
      drawn.forEach((line, index) => {
        for (const node of [line.from, line.to]) {
          const of = ends.get(node);
          if (of) of.push(index);
          else ends.set(node, [index]);
        }
      });
      const centre = (id) => {
        const r = boxes.get(id).getBoundingClientRect();
        return r.top + r.height / 2;
      };
      const slots = drawn.map(() => ({}));
      for (const [node, indices] of ends) {
        const ordered = indices
          .map((index, arrival) => {
            const line = drawn[index];
            return { index, arrival, y: centre(line.from === node ? line.to : line.from) };
          })
          .sort((a, b) => a.y - b.y || a.arrival - b.arrival);
        ordered.forEach(({ index }, slot) => {
          const end = drawn[index].from === node ? 'from' : 'to';
          slots[index][end] = { slot, of: ordered.length };
        });
      }
      return slots;
    }

    /** The ids of a row and everything nested under it. */
    function idsUnder(n) {
      return [n.id].concat((n.built || []).flatMap(idsUnder));
    }

    /**
     * Place the shorter column's rows level with what they relate to.
     *
     * Two columns of very different length — thirty-four rows facing nine — put
     * every line on a long diagonal into a short stack, and the lines bundled
     * into a rope beside the taller column. The order was right; the heights
     * were not. Each top-level row of the shorter column is set at the mean
     * height of the rows across from it, kept in order and apart, so a line
     * runs level to the row it names. The taller column stays in flow: it is
     * what the page scrolls by.
     *
     * Runs on every draw, because expanding or folding a row changes the
     * heights it is measured against. Positions are absolute inside the
     * column's own row container, so the measured widths — and so the heights
     * — are those of the flow layout.
     */
    function place() {
      const cols = ['actors', 'state'].map((id) => ({
        rows: document.querySelector('#' + id + ' .rows'),
        nodes: DATA[id],
      }));
      for (const c of cols) c.rows.classList.remove('placed');
      const natural = cols.map((c) => c.rows.getBoundingClientRect().height);
      // The shorter column moves. Neither, when the two are within a row of
      // each other: then placing gains nothing and the picture stays a list.
      const shorter = natural[0] < natural[1] ? 0 : natural[1] < natural[0] ? 1 : -1;
      if (shorter < 0 || !cols[shorter].nodes.length) return;
      const moving = cols[shorter];
      const facing = cols[1 - shorter].rows.getBoundingClientRect();

      const centreOf = (id) => {
        const box = boxes.get(shownAs(id));
        if (!box) return null;
        const r = box.getBoundingClientRect();
        return r.top + r.height / 2 - facing.top;
      };
      const wanted = [];
      const GAP = 10;
      let cursor = 0;
      for (const n of moving.nodes) {
        const ids = new Set(idsUnder(n));
        const ys = [];
        for (const e of DATA.edges) {
          if (e.side !== 'across') continue;
          const far = ids.has(e.from) ? e.to : ids.has(e.to) ? e.from : null;
          if (far === null) continue;
          const y = centreOf(far);
          if (y !== null) ys.push(y);
        }
        const box = boxes.get(n.id);
        const height = box.getBoundingClientRect().height;
        // A row with nothing across from it follows the row before it, so the
        // edgeless tail the ordering sank stays a tail.
        const centre = ys.length ? ys.reduce((a, b) => a + b, 0) / ys.length : cursor + height / 2;
        const top = Math.max(cursor, centre - height / 2);
        wanted.push({ box, top, height });
        cursor = top + height + GAP;
      }
      moving.rows.classList.add('placed');
      for (const w of wanted) w.box.style.top = w.top + 'px';
      moving.rows.style.height = (cursor - GAP) + 'px';
    }

    /**
     * Where a line meets a row: spread along the row's own edge by its slot, so
     * two relations never leave from the same point.
     *
     * Centred on the box's middle, not on a fixed offset from its top. Sizing the
     * fan from the box height while centring it near the top put the first anchor
     * *above* the box — 28px above it, for an expanded substate with eight
     * relations, across the gap and into the row before.
     *
     * boardTop is passed in rather than measured here: this runs twice per line,
     * inside a loop that is appending to the DOM, and reading a rect forces layout.
     * (No backticks in this comment — it lives inside a template literal.)
     */
    function anchorY(box, anchor, boardTop) {
      const half = Math.max(0, box.height / 2 - 4);
      const step = anchor.of > 1 ? Math.min(12, (2 * half) / (anchor.of - 1)) : 0;
      const middle = box.top - boardTop + box.height / 2;
      return middle + (anchor.slot - (anchor.of - 1) / 2) * step;
    }

    /** The row the pointer is on, or null. Held, because a redraw has to restore it. */
    let focused = null;
    /** What the picture is about right now: the hovered row, else the pinned one. */
    const current = () => focused || pinned;

    /**
     * Dim everything the current row is not attached to.
     *
     * The cheapest large win in legibility: it changes nothing about what the
     * picture contains, and lets a reader isolate one row's relations without
     * following a line through the ones that cross it.
     *
     * Attached is direct — the rows this one relates to, and the wires between.
     * Not the transitive neighbourhood: "what does this touch" is the question a
     * reader hovers to ask, and following it further is what the graph command's
     * inbound walk is for. Read off the wires as drawn, so a folded row is
     * attached to whatever its regions' lines now reach.
     *
     * Re-applied after every redraw, not only on hover. Expanding a row rebuilds
     * every wire from scratch, and the pointer never leaves the row while you do
     * it — so nothing would fire, and the picture would sit there with the
     * focused row's own relations dimmed along with the rest.
     */
    function applyFocus() {
      const board = document.getElementById('board');
      const on = current();
      for (const [id, box] of boxes) box.classList.toggle('pinned', id === pinned);
      if (!on) {
        board.classList.remove('focusing');
        for (const box of boxes.values()) box.classList.remove('lit');
        for (const wire of document.querySelectorAll('path.wire')) {
          wire.classList.remove('lit');
        }
        describe(null);
        return;
      }
      const lit = new Set([on]);
      for (const wire of document.querySelectorAll('path.wire')) {
        const touches = wire.dataset.from === on || wire.dataset.to === on;
        wire.classList.toggle('lit', touches);
        if (touches) lit.add(wire.dataset.from === on ? wire.dataset.to : wire.dataset.from);
      }
      for (const [id, box] of boxes) box.classList.toggle('lit', lit.has(id));
      board.classList.add('focusing');
      describe(on);
    }

    /**
     * Say in words what the row's lines mean.
     *
     * The picture gives the shape; this gives the specifics a line cannot carry:
     * which action, through which callback, which selector. Grouped by what the
     * relation does and which way it runs — "changed by" is the first question
     * on arriving at a substate, and it heads the list. Every entry opens the
     * thing it names: the action or selector when the fold hid one, else the
     * row across.
     */
    function describe(id) {
      const pane = document.getElementById('pane');
      pane.innerHTML = '';
      pane.classList.toggle('idle', !id);
      if (!id) {
        const hint = document.createElement('div');
        hint.className = 'hint';
        hint.textContent = 'Hover a row to see what its lines mean; click to pin it, Esc to let go.';
        pane.appendChild(hint);
        return;
      }
      const n = nodes.get(id);
      const h = document.createElement('h3');
      h.textContent = n.title;
      h.addEventListener('click', () => open(n));
      const kind = document.createElement('div');
      kind.className = 'kind';
      kind.textContent = n.kind + (n.file ? ' · ' + n.file.split(/[\\\\/]/).slice(-2).join('/') : '');
      pane.append(h, kind);

      const groups = new Map();
      const add = (group, entry) => {
        const list = groups.get(group) || [];
        list.push(entry);
        groups.set(group, list);
      };
      for (const e of DATA.edges) {
        const far = e.from === id ? e.to : e.to === id ? e.from : null;
        if (far === null) continue;
        for (const r of e.relations) {
          const out = (e.from === id) !== r.reversed;
          const what = r.through ? nodes.get(r.through) : null;
          const entry = { far: nodes.get(far), what, via: r.via, kind: r.kind };
          if (CHANGES.has(r.kind)) add(out ? 'Changes' : 'Changed by', entry);
          else if (READS.has(r.kind)) add(out ? 'Reads' : 'Read by', entry);
          else add(out ? r.kind : r.kind + ' ← from', entry);
        }
      }
      const builder = builderOf.get(id);
      if (builder) add('Built by', { far: nodes.get(builder), what: null, via: '', kind: 'builds' });
      for (const b of n.built || []) add('Builds', { far: b, what: null, via: '', kind: 'builds' });

      const order = ['Changed by', 'Changes', 'Read by', 'Reads'];
      const named = [...groups.keys()].sort(
        (a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99),
      );
      for (const group of named) {
        const h4 = document.createElement('h4');
        h4.textContent = group;
        if (group === 'Changes' || group === 'Changed by') h4.className = 'changes';
        const ul = document.createElement('ul');
        for (const entry of groups.get(group)) {
          const li = document.createElement('li');
          // The row across, then the action or selector behind the line when
          // the fold hid one, then what triggers it.
          li.textContent = entry.far.title + (entry.what ? ' · ' + entry.what.title : '');
          if (entry.via) {
            const via = document.createElement('span');
            via.className = 'via';
            via.textContent = ' ' + entry.via;
            li.appendChild(via);
          }
          li.addEventListener('click', () => open(entry.what || entry.far));
          ul.appendChild(li);
        }
        pane.append(h4, ul);
      }
    }

    function focusOnHover() {
      const board = document.getElementById('board');
      // One listener on the board, resolving to the innermost row under the
      // pointer — a row nested in another is inside its builder's box, and a
      // per-row enter/leave pair would light the builder on the way in and
      // let go of everything on the way out. Moving into the gap between rows
      // resolves to no row, which is the letting go — unless a row is pinned,
      // which is what pinning is for. A line is not a row: crossing one keeps
      // the focus, so its own tooltip can be read.
      board.addEventListener('mouseover', (event) => {
        if (event.target.closest('svg')) return;
        const row = event.target.closest('.node');
        const id = row && boxes.has(row.dataset.id) ? row.dataset.id : null;
        if (id === focused) return;
        focused = id;
        applyFocus();
      });
      // Away from the panel entirely — clicking a title opens a file over it,
      // and a hidden webview is retained rather than unloaded, so the board
      // would come back still dimmed.
      board.addEventListener('pointerleave', () => {
        focused = null;
        applyFocus();
      });
      // And off the board without the pointer moving: scrolling slides the
      // rows out from under it, and the browser then says where the pointer
      // is by a mouseover on whatever is there now — which is not the board,
      // so the board's own listeners never hear of it.
      document.addEventListener('mouseover', (event) => {
        if (focused && !board.contains(event.target)) {
          focused = null;
          applyFocus();
        }
      });
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
          focused = null;
          applyFocus();
        }
      });
      // A click on a row's own surface pins it: the focus stays when the pointer
      // goes, so the pane can be read and the picture scrolled with one row's
      // relations held lit. The title, counts and lists keep their own clicks.
      board.addEventListener('click', (event) => {
        if (event.target.closest('.t, .count, .regions, .owned li, svg')) return;
        const row = event.target.closest('.node');
        const id = row && boxes.has(row.dataset.id) ? row.dataset.id : null;
        if (!id) return;
        pinned = pinned === id ? null : id;
        remember();
        applyFocus();
      });
      document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape' || !pinned) return;
        pinned = null;
        remember();
        applyFocus();
      });
    }

    /** Redraw the wires against the current layout (expanding a node moves it). */
    function draw() {
      place();
      const svg = document.getElementById('wires');
      const boardEl = document.getElementById('board');
      const board = boardEl.getBoundingClientRect();
      // How far a same-column line may bulge into the margin: the margin is
      // narrower on a narrow panel, and a line past it runs off the page.
      const channel = parseFloat(getComputedStyle(boardEl).paddingLeft) - 8;
      svg.setAttribute('width', board.width);
      svg.setAttribute('height', board.height);
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      // A line meets a column at the column's edge, not the row's: a nested row
      // is indented inside its builder's box, and a line into its own edge would
      // cut across the box that holds it.
      const colOf = (id) => document.getElementById(id).getBoundingClientRect();
      const actorsCol = colOf('actors'), stateCol = colOf('state');
      const edgeX = (id, side) =>
        (id.startsWith('substate:') ? stateCol : actorsCol)[side] - board.left;
      const drawn = lines();
      const slots = slotsOf(drawn);
      drawn.forEach((line, i) => {
        const ra = boxes.get(line.from).getBoundingClientRect();
        const rb = boxes.get(line.to).getBoundingClientRect();
        const y1 = anchorY(ra, slots[i].from, board.top);
        const y2 = anchorY(rb, slots[i].to, board.top);

        let d;
        if (line.side === 'across') {
          // A curve, not a chord: two relations that leave one row a few pixels
          // apart and land far apart stay apart the whole way, instead of
          // converging into one stroke near each end.
          const leftFirst = !line.from.startsWith('substate:');
          const x1 = edgeX(line.from, leftFirst ? 'right' : 'left');
          const x2 = edgeX(line.to, leftFirst ? 'left' : 'right');
          const bend = (x2 - x1) * 0.45;
          d = 'M ' + x1 + ' ' + y1 +
              ' C ' + (x1 + bend) + ' ' + y1 +
              ', ' + (x2 - bend) + ' ' + y2 +
              ', ' + x2 + ' ' + y2;
        } else {
          // Out into the margin on its own side and back, rather than across the
          // canvas. The bulge grows with the vertical distance, so an edge that
          // spans many rows arcs wider than one between neighbours and the two
          // do not lie on top of each other.
          const left = line.side === 'left';
          const x1 = edgeX(line.from, left ? 'left' : 'right');
          const x2 = edgeX(line.to, left ? 'left' : 'right');
          const reach = Math.min(channel, 16 + Math.abs(y2 - y1) * 0.25) * (left ? -1 : 1);
          d = 'M ' + x1 + ' ' + y1 +
              ' C ' + (x1 + reach) + ' ' + y1 +
              ', ' + (x2 + reach) + ' ' + y2 +
              ', ' + x2 + ' ' + y2;
        }

        const wire = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        // Every kind the pair relates by, so a line that is navigation among
        // other things still draws dashed — and 'changes' when any of them
        // changes state, which is the colour.
        const kinds = [...line.kinds];
        const changes = kinds.some((k) => CHANGES.has(k));
        wire.setAttribute('class', 'wire ' + kinds.join(' ') + (changes ? ' changes' : ''));
        wire.dataset.from = line.from;
        wire.dataset.to = line.to;
        wire.setAttribute('d', d);
        const title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
        // The escape is doubled on purpose. This line lives inside the template
        // literal that *builds* the page, so a single backslash-n becomes a real
        // newline in the emitted JavaScript — inside a string literal, which stops
        // the whole script parsing and leaves the map blank.
        // (And no backticks in this comment: they would end the literal.)
        title.textContent = line.edges
          .flatMap((e) => e.relations.map((r) =>
            (r.reversed ? '← ' : '') + r.kind +
            (r.through && nodes.has(r.through) ? ' ' + nodes.get(r.through).title : '') +
            (r.via ? ' (' + r.via + ')' : '')))
          .join('\\n');
        wire.appendChild(title);
        svg.appendChild(wire);
      });
      applyFocus();
    }

    fill('actors', DATA.actors);
    fill('state', DATA.state);
    fit();
    draw();
    window.addEventListener('resize', draw);
    focusOnHover();

    // A diagram reads as exhaustive, so it says where its own edges stop.
    if (DATA.gaps.length) {
      const box = document.createElement('div');
      box.className = 'gaps';
      const h = document.createElement('h2');
      h.textContent = '⚠ ' + DATA.gaps.length + ' unresolved edge(s)';
      box.appendChild(h);
      for (const g of DATA.gaps) {
        const what = document.createElement('div');
        const code = document.createElement('code');
        code.textContent = g.what;
        what.appendChild(code);
        box.appendChild(what);
        if (g.at) {
          const at = document.createElement('div');
          at.className = 'at';
          const file = document.createElement('code');
          file.textContent = g.at;
          at.appendChild(file);
          box.appendChild(at);
        }
        const why = document.createElement('p');
        why.className = 'why';
        why.textContent = g.why;
        box.appendChild(why);
      }
      document.getElementById('gaps').appendChild(box);
    }

    document.getElementById('refresh').addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
  </script>
</body>
</html>`;
}
