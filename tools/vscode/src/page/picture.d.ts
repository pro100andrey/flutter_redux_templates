// What the FRX Map draws — the contract between `src/map.ts`, which folds the
// wiring graph into it, and `src/page/map.ts`, the page script that draws it.
//
// A declaration file rather than a module with code, because it is read by two
// programs that emit to different places: the extension (CommonJS, into `out/`)
// and the page (a plain script, into `media/map/`). A `.d.ts` is included by
// both and emitted by neither, so the page's build cannot leave a stray
// `picture.js` beside the page.

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
export type Side = 'across' | 'left' | 'right';

/** One relation between two nodes: what kind, what triggers it, which way it runs. */
export interface Relation {
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
export interface PictureEdge {
  from: string;
  to: string;
  relations: Relation[];
  /**
   * `across` the middle, or out into the margin on its own side.
   *
   * Decided in `map.ts` rather than in the webview so it can be tested, and so
   * the drawing stays a drawing. An edge joining two nodes of one column has no
   * business crossing the middle: drawn straight it leaves a node's right edge
   * and enters a neighbour's left edge in the *same* column, looping across the
   * whole canvas and crossing everything in between.
   */
  side: Side;
}

/** Where the picture's own edges are incomplete. */
export interface PictureGap {
  /** The kind of gap and the expression that hit it. */
  what: string;
  /** The file, relative to the repo when the root is known — or ''. */
  at: string;
  why: string;
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
  gaps: PictureGap[];
  /** How many pairs of edges cross the middle, after ordering. */
  crossings: number;
}

/** What the page remembers across a refresh, through the webview's state. */
export interface PageState {
  /** The rows whose regions are folded. */
  folded?: string[];
  /** The pinned row, or null. */
  pinned?: string | null;
  /** Which column the last draw placed — 0 actors, 1 state, -1 neither yet. */
  placed?: number;
}

/** What the page sends the editor. */
export type PageMessage =
  | { type: 'open'; file: string; line?: number; column?: number }
  | { type: 'refresh' };
