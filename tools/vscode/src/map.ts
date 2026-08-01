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
import { anchorSlots, orderColumns } from './layout';
import type { EdgeAnchors } from './layout';
import type { AppGraph, GraphNode } from './queries';
import { selectionAt } from './tree';

/** One drawable node: what it says, and what opening it reveals. */
interface PictureNode {
  id: string;
  title: string;
  subtitle: string;
  file: string | null;
  line?: number;
  column?: number;
  /** What it owns, collapsed — shown as a count, expanded on demand. */
  owned: PictureNode[];
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
  /** Where each end attaches, so two lines never leave from one point. */
  anchors: EdgeAnchors;
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
  /** Everything that acts on state: pages, services, the persistor, consumers. */
  actors: PictureNode[];
  /** The state itself: the substates. */
  state: PictureNode[];
  edges: PictureEdge[];
  /** Where the picture's own edges are incomplete. */
  gaps: { what: string; why: string }[];
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
  panel.webview.html = buildHtml(picture(graph));
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
export function picture(graph: AppGraph | null): Picture {
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
  // One line per pair, carrying every relation between them.
  const edges = new Map<string, PictureEdge>();
  for (const e of graph.edges) {
    const from = drawnAs(e.from);
    const to = drawnAs(e.to);
    if (!from || !to || from === to) continue;
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
        // Filled once the columns are ordered — the slots depend on which row
        // each end lands on.
        anchors: { from: { slot: 0, of: 1 }, to: { slot: 0, of: 1 } },
      };
      edges.set(key, line);
    }
    const relation: Relation = {
      kind: e.kind,
      via: e.via ?? '',
      reversed: line.from !== from,
    };
    // Two callbacks that dispatch into the same substate the same way, by the
    // same trigger, are one relation — but two different triggers are two, and
    // the tooltip names both.
    const said = line.relations.some(
      (r) =>
        r.kind === relation.kind &&
        r.via === relation.via &&
        r.reversed === relation.reversed,
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
  );

  const rows = new Map(
    [...ordering.actors, ...ordering.state].map((id, row) => [id, row]),
  );
  // A node the ordering never placed sorts last, like a node with no barycentre:
  // `Infinity`, the same answer `orderColumns` gives, so the two agree about what
  // "off the picture" means.
  const anchors = anchorSlots(drawn, (id) => rows.get(id) ?? Number.POSITIVE_INFINITY);
  // Filled in rather than built with the edge: the slots depend on the row each
  // end landed on, which is only known once the columns are ordered. Losing this
  // line puts every relation back on one anchor — which is what the "two relations
  // leaving one node" test in map.test.ts fails on.
  drawn.forEach((edge, i) => (edge.anchors = anchors[i]));

