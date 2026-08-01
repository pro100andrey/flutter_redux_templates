import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../workspace/frx_workspace.dart';
import '../ast/source_index.dart';
import 'flow_model.dart';
import 'flow_reader.dart';

/// One screen in the navigation map: its route registration plus what the
/// connector behind it exposes.
class PageNode {
  const PageNode({
    required this.page,
    required this.routeType,
    required this.pageClass,
    this.path,
    this.parent,
    this.initial = false,
    this.public = false,
    this.connectorFile,
    this.useCases = 0,
  });

  /// The page's base name, e.g. `logIn`.
  final String page;

  /// The generated auto_route class, e.g. `LogInRoute`.
  final String routeType;

  /// The dumb page class, e.g. `LogInPage`.
  final String pageClass;

  /// The registered route path, e.g. `/login`.
  final String? path;

  /// The tab shell this page is nested under, if any.
  final String? parent;

  /// `AutoRoute(initial: true)` — where the app starts.
  final bool initial;

  /// Reachable while logged out (a member of the guard's `_authArea`).
  final bool public;

  /// Absolute path of the connector, or null when the route has none (doctor
  /// reports that separately; the map still draws the node).
  final String? connectorFile;

  /// How many dispatching callbacks the connector's view-model exposes.
  final int useCases;

  Map<String, Object?> toJson() => {
    'page': page,
    'route': routeType,
    'pageClass': pageClass,
    if (path != null) 'path': path,
    if (parent != null) 'parent': parent,
    'initial': initial,
    'public': public,
    if (connectorFile != null) 'connectorFile': connectorFile,
    'useCases': useCases,
  };
}

/// How a navigation hop was performed — the `GoAction` factory that ran.
enum NavKind {
  push,
  pop,
  other;

  static NavKind of(String method) => switch (method) {
    'push' => NavKind.push,
    'pop' => NavKind.pop,
    _ => NavKind.other,
  };
}

/// One navigation hop: page [from] reaches page [to] through [via].
class NavEdge {
  const NavEdge({
    required this.from,
    required this.method,
    required this.via,
    this.to,
    this.toRoute,
    this.condition,
    this.fromAction = false,
    this.inferred = false,
  });

  /// The page the hop starts on.
  final String from;

  /// The destination page, or null when it could not be determined (a `pop`
  /// with no single pusher, or a route with no matching connector).
  final String? to;

  /// The destination route type as written, e.g. `LogInRoute`.
  final String? toRoute;

  /// The `GoAction` factory: `push`, `pop`, `replace`, …
  final String method;

  /// What triggers the hop — the view-model callback (`onPressedRegister`) or,
  /// when the navigation happens inside a reducer, the action's class name.
  final String via;

  /// The `if` guarding the hop, when there is one.
  final String? condition;

  /// True when the dispatch sits in a `ReduxAction.reduce()` rather than in the
  /// connector's view-model.
  final bool fromAction;

  /// True when [to] was deduced rather than read: a `pop` resolved to the only
  /// page that pushes [from].
  final bool inferred;

  NavKind get kind => NavKind.of(method);

  /// Identity for de-duplication — an action reached from two callbacks would
  /// otherwise contribute the same hop twice.
  String get _key => '$from|$to|$toRoute|$method|$via|$condition';

  NavEdge _to(String page) => NavEdge(
    from: from,
    to: page,
    toRoute: toRoute,
    method: method,
    via: via,
    condition: condition,
    fromAction: fromAction,
    inferred: true,
  );

  Map<String, Object?> toJson() => {
    'from': from,
    if (to != null) 'to': to,
    if (toRoute != null) 'toRoute': toRoute,
    'method': method,
    'via': via,
    if (condition != null) 'condition': condition,
    'fromAction': fromAction,
    'inferred': inferred,
  };
}

/// The whole app's navigation graph: every registered screen and every hop
/// between them, read from the AST.
class RouteMap {
  const RouteMap({
    required this.pages,
    required this.edges,
    this.flows = const {},
  });

  final List<PageNode> pages;
  final List<NavEdge> edges;

  /// The per-page use-case flow, by page name — carried so a caller that needs
  /// both the map and the sequence diagrams (the docs export) parses once.
  /// Not serialized: `--json` consumers ask for a page's flow directly.
  final Map<String, PageFlow> flows;

  bool get isEmpty => pages.isEmpty;

  /// The page names nested under each shell, keyed by the *shell's page name*.
  ///
  /// [PageNode.parent] holds a route *type* (`AccountRoute`) while pages are
  /// keyed by page *name* (`account`), so answering "what is under this shell"
  /// needs a join. It lives here because the reader has both halves in hand and
  /// the renderer does not: `mermaid.dart` used to walk every page for every
  /// page to resolve one parent, and rebuild the whole child index on each
  /// render.
  ///
  /// A getter rather than a cached field because [RouteMap] is const — the
  /// renderer hoists it into a local, which is O(n) once instead of O(n²).
  Map<String, List<String>> get children {
    final byRouteType = {for (final n in pages) n.routeType: n.page};
    final out = <String, List<String>>{};
    for (final n in pages) {
      final shell = n.parent == null ? null : byRouteType[n.parent];
      if (shell != null) (out[shell] ??= []).add(n.page);
    }
    return out;
  }

