/// The whole app as one graph: substates, actions, pages, selectors and
/// services, plus the relations between them.
///
/// Everything here is read parse-only, like the rest of frx. The point of this
/// model over the per-page [PageFlow] and the app-wide [RouteMap] is not new
/// data — it is *joined* data with the seams named: a consumer gets one object
/// instead of six, and the places frx could not follow arrive as [Unresolved]
/// entries rather than as edges that silently do not exist.
library;

/// What an artifact is. The node id is `<kind>:<name>`, and for artifacts that
/// belong to a substate the name is qualified with it — `SetEmailAction` alone
/// is not an identifier, this repo has three of them.
enum NodeKind {
  substate,
  action,
  page,
  selector,
  service,
  persistor,

  /// Reads state but is neither a screen nor a service — a `StoreConnector` no
  /// route registers, like the one `MaterialApp.builder` wraps everything in.
  /// Here for the same reason [service] is: walking the router finds only what
  /// a route reaches, so a consumer outside it reads as nobody, and every
  /// selector it alone uses reads as dead.
  consumer,
}

/// One artifact in the graph.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.kind,
    required this.name,
    this.substate,
    this.file,
    this.line,
    this.column,
    this.resolved = true,
    this.fields = const {},
  });

  /// `action:logIn.SetEmailAction`, `page:logIn`, `substate:session`.
  final String id;

  final NodeKind kind;

  /// The bare name — `SetEmailAction`, `logIn`, `ConnectivityDispatcher`.
  final String name;

  /// The substate this belongs to, for actions and selectors.
  final String? substate;

  /// Absolute path, when the artifact has a file of its own.
  final String? file;

  /// Where in [file] the artifact is declared, 1-based, when the file holds
  /// more than the one artifact. A selectors facade holds every selector in the
  /// app, so opening it at the top answers "which file" and not "which one".
  final int? line;
  final int? column;

  /// False when frx saw the artifact referenced but could not find its source —
  /// a dispatch of something that is not a `*Action` class, say. The node is
  /// still emitted so the edge pointing at it is not silently dropped; the
  /// matching [Unresolved] entry says why.
  final bool resolved;

  /// Kind-specific detail: `mixins`/`isAsync` for actions, `route`/`path` for
  /// pages, `type` for substates.
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    if (substate != null) 'substate': substate,
    if (file != null) 'file': file,
    if (line != null) 'line': line,
    if (column != null) 'column': column,
    if (!resolved) 'resolved': false,
    ...fields,
  };
}

/// How two artifacts relate.
enum EdgeKind {
  /// An action writes a substate (`state.copyWith…`).
  writes,

  /// A page, action or service dispatches an action.
  dispatches,

  /// A page reaches another page (`GoAction.push`/`pop`).
  navigates,

  /// A selector or the persistor reads a substate.
  reads,

  /// The persistor puts a substate back on boot, building it from storage
  /// rather than dispatching. It changes state without an action, so a graph
  /// that only follows dispatches answers "who can change this" wrongly.
  restores,

  /// A selector reports an action's wait status (`isWaitingForType<X>`) — the
  /// reference that makes deleting the action break the selector.
  waitsFor,

  /// A connector, action, service or another selector calls a selector. The
  /// only edge that points *into* a selector, and so the only way to ask which
  /// ones nothing reads.
  uses,
}

/// One relation between two nodes.
class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    required this.kind,
    this.via,
    this.condition,
    this.inferred = false,
  });

  final String from;
  final String to;
  final EdgeKind kind;

  /// What triggers it — a view-model callback, a `copyWith` field list, the
  /// getter name on a selector.
  final String? via;

  /// The `if` guarding it, when there is one.
  final String? condition;

  /// True when the target was deduced rather than read — see
  /// `RouteMap`'s pop resolution.
  final bool inferred;

  /// Identity for de-duplication: two callbacks dispatching the same action
  /// contribute the same relation twice.
  String get key => '$from|$to|${kind.name}|$via|$condition';

  Map<String, Object?> toJson() => {
    'from': from,
    'to': to,
    'kind': kind.name,
    if (via != null) 'via': via,
    if (condition != null) 'condition': condition,
    if (inferred) 'inferred': true,
  };
}

