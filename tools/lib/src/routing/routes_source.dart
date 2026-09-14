import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/construction.dart';
import '../ast/directives.dart';
import '../ast/file_source.dart';
import '../ast/function_bodies.dart';
import '../redux/app_state_source.dart' show AppStateSource;
import '../redux/ast_edit.dart';
import '../refusal.dart';
import '../workspace/frx_workspace.dart';
import 'route_entry.dart';
import 'route_results.dart';
import 'router_ast.dart';

export 'route_entry.dart';
export 'route_results.dart';

/// Reads and edits `app/lib/navigation/app_router.dart` via the analyzer AST.
///
/// The auto_route analogue of [AppStateSource]: instead of hand-editing the
/// `routes` list (and the connector import, and the auth-area set) after
/// generating a page, `frx add-page` inserts them at precise AST offsets. Only
/// parses — no package config needed — and leans on `dart format` to normalize
/// whitespace afterwards.
class RoutesSource extends FileSource {
  RoutesSource(super.file);

  /// The `app_router.dart` of an already-resolved workspace.
  ///
  /// [FrxWorkspace] keys on this very file, so the two cannot disagree about
  /// where the router is — which makes re-walking the tree from a command that
  /// already holds a workspace a second answer to a question already answered.
  factory RoutesSource.of(FrxWorkspace repo) =>
      RoutesSource(File(p.join(repo.root.path, _relativePath)));

  /// Finds `app_router.dart` by walking up from [startDir] (or the current
  /// directory) until `app/lib/navigation/app_router.dart` is found.
  factory RoutesSource.locate({String? startDir}) =>
      RoutesSource(locateFile(_relativePath, startDir: startDir));

  /// Path of `app_router.dart` relative to the repo root.
  static const _relativePath = 'app/lib/navigation/app_router.dart';

  /// The monorepo root — the directory that holds `app/`, `ui/`, … Derived by
  /// walking up from the located file (navigation → lib → app → root).
  Directory get repoRoot => file.parent.parent.parent.parent;

  /// The `app` package root (where build_runner regenerates the routes).
  Directory get appPackageRoot => file.parent.parent.parent;

  /// The `app/lib/connectors` directory that holds the page connectors.
  Directory get connectorsDir =>
      Directory(p.join(file.parent.parent.path, 'connectors'));

  /// The `ui/lib/pages` directory that holds the dumb pages.
  Directory get pagesDir =>
      Directory(p.join(repoRoot.path, 'ui', 'lib', 'pages'));

  /// The routes currently registered in `AppRouter.routes`, in source order,
  /// nested `children:` included — see [routeEntriesOf].
  List<RouteEntry> readRoutes() => routeEntriesOf(_routesList(unit));

  /// The route types the guard lets through while logged out — the
  /// `<Route>.name` members of `_AuthGuard._authArea`, with the `.name`
  /// dropped. Empty when there is no guard (or its set can't be read).
  Set<String> readAuthArea() {
    final set = authAreaSetOf(unit);
    if (set == null) {
      return const {};
    }
    return {
      for (final e in set.elements)
        if (e.toSource() case final member when member.endsWith('.name'))
          member.substring(0, member.length - '.name'.length),
    };
  }

  /// Wires a page into `AppRouter`: adds the connector import (kept sorted
  /// among the relative imports), an
  /// `AutoRoute(page: <Route>.page, path: '<path>')` entry in `routes`, and —
  /// when [public] — the route name in the guard's `_authArea` set. Idempotent
  /// when the route is already registered.
  RouteWireResult wirePage({
    required String routeType,
    required String connectorImport,
    required String path,
    required bool public,
    bool importMaterial = false,
  }) {
    final (source: content, :unit) = snapshot;
    final list = _routesList(unit);

    if (registeredRoute(list, routeType) != null) {
      return RouteWireResult.wired(content);
    }

    final edits = <Edit>[];
    final changes = <String>[];
    final warnings = <String>[];

    // 1) connector import, sorted among the relative imports.
    final imports = importsOf(unit);
    if (importNamed(imports, connectorImport) == null) {
      edits.add(importInsertion(imports, connectorImport));
      changes.add("import '$connectorImport';");
    }

    // A route with path params generates an args class referencing `Key`; the
    // generated `.gr.dart` is a `part`, so the library must import Flutter.
    if (importMaterial && importNamed(imports, _material) == null) {
      edits.add(importInsertion(imports, _material));
      changes.add("import '$_material';");
    }

    // 2) AutoRoute entry.
    final entry = "AutoRoute(page: $routeType.page, path: '$path')";
    edits.add(
      insertIntoList(
        elements: list.elements,
        closer: list.rightBracket,
        element: entry,
      ),
    );
    changes.add('routes: $entry');

    // 3) auth-area membership, when the page is reachable while logged out.
    if (public) {
      final authArea = authAreaSetOf(unit);
      if (authArea == null) {
        warnings.add(
          "--public: could not find the guard's _authArea set — the route was "
          'NOT added to it. Add "$routeType.name" manually if the page should '
          'be reachable while logged out.',
        );
      } else if (authAreaMember(authArea, routeType) == null) {
        edits.add(
          insertIntoList(
            elements: authArea.elements,
            closer: authArea.rightBracket,
            element: '$routeType.name',
          ),
        );
        changes.add('_authArea: $routeType.name');
      }
    }

    return RouteWireResult(
      source: applyEdits(content, edits),
      changes: changes,
      alreadyWired: false,
      warnings: warnings,
    );
  }

