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
import * as fs from 'fs';
import * as vscode from 'vscode';

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

export class FrxTreeProvider implements vscode.TreeDataProvider<FrxTreeItem> {
  private readonly _emitter = new vscode.EventEmitter<FrxTreeItem | undefined>();

  /** Fired to make VSCode re-query the tree. */
  readonly onDidChangeTreeData = this._emitter.event;

  private readonly root: string | null;

  /**
   * The in-flight or resolved graph for this refresh cycle, or null when a
   * fresh read is due. Holding the promise (not the value) means the several
   * getChildren calls one expansion triggers share a single CLI run.
   */
  private _graph: Promise<AppGraph | null> | null = null;

  constructor(private readonly context: vscode.ExtensionContext) {
    this.root = paths.findWorkspaceRoot();
  }

  refresh(): void {
    this._graph = null;
    this._emitter.fire(undefined);
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

    const graph = await this._read();
    if (!graph) return [leaf('(frx unavailable — see FRX output)', 'warning')];

    if (element.groupKind === 'substates') {
      return this._rows(
        graph.nodes.filter((n) => n.kind === 'substate'),
        (n) => this._substateItem(n, graph),
      );
    }
    if (element.groupKind === 'routes') {
      return this._rows(
        graph.nodes.filter((n) => n.kind === 'page'),
        (n) => this._routeItem(n),
      );
    }
    if (element.substateOf) {
      const owner = element.substateOf;
      const why = orphanReasons(graph);
      return this._rows(
        graph.nodes.filter(
          (n) => (n.kind === 'action' || n.kind === 'selector') && n.substate === owner,
        ),
        (n) =>
          n.kind === 'action'
            ? this._actionItem(n, why.has(n.id))
            : this._selectorItem(n, why.get(n.id)),
      );
    }
    return [];
  }

  /** The graph for this refresh cycle, read once and shared. */
  private _read(): Promise<AppGraph | null> {
    if (this._graph) return this._graph;
    const root = this.root;
    if (!root) return Promise.resolve(null);
    this._graph = (async () => {
      const inv = await frx.resolveFrx(this.context, root);
      return inv ? queries.graph(inv, root) : null;
    })();
    return this._graph;
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

  private _substateItem(n: GraphNode, graph: AppGraph): FrxTreeItem {
    // Collapsible only when something is actually under it — an expand arrow
    // that opens onto "(none)" is a promise the row cannot keep. async_redux's
    // `wait` field owns nothing of ours and stays a leaf.
    const owns = graph.nodes.some(
      (c) => (c.kind === 'action' || c.kind === 'selector') && c.substate === n.name,
    );
    const item = new FrxTreeItem(
      n.name,
      owns
        ? vscode.TreeItemCollapsibleState.Collapsed
        : vscode.TreeItemCollapsibleState.None,
    );
    item.description = n.type ?? '';
    item.contextValue = 'frxSubstate';
    item.frxName = n.name;
    item.frxKind = 'substate';
    item.substateOf = owns ? n.name : undefined;
    item.iconPath = new vscode.ThemeIcon('symbol-field');
    this._openOn(item, n);
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
