// The extension's single window onto the frx CLI's machine-readable output.
//
// Every `--json` read and every parse of frx's create/overwrite plan lives here,
// so the CLI's contract (command names, JSON shapes, plan format) is encoded in
// exactly one place. The tree, the map, the doctor diagnostics, the F2 rename
// and the substate pickers all read through these helpers instead of each
// re-spawning frx and re-parsing its output.
import * as path from 'path';

import * as frx from './frx';
import type { Invocation } from './frx';

/**
 * One change of a writing command's `--json` changeset.
 *
 * An open shape on purpose: the format's compatibility rule is additive-only with
 * no version number, and a consumer must ignore fields it does not recognise.
 */
export interface PlanChange {
  op: 'create' | 'overwrite' | 'edit' | 'delete' | 'delete-directory' | 'move';
  /** Absolute path the operation is about — a move's destination. */
  path: string;
  /** A move's source. */
  from?: string;
  /** A unified diff, for the operations that have textual change to show. */
  diff?: string;
}

/**
 * A writing command's machine result: the changeset, plus whether it happened.
 *
 * One shape in two states — `applied: false` is a plan, `true` is what was done.
 * The extension only ever reads the planned state, since it previews before
 * applying.
 */
export interface WritePlan {
  command: string;
  applied: boolean;
  changes: PlanChange[];
}

/**
 * Parse a writing command's `--json` output.
 *
 * Null when the output is not a changeset — a failed run, or an frx too old to
 * emit one. The caller falls back to reporting the CLI's own message.
 */
export function parseWritePlan(stdout: string): WritePlan | null {
  try {
    const data = JSON.parse(stdout) as WritePlan;
    return Array.isArray(data?.changes) ? data : null;
  } catch {
    return null;
  }
}

/** A row of `frx list-substates --json`. */
export interface SubstateRow {
  field: string;
  type: string;
  file: string | null;
}

/** A row of `frx list-routes --json`. */
export interface RouteRow {
  route: string;
  path: string | null;
  connector: string | null;
}

/**
 * One artifact of `frx graph --json`. The declared fields are the ones the
 * extension reads; the CLI emits kind-specific extras alongside them (see
 * `graph_model.dart`), which is why this is an open shape.
 */
export interface GraphNode {
  /** `substate:session`, `action:logIn.SetEmailAction`, `page:home`. */
  id: string;
  kind: 'substate' | 'action' | 'page' | 'selector' | 'service' | 'persistor' | 'consumer';
  /** The bare name — qualified ids keep `SetEmailAction` distinguishable. */
  name: string;
  /** Set on actions and selectors: the substate they belong to. */
  substate?: string;
  file?: string | null;
  /** Where in `file` it is declared, 1-based, when the file holds several. */
  line?: number;
  column?: number;
  /** False when frx saw the artifact referenced but could not find its source. */
  resolved?: boolean;
  /** substates */
  type?: string;
  /** actions */
  mixins?: string[];
  isAsync?: boolean;
  throwsUserException?: boolean;
  /** pages */
  route?: string;
  path?: string;
  parent?: string;
  initial?: boolean;
  public?: boolean;
}

/** What `frx graph --json` could not follow, or found nothing pointing at. */
export interface GraphGap {
  node: string;
  why: string;
}

/** One relation between two nodes — see `EdgeKind` in `graph_model.dart`. */
export interface GraphEdge {
  from: string;
  to: string;
  kind: 'writes' | 'dispatches' | 'navigates' | 'reads' | 'restores' | 'waitsFor' | 'uses';
  /** What triggers it — a callback, a `copyWith` field list, a getter name. */
  via?: string;
  condition?: string;
  inferred?: boolean;
}

/**
 * Something frx saw but could not follow.
 *
 * Carried into the structural picture rather than dropped, for the reason the CLI
 * gives for naming them at all: without them, a connection frx failed to parse
 * looks exactly like a connection that is not there — and a diagram reads as
 * exhaustive, so it owes the reader that statement more than a list does.
 */
export interface GraphUnresolved {
  kind: string;
  why: string;
  /** The node whose reading hit the gap. */
  owner: string;
  at?: string;
  expr?: string;
}

/** The whole app as one object — see `frx graph --json`. */
export interface AppGraph {
  nodes: GraphNode[];
  edges: GraphEdge[];
  unresolved: GraphUnresolved[];
  orphans: GraphGap[];
}

/** A finding of `frx doctor --json`. `fix` names the remedy `--fix` applies. */
export interface DoctorFinding {
  severity: 'error' | 'warn';
  message: string;
  file: string | null;
  fix: 'build_runner' | 'orphan' | 'flow-docs' | null;
}

/** A match of `frx which <word> --json`. */
export interface WhichMatch {
  kind: string;
  name: string;
  suffix: string | null;
  prefix: string | null;
}

/**
 * Run a `<command> --json --root <root>` invocation and return the parsed
 * object, or null on any failure (frx unavailable / non-JSON output).
 *
 * The return is deliberately `any`: this is the untyped boundary where another
 * process's JSON enters. Every exported helper below narrows it to a declared
 * shape, so the `any` never escapes this module.
 *
 * @param ignoreCode parse even on a non-zero exit — `doctor` exits 1 when it
 *   finds issues but still prints valid JSON.
 */