  return {
    actors: inOrder(actors, ordering.actors),
    state: inOrder(state, ordering.state),
    edges: drawn,
    gaps: graph.unresolved.map((u) => ({
      what: [u.kind, u.expr, u.at].filter(Boolean).join('  '),
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
    title: n.kind === 'selector' ? (n.name.split('.').pop() ?? n.name) : n.name,
    subtitle,
    file: n.file ?? null,
    line: n.line,
    column: n.column,
    owned: [],
  };
}

function sortByTitle(nodes: PictureNode[]): void {
  nodes.sort((a, b) => a.title.localeCompare(b.title));
}

/** Build the webview HTML: two columns of nodes with the relations drawn between. */
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
  body { font-family: var(--vscode-font-family); color: var(--vscode-foreground);
    background: var(--vscode-editor-background); margin: 0; padding: 16px; }
  h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .06em;
    opacity: .7; margin: 0 0 8px; font-weight: 600; }
  .toolbar { margin-bottom: 12px; }
  button { font: inherit; color: var(--vscode-button-foreground);
    background: var(--vscode-button-background); border: none; padding: 4px 10px;
    border-radius: 4px; cursor: pointer; }
  /* The side padding is the channel: an edge joining two nodes of one column
     leaves and re-enters on that column's outer side, and needs room to do it. */
  #board { position: relative; display: flex; gap: 120px; align-items: flex-start;
    padding: 0 70px; }
  svg { position: absolute; inset: 0; pointer-events: none; overflow: visible; }
  .col { position: relative; z-index: 1; width: 260px; }
  .node { box-sizing: border-box; border-radius: 6px; padding: 6px 10px;
    margin-bottom: 10px; border: 1px solid var(--vscode-panel-border);
    background: var(--vscode-editorWidget-background); }
  .node .t { font-weight: 600; cursor: pointer; }
  .node .t:hover { text-decoration: underline; }
  .node .s { opacity: .7; font-size: 12px; }
  .owned { margin-top: 4px; font-size: 12px; }
  .owned .count { cursor: pointer; opacity: .8; user-select: none; }
  .owned ul { list-style: none; margin: 4px 0 0; padding: 0 0 0 10px;
    border-left: 1px solid var(--vscode-panel-border); }
  .owned li { padding: 1px 0; cursor: pointer; }
  .owned li:hover { text-decoration: underline; }
  .empty { opacity: .6; font-style: italic; }
  /* Focus and context: hovering a row dims everything not attached to it. The
     crossings that remain stop mattering when one row's relations can be read on
     their own. A transition, so the picture settles rather than flickering as the
     pointer crosses rows. */
  .node, path.wire { transition: opacity .12s ease; }
  #board.focusing .node:not(.lit),
  #board.focusing path.wire:not(.lit) { opacity: .12; }
  .gaps { margin-top: 20px; border: 1px solid var(--vscode-panel-border);
    border-radius: 6px; padding: 8px 12px; max-width: 700px; }
  .gaps .why { opacity: .7; font-size: 12px; margin: 0 0 6px 14px; }
  .gaps code { font-family: var(--vscode-editor-font-family); }
  path.wire { fill: none; stroke: var(--vscode-panel-border); stroke-width: 1.5; }
  path.navigates { stroke-dasharray: 4 3; }
</style>
</head>
<body>
  <div class="toolbar"><button id="refresh">↻ Refresh</button></div>
  <div id="board">
    <div class="col" id="actors"><h2>Screens &amp; actors</h2></div>
    <div class="col" id="state"><h2>State</h2></div>
    <svg id="wires"></svg>
  </div>
  <div id="gaps"></div>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const DATA = ${json};
    const boxes = new Map();

    function open(n) {
      if (n.file) vscode.postMessage({ type: 'open', file: n.file, line: n.line, column: n.column });
    }

