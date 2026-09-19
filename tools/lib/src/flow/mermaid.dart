import 'flow_model.dart';
import 'route_map.dart';

/// Renders a [PageFlow] as a mermaid `sequenceDiagram`.
///
/// The arrows follow this architecture's actual path — dumb widget → connector
/// (the view-model) → ReduxAction → AppState — so the diagram doubles as an
/// explanation of how a use case travels through the layers.
///
/// [only] restricts the drawing to those use cases, with only the lanes they
/// touch — see [renderSequences] for why a page is sometimes drawn in pieces.
String renderSequence(PageFlow flow, {Iterable<UseCase>? only}) {
  final b = StringBuffer();
  final useCases = only?.toList() ?? flow.useCases;
  final ids = _ParticipantIds(flow, useCases);

  b
    ..writeln('sequenceDiagram')
    ..writeln('    autonumber')
    ..writeln('    actor User')
    ..writeln('    participant UI as ${_esc(flow.pageClass)}');
  // One lane per connector that actually holds a view-model. A page connected
  // in one place has exactly the one it always had; a page composed of regions
  // gets a lane each, which is the difference between "this screen dispatches
  // nothing" and "its frame dispatches nothing and its six regions do".
  for (final entry in ids.connectors.entries) {
    b.writeln('    participant ${entry.value} as ${_esc(entry.key)}');
  }

  for (final entry in ids.actions.entries) {
    b.writeln('    participant ${entry.value} as ${_esc(entry.key)}');
  }

  if (ids.usesState) {
    b.writeln('    participant ST as AppState');
  }

  if (ids.usesRouter) {
    b.writeln('    participant NAV as Router');
  }

  for (final useCase in useCases) {
    final from = ids.laneOf(useCase);
    b
      ..writeln()
      ..writeln('    User->>UI: ${_esc(useCase.qualifiedLabel)}')
      ..writeln('    UI->>$from: ${_esc(useCase.name)}()');
    _writeSteps(b, useCase.steps, flow, ids, from: from, indent: '    ');
  }

  // The gap, drawn. A connector whose dispatches no use case accounts for has
  // no lane and no arrows, so without this the diagram is complete-looking and
  // short — the one failure a picture cannot survive, because a reader has
  // nothing to compare it against. `UI` is the note's anchor because it is the
  // one participant every diagram has.
  //
  // "Not drawn" and not "not traced": the note states a fact about this
  // picture, which is all it can know. Some of what it counts is a callback the
  // reader could not follow, and some is a dispatch that was never a callback —
  // `onInit: (store) => store.dispatch(…)` fires on open and belongs to no
  // interaction. Both are missing from the diagram, which is what the reader
  // needs told; neither is evidence that tracing failed.
  if (only == null && flow.untraced.isNotEmpty) {
    b.writeln();
    for (final gap in flow.untraced) {
      b.writeln(
        '    Note over UI: not drawn — ${_esc(gap.connectorClass)}: '
        '${gap.calls}',
      );
    }
  }

  return b.toString().trimRight();
}

/// How many lanes a sequence diagram stays readable at.
///
/// Mermaid fits the drawing to the page's width, so lanes past a dozen are
/// paid for in font size: a composed screen with fifteen regions and
/// twenty-seven actions came out at forty-five lanes, and every label in it
/// at three pixels. Twelve is where the template's own busiest page — nine
/// lanes — still reads as one picture, with room over it.
const readableLanes = 12;

/// How many lanes [renderSequence] would draw for [flow].
int laneCount(PageFlow flow) => _ParticipantIds(flow, flow.useCases).count;

