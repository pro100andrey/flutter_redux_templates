import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../ast/source_index.dart';
import '../../model/page_artifact.dart';
import '../../refusal.dart';
import '../../routing/routes_source.dart';
import '../../workspace/frx_workspace.dart';
import '../../workspace/workspace_uri.dart';
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
  final imported = _importedBy(routes.file, repo);

  // route → connector file
  final reported = <String>{};
  for (final entry in entries) {
    final type = entry.routeType;
    final page = PageArtifact.fromRouteType(type);
    if (page == null || !reported.add(type)) {
      continue;
    }

    // Where `add-page` puts it, or wherever the router imports it from: a
    // connector moved into `connectors/auth/` with its import fixed compiles,
    // and the flat path alone called it missing.
    final connector = page.connectorFile(routes.connectorsDir);
    final name = p.basename(connector.path);
    if (!connector.existsSync() &&
        !imported.any((f) => p.basename(f) == name)) {
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
  for (final f in sourceIndex.filesUnder(routes.connectorsDir)) {
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

/// The project files [router] imports that exist.
List<String> _importedBy(File router, FrxWorkspace repo) {
  final packages = repo.packageLibs();
  return [
    for (final (:uri, offset: _) in directivesIn(
      sourceIndex.sourceOf(router),
    ))
      if (workspaceTarget(uri, from: router.absolute.path, packages: packages)
          case final target? when File(target).existsSync())
        target,
  ];
}