    function nodeEl(n) {
      const el = document.createElement('div');
      el.className = 'node';
      const t = document.createElement('div');
      t.className = 't';
      t.textContent = n.title;
      if (n.file) t.addEventListener('click', () => open(n));
      else t.style.cursor = 'default';
      const s = document.createElement('div');
      s.className = 's';
      s.textContent = n.subtitle;
      el.append(t, s);

      // Actions and selectors arrive as a count and expand on demand — the whole
      // reason the view stays readable as the app grows.
      if (n.owned && n.owned.length) {
        const wrap = document.createElement('div');
        wrap.className = 'owned';
        const actions = n.owned.filter((o) => o.subtitle === 'action').length;
        const selectors = n.owned.length - actions;
        const list = document.createElement('ul');
        list.hidden = true;
        for (const o of n.owned) {
          const li = document.createElement('li');
          li.textContent = o.title;
          li.title = o.subtitle;
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
        el.appendChild(wrap);
      }
      boxes.set(n.id, el);
      return el;
    }

    function fill(id, nodes) {
      const col = document.getElementById(id);
      if (!nodes.length) {
        const e = document.createElement('div');
        e.className = 'node empty';
        e.textContent = 'none';
        col.appendChild(e);
        return;
      }
      for (const n of nodes) col.appendChild(nodeEl(n));
    }

    /**
     * Where an edge meets a row: spread along the row's own edge by its slot, so
     * two relations never leave from the same point.
     *
     * Centred on the box's middle, not on a fixed offset from its top. Sizing the
     * fan from the box height while centring it near the top put the first anchor
     * *above* the box — 28px above it, for an expanded substate with eight
     * relations, across the gap and into the row before.
     *
     * boardTop is passed in rather than measured here: this runs twice per edge,
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

    /**
     * Dim everything the focused row is not attached to.
     *
     * The cheapest large win in legibility: it changes nothing about what the
     * picture contains, and lets a reader isolate one row's relations without
     * following a line through the ones that cross it.
     *
     * Attached is direct — the rows this one relates to, and the wires between.
     * Not the transitive neighbourhood: "what does this touch" is the question a
     * reader hovers to ask, and following it further is what the graph command's
     * inbound walk is for.
     *
     * Re-applied after every redraw, not only on hover. Expanding a row rebuilds
     * every wire from scratch, and the pointer never leaves the row while you do
     * it — so nothing would fire, and the picture would sit there with the
     * focused row's own relations dimmed along with the rest.
     */
    function applyFocus() {
      const board = document.getElementById('board');
      if (!focused) {
        board.classList.remove('focusing');
        for (const box of boxes.values()) box.classList.remove('lit');
        for (const wire of document.querySelectorAll('path.wire')) {
          wire.classList.remove('lit');
        }
        return;
      }
      const lit = new Set([focused]);
      for (const e of DATA.edges) {
        if (e.from === focused) lit.add(e.to);
        else if (e.to === focused) lit.add(e.from);
      }
      for (const [id, box] of boxes) box.classList.toggle('lit', lit.has(id));
      for (const wire of document.querySelectorAll('path.wire')) {
        const touches = wire.dataset.from === focused || wire.dataset.to === focused;
        wire.classList.toggle('lit', touches);
      }
      board.classList.add('focusing');
    }

    function focusOnHover() {
      const board = document.getElementById('board');
      for (const [id, el] of boxes) {
        el.addEventListener('mouseenter', () => {
          focused = id;
          applyFocus();
        });
        el.addEventListener('mouseleave', () => {
          focused = null;
          applyFocus();
        });
      }
      // Two ways the pointer can leave without a row saying so: out through the
      // gap between rows, and away from the panel entirely — clicking a title
      // opens a file over it, and a hidden webview is retained rather than
      // unloaded, so the board would come back still dimmed.
      board.addEventListener('pointerleave', () => {
        focused = null;
        applyFocus();
      });
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
          focused = null;
          applyFocus();
        }
      });
    }

    /** Redraw the wires against the current layout (expanding a node moves it). */
    function draw() {
      const svg = document.getElementById('wires');
      const board = document.getElementById('board').getBoundingClientRect();
      svg.setAttribute('width', board.width);
      svg.setAttribute('height', board.height);
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      for (const e of DATA.edges) {
        const a = boxes.get(e.from), b = boxes.get(e.to);
        if (!a || !b) continue;
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        const y1 = anchorY(ra, e.anchors.from, board.top);
        const y2 = anchorY(rb, e.anchors.to, board.top);

        let d;
        if (e.side === 'across') {
          // A curve, not a chord: two relations that leave one row a few pixels
          // apart and land far apart stay apart the whole way, instead of
          // converging into one stroke near each end.
          const x1 = ra.right - board.left, x2 = rb.left - board.left;
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
          const left = e.side === 'left';
          const x1 = (left ? ra.left : ra.right) - board.left;
          const x2 = (left ? rb.left : rb.right) - board.left;
          const reach = Math.min(56, 16 + Math.abs(y2 - y1) * 0.25) * (left ? -1 : 1);
          d = 'M ' + x1 + ' ' + y1 +
              ' C ' + (x1 + reach) + ' ' + y1 +
              ', ' + (x2 + reach) + ' ' + y2 +
              ', ' + x2 + ' ' + y2;
        }

        const wire = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        // Every kind the pair relates by, so a line that is navigation among
        // other things still draws dashed.
        wire.setAttribute('class', 'wire ' + e.relations.map((r) => r.kind).join(' '));
        wire.dataset.from = e.from;
        wire.dataset.to = e.to;
        wire.setAttribute('d', d);
        const title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
        // The escape is doubled on purpose. This line lives inside the template
        // literal that *builds* the page, so a single backslash-n becomes a real
        // newline in the emitted JavaScript — inside a string literal, which stops
        // the whole script parsing and leaves the map blank.
        // (And no backticks in this comment: they would end the literal.)
        title.textContent = e.relations
          .map((r) => (r.reversed ? '← ' : '') + r.kind + (r.via ? ' (' + r.via + ')' : ''))
          .join('\\n');
        wire.appendChild(title);
        svg.appendChild(wire);
      }
      applyFocus();
    }

    fill('actors', DATA.actors);
    fill('state', DATA.state);
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
        const why = document.createElement('p');
        why.className = 'why';
        why.textContent = g.why;
        box.append(what, why);
      }
      document.getElementById('gaps').appendChild(box);
    }

    document.getElementById('refresh').addEventListener('click', () => vscode.postMessage({ type: 'refresh' }));
  </script>
</body>
</html>`;
}