  /// The shell page [page] is nested under, or null when it is top-level.
  ///
  /// Null also when the parent route type matches no page — a shell whose route
  /// frx could not pair with a page. The caller renders it top-level, which is
  /// what the O(n²) lookup in the renderer did too.
  String? shellOf(String page) {
    for (final entry in children.entries) {
      if (entry.value.contains(page)) return entry.key;
    }
    return null;
  }

  /// Pages nothing pushes: entered by path, deep link or a guard redirect
  /// rather than from another screen. Not an error — in this template the auth
  /// guard is exactly what puts you on `logIn` or `home`.
  List<PageNode> get entryPoints {
    final pushed = {
      for (final e in edges)
        if (e.kind == NavKind.push && e.to != null) e.to!,
    };
    return [
      for (final n in pages)
        if (!pushed.contains(n.page) && n.parent == null) n,
    ];
  }

  Map<String, Object?> toJson() => {
    'pages': [for (final n in pages) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    'entryPoints': [for (final n in entryPoints) n.page],
  };
}

/// Builds the app-wide [RouteMap] by reading every registered route's connector
/// with [FlowReader] and keeping the hops it dispatches.
///
/// Parse-only, like the rest of frx — see `flow_reader.dart` for why.
class RouteMapReader {
  RouteMapReader(this.workspace, {RoutesSource? routes})
    : routes = routes ?? RoutesSource.of(workspace);

  final FrxWorkspace workspace;
  final RoutesSource routes;

  RouteMap read() => inSourceIndex(_read);

  RouteMap _read() {
    final authArea = routes.readAuthArea();
    final reader = FlowReader(workspace);

    final pages = <PageNode>[];
    final flows = <String, PageFlow>{};
    final edges = <NavEdge>[];
    final seen = <String>{};

    for (final entry in routes.readRoutes()) {
      final artifact = PageArtifact.fromRouteType(entry.routeType);
      if (artifact == null) continue;
      final page = artifact.name.camel;
      final connector = artifact.connectorFile(routes.connectorsDir);
      final exists = connector.existsSync();

      final PageFlow? flow;
      if (exists) {
        flow = reader.read(
          connectorFile: connector,
          page: page,
          connectorClass: artifact.connectorClass,
          pageClass: artifact.pageClass,
        );
        flows[page] = flow;
      } else {
        flow = null;
      }

      pages.add(
        PageNode(
          page: page,
          routeType: entry.routeType,
          pageClass: artifact.pageClass,
          path: entry.fullPath,
          parent: entry.parent,
          initial: entry.initial,
          public: authArea.contains(entry.routeType),
          connectorFile: exists ? connector.path : null,
          useCases: flow?.useCases.length ?? 0,
        ),
      );

      if (flow == null) continue;
      for (final edge in _edgesOf(page, flow)) {
        if (seen.add(edge._key)) edges.add(edge);
      }
    }

    return RouteMap(pages: pages, edges: _resolvePops(edges), flows: flows);
  }

  /// Every navigation hop [flow] performs — from the view-model's callbacks and
  /// from the reducers of the actions those callbacks dispatch.
  Iterable<NavEdge> _edgesOf(String page, PageFlow flow) sync* {
    for (final useCase in flow.useCases) {
      for (final step in useCase.steps) {
        if (step.isNavigation) {
          yield _edge(page, step, via: useCase.label);
          continue;
        }
        final action = flow.actions[step.target];
        for (final nested in action?.dispatches ?? const <DispatchStep>[]) {
          if (!nested.isNavigation) continue;
          yield _edge(page, nested, via: action!.className, fromAction: true);
        }
      }
    }
  }

  NavEdge _edge(
    String from,
    DispatchStep step, {
    required String via,
    bool fromAction = false,
  }) {
    const prefix = 'GoAction.';
    final method = step.target.startsWith(prefix)
        ? step.target.substring(prefix.length)
        : step.target;
    final route = step.route;
    return NavEdge(
      from: from,
      to: route == null ? null : PageArtifact.fromRouteType(route)?.name.camel,
      toRoute: route,
      method: method,
      via: via,
      condition: step.condition,
      fromAction: fromAction,
    );
  }

  /// Points each `pop` at the page that pushed it.
  ///
  /// `GoAction.pop()` returns to whatever is under it on the stack, which the
  /// source cannot state — but when exactly one page pushes this one, that is
  /// the answer, and drawing it turns the map into the loop the user actually
  /// walks. Ambiguous pops (0 or 2+ pushers) keep `to: null` and are drawn as a
  /// hop out of the graph, since guessing between callers would be a lie.
  List<NavEdge> _resolvePops(List<NavEdge> edges) {
    final pushers = <String, Set<String>>{};
    for (final e in edges) {
      if (e.kind == NavKind.push && e.to != null) {
        pushers.putIfAbsent(e.to!, () => {}).add(e.from);
      }
    }
    return [
      for (final e in edges)
        if (e.kind != NavKind.pop || e.to != null)
          e
        else if (pushers[e.from]?.length == 1)
          e._to(pushers[e.from]!.single)
        else
          e,
    ];
  }
}