/// One diagram of every use case, or one per use case — each titled.
///
/// A page draws as one sequence while its lanes fit ([readableLanes]); past
/// that, each interaction is its own drawing with only the lanes it touches,
/// which is what a reader was doing by eye on the wide one — following one
/// arrow chain across forty lanes of nothing. The untraced dispatches belong
/// to the page rather than to any interaction, so a split leaves them to the
/// document to list.
List<({String title, String diagram})> renderSequences(PageFlow flow) {
  if (laneCount(flow) <= readableLanes) {
    return [(title: '', diagram: renderSequence(flow))];
  }
  return [
    for (final useCase in flow.useCases)
      (
        title: useCase.qualifiedLabel,
        diagram: renderSequence(flow, only: [useCase]),
      ),
  ];
}

void _writeSteps(
  StringBuffer b,
  List<DispatchStep> steps,
  PageFlow flow,
  _ParticipantIds ids, {
  required String from,
  required String indent,
}) {
  String? openAlt;

  for (final step in steps) {
    // Guarded dispatches become an `alt` block; consecutive steps under the
    // same condition share one block.
    if (step.condition != openAlt) {
      if (openAlt != null) {
        b.writeln('${indent}end');
      }

      openAlt = step.condition;
      if (openAlt != null) {
        b.writeln('${indent}alt ${_esc(openAlt)}');
      }
    }
    final pad = openAlt == null ? indent : '$indent    ';

    if (step.isNavigation) {
      // The route plus what was handed to it: on `/product/:id` the arguments
      // are the half that says *which* product.
      final args = step.routeArgs == null ? '' : '(${_esc(step.routeArgs!)})';
      final where = step.route == null ? '' : ' ${_esc(step.route!)}$args';
      b.writeln('$pad$from->>NAV: ${_esc(step.target)}$where');
      continue;
    }

    final id = ids.actions[step.target];
    if (id == null) {
      b.writeln(
        '$pad$from->>$from: ${_esc(step.kind.name)}(${_esc(step.target)})',
      );
      continue;
    }

    final action = flow.actions[step.target];
    // A round trip gets activation bars so the wait is visible.
    final open = step.kind.isRoundTrip ? '+' : '';
    b.writeln('$pad$from->>$open$id: ${_esc(step.kind.name)}');

    final notes = _notesFor(action);
    if (notes != null) {
      b.writeln('${pad}Note over $id: ${_esc(notes)}');
    }

    if (action?.writesLabel case final w?) {
      b.writeln('$pad$id->>ST: copyWith(${_esc(w)})');
    }

    if (action?.throwsUserException ?? false) {
      // Propagates to the caller, where async_redux surfaces it as a dialog.
      b.writeln('$pad$id--x$from: UserException');
    }
    // Cascades: actions this action dispatches itself.
    for (final nested in action?.dispatches ?? const <DispatchStep>[]) {
      final nestedId = ids.actions[nested.target];
      b.writeln(
        '$pad$id->>${nestedId ?? 'ST'}: ${_esc(nested.kind.name)}'
        '${nestedId == null ? '(${_esc(nested.target)})' : ''}',
      );
    }

    if (step.kind.isRoundTrip) {
      b.writeln('$pad$id-->>-$from: ActionStatus');
    }
  }

  if (openAlt != null) {
    b.writeln('${indent}end');
  }
}