  /// Wires a tab flow into `AppRouter`: adds the shell + every tab connector
  /// import, and a nested
  /// `AutoRoute(page: <Shell>.page, path: '<path>', children: [...])`, whose
  /// children are `AutoRoute(page: <Tab>.page, path: '<tab>')`
  /// entry. Idempotent when the shell route is already registered.
  ///
  /// The imports go in through [addImports] — one re-parse each, so several
  /// relative imports each land in their own sorted position instead of
  /// colliding — and after the entry, whose offset an import above it would
  /// move.
  RouteWireResult wireTabsRoute({
    required String shellRoute,
    required List<String> connectorImports,
    required String path,
    required List<({String route, String path})> tabs,
  }) {
    final (source: content, :unit) = snapshot;
    final list = _routesList(unit);

    if (registeredRoute(list, shellRoute) != null) {
      return RouteWireResult.wired(content);
    }

    final children = tabs
        .map((t) => "AutoRoute(page: ${t.route}.page, path: '${t.path}')")
        .join(', ');
    final entry =
        "AutoRoute(page: $shellRoute.page, path: '$path', "
        'children: [$children])';
    final routed = applyEdits(content, [
      insertIntoList(
        elements: list.elements,
        closer: list.rightBracket,
        element: entry,
      ),
    ]);
    final added = addImports(routed, connectorImports);

    return RouteWireResult(
      source: added.source,
      changes: [
        ...added.changes,
        'routes: $shellRoute with ${tabs.length} tab(s)',
      ],
      alreadyWired: false,
    );
  }

  /// Removes a page from `AppRouter`: drops its
  /// `AutoRoute(page: <routeType> .page, …)` entry, the connector import
  /// [connectorImport], and `<routeType>.name` from the guard's `_authArea` set
  /// when present. The inverse of [wirePage]; `found: false` when no such route
  /// is registered. A removed entry carrying nested `children` (a tab shell) is
  /// flagged so the caller can note the child pages were left in place.
  RouteUnwireResult unwirePage({
    required String routeType,
    required String connectorImport,
  }) {
    final (source: content, :unit) = snapshot;
    final list = _routesList(unit);

    final registered = registeredRoute(list, routeType);
    if (registered == null) {
      return RouteUnwireResult.absent(content);
    }
    final entry = registered.element;

    final edits = <Edit>[removeListItem(content, entry)];
    final changes = <String>['route $routeType'];
    final warnings = <String>[];

    if (namedArgumentIn(registered.args, 'children') != null) {
      warnings.add(
        '$routeType has nested children (a tab shell) — its child tab pages '
        'and '
        'their connectors were left in place; remove them separately.',
      );
    }

    // The connector import, matched exactly against the path add-page used.
    final imports = importsOf(unit);
    final imp = importNamed(imports, connectorImport);
    if (imp != null) {
      edits.add(removeDirective(content, imp));
      changes.add("import '$connectorImport'");
    }

    // Auth-area membership, if the page was reachable while logged out.
    final authArea = authAreaSetOf(unit);
    if (authArea != null) {
      final member = authAreaMember(authArea, routeType);
      if (member != null) {
        edits.add(removeListItem(content, member));
        changes.add('_authArea: $routeType.name');
      }
    }

    // Prune the Flutter import once the last param route is gone. `add-page`
    // adds it only for a route with path params, so the generated `.gr.dart`
    // args class (which references `Key`) compiles; `app_router.dart` itself
    // uses no material symbols. Left dangling it would be an unused-import
    // lint, so drop it when no route path *other than the one leaving* carries
    // a `:` segment — judged on the same tree as the edits above, with the
    // removed entry (and, for a shell, its children) left out.
    final materialImport = importNamed(imports, _material);
    if (materialImport != null &&
        !identical(materialImport, imp) &&
        !anyParamPath(list.elements.where((e) => !identical(e, entry)))) {
      edits.add(removeDirective(content, materialImport));
      changes.add("import '$_material'");
    }

    return RouteUnwireResult(
      source: applyEdits(content, edits),
      changes: changes,
      found: true,
      warnings: warnings,
    );
  }

  static const _material = 'package:flutter/material.dart';

  /// The `[...]` literal returned by `AppRouter`'s `routes` getter.
  ListLiteral _routesList(CompilationUnit unit) {
    final router = classIn(unit, 'AppRouter');
    final getter = router.body.members
        .whereType<MethodDeclaration>()
        .where((m) => m.isGetter && m.name.lexeme == 'routes')
        .firstOrNull;
    if (getter == null) {
      throw FrxRefusal('AppRouter.routes getter not found in "${file.path}".');
    }
    final expr = resultOf(getter.body);
    if (expr is! ListLiteral) {
      throw const FrxRefusal(
        'AppRouter.routes does not return a list literal — cannot wire '
        'automatically.',
      );
    }
    return expr;
  }
}
