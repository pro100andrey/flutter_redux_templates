import '../ast/source_index.dart';
import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../workspace/frx_workspace.dart';
import 'flow_model.dart';
import 'flow_reader.dart';
import 'route_map.dart';

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
      if (artifact == null) {
        continue;
      }
      final page = artifact.name.camel;
      final connector = routes.connectorFor(artifact, workspace);

      final PageFlow? flow;
      if (connector != null) {
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
          connectorFile: connector?.path,
          useCases: flow?.useCases.length ?? 0,
        ),
      );

      if (flow == null) {
        continue;
      }

      for (final edge in _edgesOf(page, flow)) {
        if (seen.add(edge.key)) {
          edges.add(edge);
        }
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
          if (!nested.isNavigation) {
            continue;
          }
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
          e.inferredTo(pushers[e.from]!.single)
        else
          e,
    ];
  }
}