/// Something frx saw but could not resolve.
///
/// This is the part a consumer cannot reconstruct: without it, a connection frx
/// failed to follow is indistinguishable from a connection that is not there,
/// and an agent reading the graph would conclude the latter.
class Unresolved {
  const Unresolved({
    required this.kind,
    required this.why,
    required this.owner,
    this.at,
    this.expr,
  });

  /// `dispatch-target`, `pop-destination`, `route-connector`.
  final String kind;

  /// Why frx stopped, in a sentence a human or an agent can act on.
  final String why;

  /// The node whose reading hit the gap — `page:logIn`, `selector:logIn.email`.
  ///
  /// What makes a gap attributable, and therefore what lets [AppGraph.focusOn]
  /// keep only the ones belonging to the subgraph it returns. [at] cannot do it:
  /// it is a display string, and across the readers it has been a file path, a
  /// node id and a route class name.
  final String owner;

  /// The file to go read. No line number: the parse-only readers do not carry
  /// offsets, and inventing one would be worse than omitting it.
  final String? at;

  /// The source expression, when there is one to quote.
  final String? expr;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'why': why,
    'owner': owner,
    if (at != null) 'at': at,
    if (expr != null) 'expr': expr,
  };
}

/// Which way an edge is followed out of the focus.
///
/// The distinction is load-bearing rather than cosmetic. The persistor and the
/// top-level connector are **hub** nodes: an undirected walk through one joins
/// substates that have nothing to do with each other, because the persistor
/// touches all of them. Direction is what excludes them.
enum GraphDirection {
  /// Edges pointing *at* the focus, followed backwards — "what breaks if I
  /// touch this". Text search finds occurrences and cannot say that changing a
  /// session token reaches a selector, then a composite selector, then the auth
  /// guard; the type analyzer knows types, not Redux semantics.
  inbound,

  /// Edges leading *out of* the focus — what it reaches.
  outbound,

  /// Both, which is what a focused read has always done.
  both;

  static GraphDirection parse(String value) =>
      GraphDirection.values.byName(value);
}

/// How a graph was narrowed, when it was.
///
/// Emitted with the graph because an impact answer is read as exhaustive, so a
/// silently truncated dependency list looks exactly like a short one. [depth]
/// null means the walk ran until it closed.
class GraphFocus {
  const GraphFocus({
    required this.node,
    required this.direction,
    required this.depth,
    required this.truncated,
  });

  final String node;
  final GraphDirection direction;

  /// Hops followed, or null when unbounded.
  final int? depth;

  /// Whether the bound stopped the walk while there was still more to reach —
  /// the one fact that turns a short answer into an honest one.
  final bool truncated;

  Map<String, Object?> toJson() => {
    'node': node,
    'direction': direction.name,
    'depth': depth,
    'truncated': truncated,
  };
}

