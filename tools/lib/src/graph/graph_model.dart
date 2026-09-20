/// The whole app as one graph: substates, actions, pages, selectors and
/// services, plus the relations between them.
///
/// Everything here is read parse-only, like the rest of frx. The point of this
/// model over the per-page [PageFlow] and the app-wide [RouteMap] is not new
/// data — it is *joined* data with the seams named: a consumer gets one object
/// instead of six, and the places frx could not follow arrive as [Unresolved]
/// entries rather than as edges that silently do not exist.
library;

import '../flow/flow_model.dart' show PageFlow;
import '../flow/route_map.dart' show RouteMap;

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

  /// One field of a substate — `session.token`.
  ///
  /// **Never among [AppGraph.nodes].** A field is a place on a substate, and
  /// the graph draws it as the `via` of the edges into the substate rather
  /// than as a node of its own: a fifty-field slice would be fifty nodes, and
  /// every consumer of the graph would have to fold them back. The kind
  /// exists so the orphan list can name one — [AppGraph.deadFields] — with
  /// the same record every other orphan has.
  field,
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

  /// A selector, an action, a connector or the persistor reads a substate.
  /// `via` is the place read — `session.token`, or `session` for the whole
  /// slice — which is what a focus on one field keeps or drops the edge by.
  reads,

  /// The persistor puts a substate back on boot, building it from storage
  /// rather than dispatching. It changes state without an action, so a graph
  /// that only follows dispatches answers "who can change this" wrongly.
  restores,

  /// A page or connector constructs another connector — how a screen is
  /// composed out of regions — or a file constructs a service dispatcher.
  ///
  /// The one edge that is about *existence* rather than behaviour, and the
  /// reason it is here: a connector nothing builds cannot dispatch anything, so
  /// without it the actions it alone dispatches read as reached and the
  /// connector itself reads as nothing at all.
  builds,

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

  /// `dispatch-target`, `pop-destination`, `route-connector`,
  /// `orphan-substate`, `selector-action`, `selector-body`,
  /// `misplaced-selector`, `unparsed-file`.
  final String kind;

  /// Why frx stopped, in a sentence a human or an agent can act on.
  final String why;

  /// The node whose reading hit the gap — `page:logIn`, `selector:logIn.email`.
  ///
  /// What makes a gap attributable, and therefore what lets [AppGraph.focusOn]
  /// keep only the ones belonging to the subgraph it returns. [at] cannot do
  /// it: it is a display string, and across the readers it has been a file
  /// path, a node id and a route class name.
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
    this.field,
  });

  final String node;
  final GraphDirection direction;

  /// The one field of a substate [node] the walk was narrowed to, when it was
  /// — see [AppGraph.focusOn].
  final String? field;

  /// Hops followed, or null when unbounded.
  final int? depth;

  /// Whether the bound stopped the walk while there was still more to reach —
  /// the one fact that turns a short answer into an honest one.
  final bool truncated;

  Map<String, Object?> toJson() => {
    'node': node,
    if (field != null) 'field': field,
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
      if (n.id == id) {
        return n;
      }
    }
    return null;
  }

  /// Artifacts nothing reaches, each with the reason — actions nothing
  /// dispatches, selectors nothing reads.
  ///
  /// Not an error by itself: either can be reached from somewhere frx does not
  /// read, and in a template a selector can be API offered to whoever builds on
  /// it. But in a repo where frx wrote the callers, it usually means dead code.
  /// Connectors and service dispatchers no file constructs.
  ///
  /// In-degree on [EdgeKind.builds], not reachability, and the difference is
  /// deliberate: "no file anywhere constructs this class" is a claim the source
  /// settles, while "not reachable from the app's root widget" needs frx to
  /// know which widget that is — and being wrong about *that* would report a
  /// live screen as dead, which is the failure this whole list exists not to
  /// have. A chain of two connectors that only build each other is therefore
  /// not reported. That is the honest bound, and it errs the safe way.
  ///
  /// A dispatcher by the same rule: it is constructed where the app wires its
  /// services, and one nothing constructs is dead with every action only it
  /// dispatches — which the orphan list said one action at a time.
  List<({GraphNode node, String why})> get unbuiltConnectors {
    final built = {
      for (final e in edges)
        if (e.kind == EdgeKind.builds) e.to,
    };
    return [
      for (final n in nodes)
        // Connectors and services only. A [NodeKind.consumer] is any file frx
        // read that turned out to dispatch, read a selector or compose a
        // screen, and "nothing constructs `RunEnv`" is not a claim about dead
        // code — it is a claim about a class that was never a widget.
        if ((n.kind == NodeKind.consumer && n.name.endsWith('Connector') ||
                n.kind == NodeKind.service) &&
            !built.contains(n.id))
          (node: n, why: 'no file constructs it'),
    ];
  }

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
      ...unbuiltConnectors,
      ...deadSelectors,
      ...deadFields,
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
      if (e.kind == .uses) {
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
        if (entry.value.any(live.contains)) {
          live.add(entry.key);
        }
      }

      if (live.length == before) {
        break;
      }
    }

    return [
      for (final n in nodes)
        if (n.kind == .selector && !live.contains(n.id))
          (
            node: n,
            why: usedBy.containsKey(n.id)
                ? 'read only by selectors nothing reads'
                : 'nothing reads it',
          ),
    ];
  }

  /// Fields of a substate nothing reads — written, often, and never looked
  /// at.
  ///
  /// The question a dead selector could not settle. `SelectSetup.agentErrorOn`
  /// on the dead list says the *getter* is unused; whether the field behind
  /// it is, depends on every reducer and connector that might read the state
  /// directly — which the `reads` edges now record, by field. So: a field is
  /// live when something reads it that is not itself a dead selector, or
  /// when anything live reads the whole slice — `state.session` handed on,
  /// or a getter returning it — since that is a read of every field, and
  /// guessing otherwise would report a live field as dead. The persistor's
  /// reads do not count: it saves the slice, it does not use it.
  ///
  /// Only for a substate whose node lists its `fields`, which is one with a
  /// state class of ours; a framework slice has nothing to list.
  List<({GraphNode node, String why})> get deadFields {
    final deadSelectorIds = {for (final d in deadSelectors) d.node.id};
    final kindOf = {for (final n in nodes) n.id: n.kind};
    bool live(String reader) => !deadSelectorIds.contains(reader);

    final out = <({GraphNode node, String why})>[];
    for (final n in nodes) {
      if (n.kind != NodeKind.substate) {
        continue;
      }
      final fields = n.fields['fields'];
      if (fields is! List<String> || fields.isEmpty) {
        continue;
      }

      final substate = n.name;
      final readersOf = <String, Set<String>>{};
      final wholeReaders = <String>{};
      final written = <String>{};
      var wholeWritten = false;
      for (final e in edges) {
        if (e.to != n.id) {
          continue;
        }
        final via = e.via;
        final whole = via == null || via == substate;
        final field = whole ? null : _fieldOf(via, substate);
        if (e.kind == .reads && kindOf[e.from] != NodeKind.persistor) {
          if (whole) {
            wholeReaders.add(e.from);
          } else if (field != null) {
            readersOf.putIfAbsent(field, () => {}).add(e.from);
          }
        } else if (e.kind == .writes) {
          if (whole) {
            wholeWritten = true;
          } else if (field != null) {
            written.add(field);
          }
        }
      }

      if (wholeReaders.any(live)) {
        continue;
      }
      for (final field in fields) {
        if ((readersOf[field] ?? const {}).any(live)) {
          continue;
        }
        out.add((
          node: GraphNode(
            id: 'field:$substate.$field',
            kind: NodeKind.field,
            name: '$substate.$field',
            substate: substate,
            file: n.file,
          ),
          why: wholeWritten || written.contains(field)
              ? 'written, nothing reads it'
              : 'nothing reads it',
        ));
      }
    }
    return out;
  }

  /// `session.token` → `token`; `session.user.name` → `user`; anything not
  /// under [substate] → null.
  static String? _fieldOf(String via, String substate) {
    final prefix = '$substate.';
    if (!via.startsWith(prefix)) {
      return null;
    }
    final rest = via.substring(prefix.length);
    final dot = rest.indexOf('.');
    return dot < 0 ? rest : rest.substring(0, dot);
  }

  /// The subgraph within [depth] hops of [id] — "show me everything around the
  /// login screen", or, with [GraphDirection.inbound], "what breaks if I touch
  /// this".
  ///
  /// [depth] null follows the edges until the set closes. Unbounded is the
  /// sensible default for an impact question and terminates for the same reason
  /// a bounded one does: the node set is finite and each pass either grows it
  /// or stops.
  ///
  /// [field] narrows a substate focus to one field of it — "who touches
  /// `console.seq`", not "who touches `console`". A slice with fifty fields is
  /// a hub: every selector on it reads it, every setter writes it, and an
  /// inbound walk from the slice is the whole app. The edges at the focus are
  /// kept when their `via` names the field, or names the whole slice — a flat
  /// `copyWith(console: …)` and the persistor's restore change every field —
  /// and the walk goes on from what is left. Edges elsewhere are untouched.
  AppGraph focusOn(
    String id, {
    int? depth = 1,
    GraphDirection direction = GraphDirection.both,
    String? field,
  }) {
    final edges = field == null
        ? this.edges
        : [
            for (final e in this.edges)
              if ((e.from != id && e.to != id) || _touchesField(e, id, field))
                e,
          ];

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
      // Scoped to the subgraph. Kept whole, a gap belonging to an unrelated
      // page was reported against whatever you focused, which misattributes it
      // — and the one thing this list exists to do is say where the answer is
      // incomplete.
      unresolved: [
        for (final u in unresolved)
          if (reached.contains(u.owner)) u,
      ],
      focus: GraphFocus(
        node: id,
        field: field,
        direction: direction,
        depth: depth,
        truncated: truncated,
      ),
    );
  }

  /// Whether an edge at `substate:<name>` concerns [field] of it.
  ///
  /// `via` on an edge into a substate is the place touched — `console.seq`,
  /// or `console` for the whole slice — and an edge with no `via` at all
  /// (the persistor's) touches the whole slice too.
  static bool _touchesField(GraphEdge e, String id, String field) {
    final substate = id.substring(id.indexOf(':') + 1);
    final via = e.via;
    return via == null ||
        via == substate ||
        via == '$substate.$field' ||
        via.startsWith('$substate.$field.');
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
