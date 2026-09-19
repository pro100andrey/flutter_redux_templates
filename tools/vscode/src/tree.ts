// The FRX tree view: the app's substates and routes, read from the CLI's
// `frx graph --json`. A substate expands into what belongs to it — its actions
// and selectors — and clicking any row opens its source. The item context menu
// offers "Add action…" (substates) and "Remove" (substates and routes).
// Monorepo only.
//
// One `graph` read backs the whole tree rather than a `list-*` call per group:
// the graph carries the same rows plus the facts a flat list drops (what a
// substate owns, whether a route is `initial`/`public`, which actions nothing
// dispatches). The result is cached per refresh — VSCode calls getChildren once
// per group and again per expanded node, and that is one process either way.
// The read happens at the refresh, not at the first question (see refresh()).
import * as fs from 'fs';
import * as vscode from 'vscode';

import { pushInto } from './collections';
import * as frx from './frx';
import * as naming from './naming';
import * as paths from './paths';
import * as queries from './queries';
import type { AppGraph, GraphNode } from './queries';
import type { ArtifactKind } from './ui';

/**
 * A tree row plus the extension's own metadata.
 *
 * Declared as a subclass rather than assigned onto a plain `vscode.TreeItem`:
 * the command handlers read `item.frxName` / `item.frxKind` off whatever the
 * context menu hands them, and a monkey-patched property is invisible to both
 * the compiler and the next reader.
 */
export class FrxTreeItem extends vscode.TreeItem {
  /** Set on the two top-level rows; identifies which list to expand. */
  groupKind?: 'substates' | 'routes';
  /** The artifact's base name, in the casing the CLI resolves. */
  frxName?: string;
  frxKind?: ArtifactKind;
  /** Set on a substate row: the id whose children are its actions/selectors. */
  substateOf?: string;
}

/**
 * A graph as read, with the two lookups every row asks computed once.
 *
 * The rows used to ask the graph directly — every substate row scanned all
 * the nodes to learn whether anything was under it, and every expansion
 * scanned them again for what, and rebuilt the orphan map. Small graphs never
 * noticed; the shape was quadratic in the nodes all the same.
 */
interface Read {
  graph: AppGraph;
  /** A substate's actions and selectors, in the graph's order, by its name. */
  owned: Map<string, GraphNode[]>;
  /** Why frx found nothing reaching a node, by node id. */
  why: Map<string, string>;
}

function read(graph: AppGraph): Read {
  return { graph, owned: ownedBySubstate(graph), why: orphanReasons(graph) };
}

export class FrxTreeProvider implements vscode.TreeDataProvider<FrxTreeItem> {
  private readonly _emitter = new vscode.EventEmitter<FrxTreeItem | undefined>();

  /** Fired to make VSCode re-query the tree. */
  readonly onDidChangeTreeData = this._emitter.event;

  private readonly root: string | null;

  /**
   * The in-flight or resolved graph for this refresh cycle, or null until the
   * first refresh. Holding the promise (not the value) means the several
   * getChildren calls one expansion triggers share a single CLI run.
   */
  private _graph: Promise<Read | null> | null = null;

  constructor(private readonly context: vscode.ExtensionContext) {
    this.root = paths.findWorkspaceRoot();
  }

  /**
   * Re-read the graph now, and tell VSCode the tree has changed.
   *
   * Now, not when VSCode next asks. Dropping the cache and leaving the read to
   * the next getChildren looked the same and was not: VSCode only asks a
   * section that is visible and expanded, and holds a hidden one's refresh
   * until it is opened. So a section collapsed at startup, or collapsed while
   * the last change landed, read the whole graph on the click that opened it
   * — a CLI run, then the rows — where the Dart extension's Dependencies beside
   * it had its rows the moment it opened. Read at the change, the rows are
   * there when the section is.
   */
  refresh(): Promise<void> {
    this._graph = this._load();
    this._emitter.fire(undefined);
    // Settled when the rows are, so a caller can wait for them; never rejects.
    return this._graph.then(() => undefined);
  }