/// The joined graph.
class AppGraph {
  const AppGraph({
    required this.nodes,
    required this.edges,
    this.unresolved = const [],
    this.focus,
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<Unresolved> unresolved;

  /// How this graph was narrowed, or null when it is the whole app.
  final GraphFocus? focus;

  GraphNode? node(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Artifacts nothing reaches, each with the reason — actions nothing
  /// dispatches, selectors nothing reads.
  ///
  /// Not an error by itself: either can be reached from somewhere frx does not
  /// read, and in a template a selector can be API offered to whoever builds on
  /// it. But in a repo where frx wrote the callers, it usually means dead code.
  List<({GraphNode node, String why})> get orphans {
    // Read once: `_dispatched` is a getter that rescans every edge, and inside
    // the comprehension it was rebuilt for each node in turn.
    final dispatched = _dispatched;
    return [
      for (final n in nodes)
        if (n.kind == NodeKind.action &&
            n.resolved &&
            !dispatched.contains(n.id))
          (node: n, why: 'no dispatcher found'),
      ...deadSelectors,
    ];
  }

  Set<String> get _dispatched => {
    for (final e in edges)
      if (e.kind == EdgeKind.dispatches) e.to,
  };

  /// Selectors no live consumer reaches.
  ///
  /// Reachability, not in-degree: a selector read only by another selector that
  /// nothing reads is dead just the same, and counting callers would report the
  /// chain as healthy. Live roots are the `uses` edges that come from something
  /// other than a selector — a connector, an action, a service.
  List<({GraphNode node, String why})> get deadSelectors {
    final selectors = {
      for (final n in nodes)
        if (n.kind == NodeKind.selector) n.id,
    };
    final usedBy = <String, Set<String>>{};
    for (final e in edges) {
      if (e.kind == EdgeKind.uses) {
        usedBy.putIfAbsent(e.to, () => {}).add(e.from);
      }
    }

    // Seed with the selectors a non-selector reads, then follow `uses` inward
    // until nothing new goes live. Bounded by the selector count: each pass
    // adds at least one, or stops.
    final live = <String>{
      for (final entry in usedBy.entries)
        if (entry.value.any((from) => !selectors.contains(from))) entry.key,
    };
    for (var pass = 0; pass < selectors.length; pass++) {
      final before = live.length;
      for (final entry in usedBy.entries) {
        if (entry.value.any(live.contains)) live.add(entry.key);
      }
      if (live.length == before) break;
    }

    return [
      for (final n in nodes)
        if (n.kind == NodeKind.selector && !live.contains(n.id))
          (
            node: n,
            why: usedBy.containsKey(n.id)
                ? 'read only by selectors nothing reads'
                : 'nothing reads it',
          ),
    ];
  }

  /// The subgraph within [depth] hops of [id] — "show me everything around the
  /// login screen", or, with [GraphDirection.inbound], "what breaks if I touch
  /// this".
  ///
  /// [depth] null follows the edges until the set closes. Unbounded is the
  /// sensible default for an impact question and terminates for the same reason
  /// a bounded one does: the node set is finite and each pass either grows it or
  /// stops.
  AppGraph focusOn(
    String id, {
    int? depth = 1,
    GraphDirection direction = GraphDirection.both,
  }) {
    Set<String> expand(Set<String> from) {
      final next = {...from};
      for (final e in edges) {
        if (direction != GraphDirection.inbound && from.contains(e.from)) {
          next.add(e.to);
        }
        if (direction != GraphDirection.outbound && from.contains(e.to)) {
          next.add(e.from);
        }
      }
      return next;
    }

    var reached = {id};
    var closed = false;
    for (var i = 0; depth == null || i < depth; i++) {
      final next = expand(reached);
      if (next.length == reached.length) {
        closed = true;
        break;
      }
      reached = next;
    }
    // One hop past the bound, to tell "there was nothing more" from "the bound
    // stopped me" — which is the difference between a short answer and a wrong
    // one.
    final truncated = !closed && expand(reached).length > reached.length;

    return AppGraph(
      nodes: [
        for (final n in nodes)
          if (reached.contains(n.id)) n,
      ],
      edges: [
        for (final e in edges)
          if (reached.contains(e.from) && reached.contains(e.to)) e,
      ],
      // Scoped to the subgraph. Kept whole, a gap belonging to an unrelated page
      // was reported against whatever you focused, which misattributes it — and
      // the one thing this list exists to do is say where the answer is
      // incomplete.
      unresolved: [
        for (final u in unresolved)
          if (reached.contains(u.owner)) u,
      ],
      focus: GraphFocus(
        node: id,
        direction: direction,
        depth: depth,
        truncated: truncated,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    'unresolved': [for (final u in unresolved) u.toJson()],
    'orphans': [
      for (final o in orphans) {'node': o.node.id, 'why': o.why},
    ],
    if (focus != null) 'focus': focus!.toJson(),
  };
}