/// The one-line note under an action: its mixins and whether it's async.
String? _notesFor(ActionInfo? action) {
  if (action == null) {
    return null;
  }

  final parts = <String>[...action.mixins, if (action.isAsync) 'async'];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Stable, mermaid-safe participant ids, over the use cases being drawn.
class _ParticipantIds {
  _ParticipantIds(PageFlow flow, List<UseCase> useCases) {
    // The route connector keeps the id `VM` it has always had, so a page with
    // no regions renders byte-for-byte as before. Only a composed page gains
    // lanes, and only for the regions that dispatch something — a region that
    // draws state and calls nothing has no interaction to put on a lane.
    _routeConnector = flow.connectorClass;
    connectors[flow.connectorClass] = 'VM';
    var lane = 0;
    for (final useCase in useCases) {
      final owner = useCase.owner;
      if (owner != null) {
        connectors.putIfAbsent(owner, () => 'R${++lane}');
      }
    }

    if (connectors.length > 1 && !useCases.any((u) => u.owner == null)) {
      // The frame holds no view-model of its own — the composition case. Its
      // lane would be an empty column captioned with the one class in the
      // drawing that does nothing.
      connectors.remove(flow.connectorClass);
    }

    var n = 0;
    for (final useCase in useCases) {
      for (final step in useCase.steps) {
        if (step.isNavigation) {
          usesRouter = true;
          continue;
        }

        final action = flow.actions[step.target];
        if (action == null) {
          continue;
        }

        actions.putIfAbsent(step.target, () => 'A${++n}');
        // `writes.isNotEmpty`, not `writesLabel != null`: the label is a
        // rendering of the writes, and joining every one of them into a string
        // to compare it against null is the shape this was all changed to stop.
        if (action.writes.isNotEmpty || action.dispatches.isNotEmpty) {
          usesState = true;
        }
      }
    }
  }

  /// The route connector's class — the lane a use case with no owner sits in.
  late final String _routeConnector;

  /// Connector class → lane id, in the order the regions are reached.
  final Map<String, String> connectors = {};
  final Map<String, String> actions = {};
  var usesState = false;
  var usesRouter = false;

  /// The lane [useCase] is dispatched from.
  String laneOf(UseCase useCase) =>
      connectors[useCase.owner ?? _routeConnector] ?? connectors.values.first;

  /// Every lane the diagram draws: the user, the page, and these.
  int get count =>
      2 +
      connectors.length +
      actions.length +
      (usesState ? 1 : 0) +
      (usesRouter ? 1 : 0);
}

/// Mermaid message text is newline- and semicolon-delimited; keep it on one
/// line and drop the characters that would end the statement early.
String _esc(String s) =>
    s.replaceAll('\n', ' ').replaceAll(';', ',').replaceAll('#', '').trim();

// --- navigation map ---------------------------------------------------------

/// Renders a [RouteMap] as a mermaid `flowchart` — the app's screens and the
/// hops between them.
///
/// Node shape and style carry the routing facts that are otherwise invisible:
/// the `initial:` route is a stadium, screens nothing pushes (reached by path,
/// deep link or the auth guard) are dashed, and the guard's `_authArea` becomes
/// a subgraph, so "what can I see logged out?" is one glance.
String renderRouteMap(RouteMap map) {
  final b = StringBuffer();
  final entryPoints = {for (final n in map.entryPoints) n.page};
  final popsOut = map.edges.any((e) => e.kind == NavKind.pop && e.to == null);

  b.writeln('flowchart LR');

  // A tab shell and its children belong together: their nesting is the one
  // thing a flat list of nodes cannot state — `profile` sits inside `account`,
  // and without the box it reads as another top-level screen you can push to.
  //
  // Grouped before the public/private split, and a shell's own access decides
  // where the group goes. Splitting first put a public shell in one region and
  // left its children — filtered out of the flat list for having a parent — in
  // neither, so they vanished from the diagram entirely.
  // The join lives on the model: `parent` names a route type, pages are keyed
  // by name, and the reader had both halves. Read once — the getter is O(n),
  // and asking it per page was the O(n^2) this used to do.
  final childIndex = map.children;
  final nested = {for (final kids in childIndex.values) ...kids};
  final byPage = {for (final n in map.pages) n.page: n};
  final childrenOf = {
    for (final entry in childIndex.entries)
      entry.key: [
        for (final page in entry.value) ?byPage[page],
      ],
  };

  void writeGroup(PageNode n, String indent) {
    final kids = childrenOf[n.page];
    if (kids == null) {
      b.writeln('$indent${_flowNode(n)}');
      return;
    }

    b
      ..writeln(
        '${indent}subgraph frxTabs_${_flowId(n.page)}'
        '["${_escFlow(n.pageClass)} · tabs"]',
      )
      ..writeln('$indent    ${_flowNode(n)}');
    for (final kid in kids) {
      b.writeln('$indent    ${_flowNode(kid)}');
    }

    b.writeln('${indent}end');
  }

  // Public screens grouped, so the auth boundary is a visible region rather
  // than a property you have to look up per node. Only the top-level screens
  // are placed; a nested one is drawn inside its shell's group.
  final public = <PageNode>[];
  final rest = <PageNode>[];
  for (final n in map.pages) {
    if (!nested.contains(n.page)) {
      (n.public ? public : rest).add(n);
    }
  }

  if (public.isNotEmpty && rest.isNotEmpty) {
    b.writeln('    subgraph frxPublic["reachable logged out"]');
    for (final n in public) {
      writeGroup(n, '        ');
    }
    b.writeln('    end');
  } else {
    rest.insertAll(0, public);
  }

  for (final n in rest) {
    writeGroup(n, '    ');
  }

  if (popsOut) {
    b.writeln('    frxBack(["◀ back"])');
  }

  if (map.edges.isNotEmpty) {
    b.writeln();
  }

  for (final e in map.edges) {
    final target = e.to != null
        ? _flowId(e.to!)
        : e.kind == NavKind.pop
        ? 'frxBack'
        : null;
    // A push to a route with no page of its own has nothing to point at.
    if (target == null) {
      continue;
    }

    b.writeln(
      '    ${_flowId(e.from)} ${_arrow(e.kind)}|"${_escFlow(_edgeLabel(e))}"| '
      '$target',
    );
  }

  final dashed = [
    for (final n in map.pages)
      if (entryPoints.contains(n.page) && !n.initial) _flowId(n.page),
  ];
  if (dashed.isNotEmpty) {
    b
      ..writeln()
      ..writeln('    classDef frxEntry stroke-dasharray: 5 3')
      ..writeln('    class ${dashed.join(',')} frxEntry');
  }

  return b.toString().trimRight();
}

/// `push` is a solid hop, `pop` a dashed return, anything else (`replace`,
/// `pushAndRemoveUntil`) a thick arrow — it drops what came before.
String _arrow(NavKind kind) => switch (kind) {
  .push => '-->',
  .pop => '-.->',
  .other => '==>',
};

String _flowNode(PageNode n) {
  final label = _escFlow(
    n.path == null ? n.pageClass : '${n.pageClass} · ${n.path}',
  );
  // The `initial:` route gets the stadium shape reserved for a start node.
  return n.initial
      ? '${_flowId(n.page)}(["$label"])'
      : '${_flowId(n.page)}["$label"]';
}

/// The trigger, plus the guard it sits behind and a marker when the hop is
/// dispatched from a reducer rather than the view-model.
String _edgeLabel(NavEdge e) {
  final parts = StringBuffer(e.fromAction ? '⚡ ${e.via}' : e.via);
  if (e.method != 'push' && e.method != 'pop') {
    parts.write(' (${e.method})');
  }

  if (e.condition != null) {
    parts.write(' [${e.condition}]');
  }

  return parts.toString();
}

/// Words mermaid reads as syntax cannot be node ids; a page legitimately named
/// `end` would otherwise close the enclosing subgraph.
const _flowKeywords = {
  'end',
  'graph',
  'flowchart',
  'subgraph',
  'click',
  'style',
  'class',
  'classDef',
  'linkStyle',
  'direction',
};

String _flowId(String page) => _flowKeywords.contains(page) ? '${page}_' : page;

/// Node and edge labels are emitted quoted, so the only characters left to
/// neutralize are the quote itself and the `|` that delimits an edge label — a
/// condition like `a || b` would otherwise close the label mid-word.
String _escFlow(String s) => _esc(
  s.replaceAll('||', ' or ').replaceAll('|', '/').replaceAll('"', "'"),
).replaceAll(_whitespace, ' ');

final _whitespace = RegExp(r'\s+');