  getTreeItem(element: FrxTreeItem): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: FrxTreeItem): Promise<FrxTreeItem[]> {
    if (!this.root) return [];
    if (!element) {
      return [
        this._group('Substates', 'substates', 'database'),
        this._group('Routes', 'routes', 'browser'),
      ];
    }

    const read = await this._read();
    if (!read) return [leaf('(frx unavailable — see FRX output)', 'warning')];
    const { graph, owned, why } = read;

    if (element.groupKind === 'substates') {
      return this._rows(
        graph.nodes.filter((n) => n.kind === 'substate'),
        (n) => this._substateItem(n, owned.has(n.name)),
      );
    }
    if (element.groupKind === 'routes') {
      return this._rows(
        graph.nodes.filter((n) => n.kind === 'page'),
        (n) => this._routeItem(n),
      );
    }
    if (element.substateOf) {
      const substate = graph.nodes.find((n) => n.id === `substate:${element.substateOf}`);
      const rows = (owned.get(element.substateOf) ?? []).map((n) =>
        n.kind === 'action'
          ? this._actionItem(n, why.has(n.id))
          : this._selectorItem(n, why.get(n.id)),
      );
      // The slice's own fields after what acts on it: a fifty-field slice
      // would otherwise push every action off the screen. Each carries the
      // graph's verdict on it — `field:setup.agentErrorOn  written, nothing
      // reads it` — the one thing about a field the source cannot say.
      for (const f of substate?.fields ?? []) {
        rows.push(this._fieldItem(substate!, f, why.get(`field:${substate!.name}.${f}`)));
      }
      return rows.length === 0 ? [leaf('(none)', 'info')] : rows;
    }
    return [];
  }

  /** The graph for this refresh cycle, read once and shared. */
  private _read(): Promise<Read | null> {
    return this._graph ?? (this._graph = this._load());
  }

  /**
   * One CLI read of the graph; null when there is no project, no frx, or the
   * read threw. A throw would otherwise be an unhandled rejection while the
   * section is collapsed and nothing awaits it; the null draws the "(frx
   * unavailable — see FRX output)" leaf, so the output is where the throw is
   * written, or the leaf would send the reader to a channel that says the
   * run went fine.
   */
  private async _load(): Promise<Read | null> {
    const root = this.root;
    if (!root) return null;
    try {
      const inv = await frx.resolveFrx(this.context, root);
      const graph = inv ? await queries.graph(inv, root) : null;
      return graph ? read(graph) : null;
    } catch (err) {
      frx.output().appendLine(`FRX: the tree could not read the graph — ${err}`);
      return null;
    }
  }

  /** Map rows to items, or a single "(none)" leaf when there are none. */
  private _rows(nodes: GraphNode[], make: (n: GraphNode) => FrxTreeItem): FrxTreeItem[] {
    if (nodes.length === 0) return [leaf('(none)', 'info')];
    return nodes.map(make);
  }


  private _group(
    label: string,
    groupKind: 'substates' | 'routes',
    icon: string,
  ): FrxTreeItem {
    const item = new FrxTreeItem(label, vscode.TreeItemCollapsibleState.Expanded);
    item.groupKind = groupKind;
    item.contextValue = 'frxGroup';
    item.iconPath = new vscode.ThemeIcon(icon);
    return item;
  }

  /** @param owns whether anything is under it — see `Read.owned` */
  private _substateItem(n: GraphNode, owns: boolean): FrxTreeItem {
    // Collapsible only when something is actually under it — an expand arrow
    // that opens onto "(none)" is a promise the row cannot keep. async_redux's
    // `wait` field owns nothing of ours, lists no fields, and stays a leaf.
    const expands = owns || (n.fields?.length ?? 0) > 0;
    const item = new FrxTreeItem(
      n.name,
      expands
        ? vscode.TreeItemCollapsibleState.Collapsed
        : vscode.TreeItemCollapsibleState.None,
    );
    item.description = n.type ?? '';
    item.contextValue = 'frxSubstate';
    item.frxName = n.name;
    item.frxKind = 'substate';
    item.substateOf = expands ? n.name : undefined;
    item.iconPath = new vscode.ThemeIcon('symbol-field');
    this._openOn(item, n);
    return item;
  }

  /** One field of a substate, marked when the graph says nothing reads it. */
  private _fieldItem(substate: GraphNode, field: string, dead?: string): FrxTreeItem {
    const item = new FrxTreeItem(field, vscode.TreeItemCollapsibleState.None);
    item.description = dead ?? '';
    item.contextValue = 'frxField';
    item.frxName = field;
    item.frxKind = 'field';
    item.iconPath = new vscode.ThemeIcon(dead ? 'warning' : 'symbol-variable');
    // The state file: every field of the slice is declared in it.
    this._openOn(item, { file: substate.file });
    return item;
  }

  private _routeItem(n: GraphNode): FrxTreeItem {
    const item = new FrxTreeItem(n.route ?? n.name, vscode.TreeItemCollapsibleState.None);
    item.description = routeDescription(n);
    item.contextValue = 'frxRoute';
    // Strip the generated `Route` suffix — `remove`/Casing expect the base name.
    item.frxName = naming.stripSuffix(n.route ?? n.name, 'Route');
    item.frxKind = 'page';
    item.iconPath = new vscode.ThemeIcon('browser');
    this._openOn(item, n);
    return item;
  }

  private _actionItem(n: GraphNode, orphan: boolean): FrxTreeItem {
    const item = new FrxTreeItem(n.name, vscode.TreeItemCollapsibleState.None);
    item.description = actionDescription(n, orphan);
    item.contextValue = 'frxAction';
    // A warning icon, not a squiggle: an action nothing dispatches is a fact
    // worth seeing, not a defect (the dispatcher may be the code you are about
    // to write), which is why `doctor` stays quiet about it.
    item.iconPath = new vscode.ThemeIcon(orphan ? 'warning' : 'zap');
    this._openOn(item, n);
    return item;
  }

  private _selectorItem(n: GraphNode, unused?: string): FrxTreeItem {
    // `SelectLogIn.isWaiting` → `isWaiting`: under its own substate the prefix
    // is the row above.
    const dot = n.name.lastIndexOf('.');
    const item = new FrxTreeItem(
      dot >= 0 ? n.name.slice(dot + 1) : n.name,
      vscode.TreeItemCollapsibleState.None,
    );
    item.description = unused ?? '';
    item.contextValue = 'frxSelector';
    // Same treatment as an unreached action, for the same reason: in a template
    // an unread selector can be API offered to whoever builds on it, so it is
    // shown rather than reported.
    item.iconPath = new vscode.ThemeIcon(unused ? 'warning' : 'symbol-property');
    this._openOn(item, n);
    return item;
  }

  /**
   * Wire a click-to-open on [item] for the node's source.
   *
   * Jumps to the declaration when the node says where it is: every selector in
   * the app shares one `selectors.dart`, so opening the file alone lands you at
   * the top and leaves you to find the getter yourself.
   */
  private _openOn(item: FrxTreeItem, n: Pick<GraphNode, 'file' | 'line' | 'column'>): void {
    if (!n.file || !fs.existsSync(n.file)) return;
    const uri = vscode.Uri.file(n.file);
    item.resourceUri = uri;
    item.command = {
      command: 'vscode.open',
      title: 'Open',
      arguments: [uri, selectionAt(n)],
    };
  }
}

