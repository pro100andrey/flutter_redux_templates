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
// The picture's types live in `page/picture.d.ts`, which the page script reads
// too: one contract, checked on both sides of the webview boundary.
import type { Picture, PictureEdge, PictureNode, Relation, Side } from './page/picture';
import { OWNED_KINDS, actionLabel, ownedBySubstate, selectionAt } from './tree';

export type { Picture, PictureNode } from './page/picture';

/** Node kinds that act on state rather than being state. */
const ACTOR_KINDS = new Set(['page', 'service', 'persistor', 'consumer']);

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

  const view = (panel ??= openPanel(context));

  // One read. The two list reads it replaces carried strictly less: no edges, no
  // ownership, and nothing about what frx could not follow.
  //
  // What the read comes back to is checked, not assumed. The panel can be
  // closed while `frx graph` runs — seconds on the `dart run` fallback — and
  // drawing into it threw "Cannot read properties of null"; and a ↻ clicked
  // twice starts two reads, of which the older may land last.
  const read = ++_reads;
  const graph = await queries.graph(inv, root);
  if (panel !== view || read !== _reads) return;

  if (!graph) {
    // A failed read used to be drawn as an app with nothing in it — the one
    // picture that is certainly wrong, and indistinguishable from an empty
    // project. The last picture stays; the first read has none to keep.
    if (!view.webview.html) view.webview.html = unreadableHtml();
    frx.output().show(true);
    vscode.window.showErrorMessage(
      'FRX: the Map could not read the app graph (`frx graph` failed) — see the FRX output.',
    );
    return;
  }

  const asset = (name: string) =>
    view.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'media', 'map', name)).toString();
  view.webview.html = buildHtml(picture(graph, root), {
    css: asset('map.css'),
    js: asset('map.js'),
    cspSource: view.webview.cspSource,
  });
  view.reveal();
}

/** Bumped per graph read, so only the newest one draws. */
let _reads = 0;

function openPanel(context: vscode.ExtensionContext): vscode.WebviewPanel {
  const created = vscode.window.createWebviewPanel(
    'frxMap',
    'FRX Map',
    vscode.ViewColumn.Active,
    {
      enableScripts: true,
      retainContextWhenHidden: true,
      // The page's stylesheet and script live under media/; nothing else of
      // the extension's is the webview's to read.
      localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')],
    },
  );
  created.onDidDispose(() => {
    if (panel === created) panel = null;
  });
  created.webview.onDidReceiveMessage((m) => {
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
  return created;
}

/** What a Map whose first read failed shows: a sentence, and nothing to run. */
function unreadableHtml(): string {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none';" />
</head>
<body>
  <p>frx could not read the app graph, so there is no picture to draw. The FRX output says why; run “FRX: Map” again once it is fixed.</p>
</body>
</html>`;
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

  const owned = ownedBySubstate(graph);

  const state: PictureNode[] = [];
  const actors: PictureNode[] = [];
  for (const n of graph.nodes) {
    if (n.kind === 'substate') {
      state.push({
        ...leaf(n, n.type ?? ''),
        owned: (owned.get(n.name) ?? []).map((c) => leaf(c, c.kind)),
      });
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
  // Where a fold pointed at a row that is not drawn. An action's substate is
  // the folder it sits in, and the CLI does not check that `AppState` still
  // composes it — the doctor reports that as an orphan — so an edge into an
  // orphan folds to a substate no column has. Drawn, it was a line to nowhere
  // that threw on the page's first draw and took the hover, the refresh and
  // the gaps box with it. It is a gap, and goes where the gaps go.
  const dangling: Picture['gaps'] = [];
  for (const e of graph.edges) {
    const from = drawnAs(e.from);
    const to = drawnAs(e.to);
    if (!from || !to || from === to) continue;
    const missing = [from, to].find((id) => !inState.has(id) && !inActors.has(id));
    if (missing) {
      dangling.push({
        what: `${e.kind}  ${e.from} → ${e.to}`,
        at: '',
        why: `folds onto ${missing}, which the picture does not draw — a substate AppState no longer composes?`,
      });
      continue;
    }
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
    // is drawn to the substate, and the pane says which one it was. The target
    // first, when both moved — an action that dispatches another substate's
    // action is a line between two substates, and what it names is the action
    // dispatched, not the one dispatching.
    const folded = e.to !== to ? e.to : e.from !== from ? e.from : undefined;
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
    gaps: [
      ...graph.unresolved.map((u) => ({
        what: [u.kind, u.expr].filter(Boolean).join('  '),
        at: u.at ? relativeTo(root, u.at) : '',
        why: u.why,
      })),
      ...dangling,
    ],
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

/**
 * A graph node as a drawable leaf. A selector sheds its `Select…` qualifier;
 * an action keeps whatever its id carries past the substate — a private step
 * is `InstallSkillsAction._AgentWorking`, because two files in one substate
 * can each declare an `_AgentWorking`, and two rows titled alike read as one
 * artifact drawn twice.
 */
function leaf(n: GraphNode, subtitle: string): PictureNode {
  const title =
    n.kind === 'selector'
      ? (n.name.split('.').pop() ?? n.name)
      : n.kind === 'action'
        ? actionLabel(n)
        : n.name;
  return {
    id: n.id,
    kind: n.kind,
    title,
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
/** The URIs the page loads its stylesheet and script from, as the webview sees them. */
export interface PageAssets {
  css: string;
  js: string;
  /**
   * The origin the webview may load resources from — `webview.cspSource`. Empty
   * in a test, where nothing is loaded; the policy still names it.
   */
  cspSource: string;
}

/**
 * Build the webview HTML: two columns of nodes with the relations drawn between,
 * and a pane beside them that says in words what the focused row's lines mean.
 *
 * The page's stylesheet and script are files under `media/map/`, loaded by URI;
 * this builds the skeleton they attach to and hands them the picture as a JSON
 * block. Pure: the same picture, assets and nonce give the same page, which is
 * what lets a test read it. The nonce is generated when the caller passes none.
 */
export function buildHtml(
  data: Picture,
  assets: PageAssets = { css: 'map.css', js: 'map.js', cspSource: '' },
  nonce: string = crypto.randomBytes(16).toString('base64'),
): string {
  // Embed as JSON, with `<` neutralized so a value can never close the block.
  // `crossings` stays out: it is what the ordering achieved, which the tests
  // assert and the drawing has no use for.
  const { crossings: _crossings, ...drawable } = data;
  const json = JSON.stringify(drawable).replace(/</g, '\\u003c');

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; style-src ${assets.cspSource}; script-src 'nonce-${nonce}';" />
<link rel="stylesheet" href="${assets.css}" />
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
  <script type="application/json" id="picture" nonce="${nonce}">${json}</script>
  <script nonce="${nonce}" src="${assets.js}"></script>
</body>
</html>`;
}