async function _json(
  inv: Invocation,
  args: string[],
  root: string,
  ignoreCode = false,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any> {
  const res = await frx.run(inv, [...args, '--json', '--root', root], root);
  if (!ignoreCode && res.code !== 0) return null;
  try {
    return JSON.parse(res.stdout);
  } catch {
    return null;
  }
}

/**
 * All AppState substates, or null when frx couldn't be read. An empty array
 * means "read fine, no substates" — callers that need to distinguish
 * "unavailable" from "none" check for null.
 */
export async function listSubstates(inv: Invocation, root: string): Promise<SubstateRow[] | null> {
  const data = await _json(inv, ['list-substates'], root);
  return Array.isArray(data?.substates) ? data.substates : null;
}

/**
 * All routes, or null when frx couldn't be read (empty array = read fine, no
 * routes).
 */
export async function listRoutes(inv: Invocation, root: string): Promise<RouteRow[] | null> {
  const data = await _json(inv, ['list-routes'], root);
  return Array.isArray(data?.routes) ? data.routes : null;
}

/**
 * The whole app as one graph, or null when frx couldn't be read.
 *
 * Subsumes `listSubstates` + `listRoutes` — the same rows plus what belongs to
 * each substate (its actions and selectors) and the facts the two list commands
 * don't carry (a route's `initial`/`public`, an action nothing dispatches). One
 * read instead of two, and the tree can go a level deeper.
 */
export async function graph(inv: Invocation, root: string): Promise<AppGraph | null> {
  const data = await _json(inv, ['graph'], root);
  if (!Array.isArray(data?.nodes)) return null;
  return {
    nodes: data.nodes,
    edges: Array.isArray(data.edges) ? data.edges : [],
    unresolved: Array.isArray(data.unresolved) ? data.unresolved : [],
    orphans: Array.isArray(data.orphans) ? data.orphans : [],
  };
}

/**
 * The parsed `frx doctor --json` object, or null when there's no JSON to read
 * (e.g. project-not-found, exit 70). Exit 1 ("issues found") still yields it.
 */
export function doctor(
  inv: Invocation,
  root: string,
): Promise<{ findings: DoctorFinding[] } | null> {
  return _json(inv, ['doctor'], root, true);
}

/**
 * What artifact an identifier belongs to (`frx which <word> --json`): the match
 * for a wired substate or page, else null. The authoritative token → artifact
 * map lives in the CLI, so the extension never re-encodes the conventions.
 */
export async function which(
  inv: Invocation,
  word: string,
  root: string,
): Promise<WhichMatch | null> {
  const m = await _json(inv, ['which', word], root);
  return m && m.kind ? m : null;
}

/**
 * The mermaid `sequenceDiagram` for a page's use cases (`frx flow <page>`),
 * read from the AST. Null when the page has no connector or frx failed — the
 * caller surfaces the CLI's own message from the output channel.
 */
export async function flow(inv: Invocation, page: string, root: string): Promise<string | null> {
  const res = await frx.run(inv, ['flow', page, '--root', root], root);
  return res.code === 0 ? res.stdout.trim() : null;
}

/**
 * The mermaid `flowchart` of the whole app — every registered screen and the
 * navigation between them (`frx flow --routes`). Null when frx failed.
 */
export async function routeMap(inv: Invocation, root: string): Promise<string | null> {
  const res = await frx.run(inv, ['flow', '--routes', '--root', root], root);
  return res.code === 0 ? res.stdout.trim() : null;
}

/** One async_redux behaviour mixin, from `frx list-mixins --json`. */
export interface ActionMixin {
  name: string;
  /** The identifier in the generated `with` clause. */
  clause: string;
  /** One line on what it does. */
  summary: string;
  /** A mixin this one is declared `on`, added automatically. */
  implies: string | null;
  /**
   * Every mixin it cannot be combined with, implications already folded in —
   * `noDialog` excludes `abortWhenNoInternet` through the `checkInternet` it
   * implies. Precomputed by the CLI so a picker filters by set membership
   * rather than re-deriving async_redux's rule.
   */
  conflictsWith: string[];
}

/**
 * The mixins `add-action` can attach, or null when frx couldn't be read.
 *
 * Read rather than hardcoded: the editor kept its own list, and it had drifted
 * to eight of the ten.
 */
export async function listMixins(inv: Invocation, root: string): Promise<ActionMixin[] | null> {
  const data = await _json(inv, ['list-mixins'], root);
  return Array.isArray(data?.mixins) ? data.mixins : null;
}

/** What `frx list-widget-dirs --json` knows about widget folders. */
export interface WidgetDirs {
  /** Folders under `ui/lib/` that already hold widgets, sorted. */
  dirs: string[];
  /** Where each `--kind` usually goes, so a picker can offer it first. */
  home: Record<string, string>;
}

/**
 * The folders `add-widget --dir` suggests, or null when frx couldn't be read.
 *
 * A suggestion, not the allowed set — `--dir` also takes a name that does not
 * exist yet and creates the folder, which is why the picker offers the typed
 * value as its own row.
 */
export async function listWidgetDirs(inv: Invocation, root: string): Promise<WidgetDirs | null> {
  const data = await _json(inv, ['list-widget-dirs'], root);
  if (!Array.isArray(data?.dirs)) return null;
  return { dirs: data.dirs, home: data.home ?? {} };
}

/**
 * A file frx reported creating/overwriting whose path ends with `suffix`,
 * parsed from its plan and resolved against `baseDir` (the run's cwd). Returns
 * null if the plan mentions no such file.
 */
export function createdFile(stdout: string, baseDir: string, suffix: string): string | null {
  const esc = suffix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = stdout.match(new RegExp(`^\\s*(?:create|overwrite)\\s+(\\S.*${esc})\\s*$`, 'm'));
  return m ? path.resolve(baseDir, m[1].trim()) : null;
}

/** The `_state.dart` file frx just wrote (the substate file you edit next). */
export function createdStateFile(stdout: string, baseDir: string): string | null {
  return createdFile(stdout, baseDir, '_state.dart');
}
