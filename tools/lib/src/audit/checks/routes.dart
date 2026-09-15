import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../ast/source_index.dart';
import '../../model/page_artifact.dart';
import '../../refusal.dart';
import '../../routing/routes_source.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Every route needs its connector; every page connector should be routed.
void checkRoutesAndConnectors(FrxWorkspace repo, List<Finding> into) {
  final RoutesSource routes;
  try {
    routes = RoutesSource.of(repo);
  } on FrxRefusal {
    into.add(const Finding.warn('AppRouter not found — skipped route checks.'));
    return;
  }

  final entries = routes.readRoutes();
  final routedTypes = entries.map((r) => r.routeType).toSet();

  // route → connector file
  final reported = <String>{};
  for (final entry in entries) {
    final type = entry.routeType;
    final page = PageArtifact.fromRouteType(type);
    if (page == null || !reported.add(type)) {
      continue;
    }
    final connector = page.connectorFile(routes.connectorsDir);
    if (!connector.existsSync()) {
      final at = entry.offset == null
          ? null
          : positionIn(routes.unit, entry.offset!);
      into.add(
        Finding.error(
          'Route $type has no ${p.relative(connector.path)}.',
          // The connector is missing; anchor on the route registration.
          file: routes.file.path,
          line: at?.line,
          column: at?.column,
        ),
      );
    }
  }

  // page connector → route (only @RoutePage() connectors are meant to be
  // routed; wrappers like TopLevelPageConnector are not).
  for (final f in sourceIndex.filesUnder(
    routes.connectorsDir,
    recursive: false,
  )) {
    const suffix = '_page_connector.dart';
    final fname = p.basename(f.path);
    if (!fname.endsWith(suffix)) {
      continue;
    }
    // Off the parse tree, not out of the text — and through the one module that
    // decides, so this check and the placement rules cannot come to differ.
    final unit = sourceIndex.unitIf(
      f,
      (s) => s.contains('@${PageArtifact.routePageAnnotation}'),
    );
    if (unit == null || !PageArtifact.carriesRoutePage(unit)) {
      continue;
    }
    final base = fname.substring(0, fname.length - suffix.length);
    final type = PageArtifact.parse(base).routeType;
    if (!routedTypes.contains(type)) {
      // The annotated class, so the squiggle lands on the connector and not on
      // its imports.
      final decl = unit.declarations
          .whereType<ClassDeclaration>()
          .where(PageArtifact.isRoutePage)
          .firstOrNull;
      final at = decl == null
          ? null
          : positionIn(unit, decl.namePart.typeName.offset);
      into.add(
        Finding.warn(
          'connectors/$fname — $type is not registered in AppRouter.',
          file: f.path,
          line: at?.line,
          column: at?.column,
        ),
      );
    }
  }
}