/**
 * `vscode.open` options that put the cursor on the declaration, or undefined
 * when the node names no position (the file *is* the artifact — an action, a
 * page connector — and its top is the right landing).
 *
 * frx counts lines and columns from 1, the way an editor shows them; the API
 * counts from 0.
 */
export function selectionAt(
  n: Pick<GraphNode, 'line' | 'column'>,
): vscode.TextDocumentShowOptions | undefined {
  if (!n.line) return undefined;
  const at = new vscode.Position(n.line - 1, Math.max(0, (n.column ?? 1) - 1));
  return { selection: new vscode.Range(at, at) };
}

/**
 * The node kinds a substate owns — the one statement of it. The tree lists
 * them under the substate's row, and the map folds them into it (`picture`
 * draws an edge into one as an edge into the substate); the two used to each
 * spell the rule out, and a kind added to one alone either went unlisted or
 * threw on the page.
 */
export const OWNED_KINDS: ReadonlySet<string> = new Set(['action', 'selector']);

/**
 * Each substate's actions and selectors, in the graph's order, by the
 * substate's name.
 */
export function ownedBySubstate(graph: AppGraph): Map<string, GraphNode[]> {
  const owned = new Map<string, GraphNode[]>();
  for (const n of graph.nodes) {
    if (OWNED_KINDS.has(n.kind) && n.substate) pushInto(owned, n.substate, n);
  }
  return owned;
}

/**
 * The ids frx found nothing reaching, mapped to why, for per-row lookup —
 * actions nothing dispatches and selectors nothing reads.
 */
export function orphanReasons(graph: AppGraph): Map<string, string> {
  return new Map(graph.orphans.map((o) => [o.node, o.why]));
}

/** A route row's grey text: its path, plus what makes it special. */
export function routeDescription(n: GraphNode): string {
  const tags = [n.path, n.initial ? 'initial' : null, n.public ? 'public' : null].filter(
    Boolean,
  );
  return tags.join(' · ');
}

/** An action row's grey text: how it runs, and whether anything reaches it. */
export function actionDescription(n: GraphNode, orphan: boolean): string {
  const tags = [
    n.isAsync ? 'async' : null,
    ...(n.mixins ?? []),
    n.throwsUserException ? 'throws' : null,
    orphan ? 'nothing dispatches' : null,
  ].filter(Boolean);
  return tags.join(' · ');
}

function leaf(label: string, icon: string): FrxTreeItem {
  const item = new FrxTreeItem(label, vscode.TreeItemCollapsibleState.None);
  item.iconPath = new vscode.ThemeIcon(icon);
  return item;
}
