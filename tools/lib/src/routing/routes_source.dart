import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../ast/construction.dart';
import '../ast/source_index.dart';
import '../redux/ast_edit.dart';
import '../workspace/frx_workspace.dart';

/// One route registered in `AppRouter.routes`.
class RouteEntry {
  const RouteEntry({
    required this.routeType,
    required this.path,
    String? fullPath,
    this.initial = false,
    this.parent,
  }) : _fullPath = fullPath;

  /// The generated route class referenced as `<Type>.page`, e.g. `HomeRoute`.
  final String routeType;

  /// The path exactly as the `AutoRoute` spells it — `/home`, or the relative
  /// `profile` of a tab child (null if the `AutoRoute` omits `path:`).
  ///
  /// The source fact. To show a user where a route lives, use [fullPath]: a
  /// child's own path is not an address anyone can navigate to.
  final String? path;

  final String? _fullPath;

  /// The path the router actually serves, with a tab child's path joined onto
  /// its shell's — `/account/profile`, not `profile`.
  ///
  /// auto_route treats a child path as relative unless it starts with `/`, so
  /// printing [path] for a nested route states an address that does not exist.
  String? get fullPath => _fullPath ?? path;

  /// Whether the `AutoRoute` carries `initial: true` — the app's entry screen.
  final bool initial;

  /// The shell route this one is nested under (`children:` of a tab shell), or
  /// null for a top-level route.
  final String? parent;
}

/// The outcome of wiring a page into `AppRouter`.
class RouteWireResult implements EditOutcome {
  const RouteWireResult({
    required this.source,
    required this.changes,
    required this.alreadyWired,
    this.warnings = const [],
  });

  /// The full, edited `app_router.dart` source (unchanged if [alreadyWired]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when the same route was already registered — nothing was changed.
  final bool alreadyWired;

  @override
  bool get unchanged => alreadyWired;

  /// Non-fatal problems the caller should surface (e.g. `--public` requested
  /// but the guard's `_authArea` set could not be located).
  final List<String> warnings;
}

/// The outcome of unwiring a page from `AppRouter`.
class RouteUnwireResult with Unwiring {
  const RouteUnwireResult({
    required this.source,
    required this.changes,
    required this.found,
    this.warnings = const [],
  });

  /// The full, edited `app_router.dart` source (unchanged when not [found]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a route of the given type was registered and was removed.
  @override
  final bool found;

  /// Non-fatal problems the caller should surface (e.g. a removed tab shell
  /// whose child pages were left in place).
  final List<String> warnings;
}

/// Reads and edits `app/lib/navigation/app_router.dart` via the analyzer AST.
///
/// The auto_route analogue of [AppStateSource]: instead of hand-editing the
/// `routes` list (and the connector import, and the auth-area set) after
/// generating a page, `frx add-page` inserts them at precise AST offsets. Only
/// parses — no package config needed — and leans on `dart format` to normalize
/// whitespace afterwards.
class RoutesSource {
  RoutesSource(this.file);

  final File file;

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

  /// Finds `app_router.dart` by walking up from [startDir] (or the current
  /// directory) until `app/lib/navigation/app_router.dart` is found.
  static RoutesSource locate({String? startDir}) {
    final root = walkUpForMarker(
      startDir,
      _relativePath,
      (origin) =>
          'Could not find "$_relativePath" walking up from "$origin". '
          'Run this from inside the monorepo, or pass --root.',
    );
    return RoutesSource(File(p.join(root.path, _relativePath)));
  }

  /// The `app_router.dart` of an already-resolved workspace.
  ///
  /// [FrxWorkspace] keys on this very file, so the two cannot disagree about
  /// where the router is — which makes re-walking the tree from a command that
  /// already holds a workspace a second answer to a question already answered.
  static RoutesSource of(FrxWorkspace repo) =>
      RoutesSource(File(p.join(repo.root.path, _relativePath)));

  /// The routes currently registered in `AppRouter.routes`, in source order.
  ///
  /// Nested `children:` (a tab shell's pages) are included, each carrying the
  /// shell's route type as [RouteEntry.parent] — a tab page is as real a route
  /// as a top-level one, so every consumer (doctor's connector check, the
  /// navigation map) sees it.
  List<RouteEntry> readRoutes() {
    final entries = <RouteEntry>[];
    _collectRoutes(_routesList(_parse()), null, null, entries);
    return entries;
  }

  void _collectRoutes(
    ListLiteral list,
    String? parent,
    String? parentPath,
    List<RouteEntry> into,
  ) {
    for (final element in list.elements) {
      final args = _autoRouteArgs(element);
      if (args == null) continue;
      final page = _namedArg(args, 'page')?.toSource();
      final path = _namedArg(args, 'path');
      final initial = _namedArg(args, 'initial');
      final routeType = page != null
          ? page.replaceAll('.page', '')
          : '<unknown>';
      final own = path is SimpleStringLiteral ? path.value : path?.toSource();
      final full = _joinPath(parentPath, own, nested: parent != null);
      into.add(
        RouteEntry(
          routeType: routeType,
          path: own,
          fullPath: full,
          initial: initial is BooleanLiteral && initial.value,
          parent: parent,
        ),
      );
      final children = _namedArg(args, 'children');
      if (children is ListLiteral) {
        _collectRoutes(children, routeType, full, into);
      }
    }
  }

  /// Joins a child's path onto its shell's, the way auto_route resolves it: a
  /// path starting with `/` is absolute and ignores the parent, anything else
  /// hangs off it. An empty child path *is* the parent's — the tab that shows
  /// when you land on the shell.
  static String? _joinPath(
    String? parentPath,
    String? own, {
    required bool nested,
  }) {
    if (own == null) return parentPath;
    if (own.startsWith('/') || !nested) return own;
    // Nested under a shell that declares no `path:`: auto_route derives one
    // from its page name, which frx cannot know. Printing the child's own
    // relative path would be the same untruth composing exists to remove.
    if (parentPath == null) return own.isEmpty ? null : '…/$own';
    if (own.isEmpty) return parentPath;
    final base = parentPath.endsWith('/')
        ? parentPath.substring(0, parentPath.length - 1)
        : parentPath;
    return '$base/$own';
  }

  /// The route types the guard lets through while logged out — the
  /// `<Route>.name` members of `_AuthGuard._authArea`, with the `.name` dropped.
  /// Empty when there is no guard (or its set can't be read).
  Set<String> readAuthArea() {
    final set = _authAreaSet(_parse());
    if (set == null) return const {};
    return {
      for (final e in set.elements)
        if (e.toSource().endsWith('.name'))
          e.toSource().substring(0, e.toSource().length - '.name'.length),
    };
  }

  /// Wires a page into `AppRouter`: adds the connector import (kept sorted among
  /// the relative imports), an `AutoRoute(page: <Route>.page, path: '<path>')`
  /// entry in `routes`, and — when [public] — the route name in the guard's
  /// `_authArea` set. Idempotent when the route is already registered.
  RouteWireResult wirePage({
    required String routeType,
    required String connectorImport,
    required String path,
    required bool public,
    bool importMaterial = false,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = _parse(content);
    final list = _routesList(unit);
    final pageExpr = '$routeType.page';

    // Exact match on the `page:` argument — a substring `contains` would treat
    // `ProfileRoute` as already-wired when `UserProfileRoute` is registered.
    final already = list.elements.any((e) {
      final args = _autoRouteArgs(e);
      return args != null && _namedArg(args, 'page')?.toSource() == pageExpr;
    });
    if (already) {
      return RouteWireResult(
        source: content,
        changes: const [],
        alreadyWired: true,
      );
    }

    final edits = <Edit>[];
    final changes = <String>[];
    final warnings = <String>[];

    // 1) connector import, sorted among the relative imports.
    final imports = unit.directives.whereType<ImportDirective>().toList();
    if (!imports.any((d) => d.uri.stringValue == connectorImport)) {
      edits.add(importInsertion(imports, connectorImport));
      changes.add("import '$connectorImport';");
    }

    // A route with path params generates an args class referencing `Key`; the
    // generated `.gr.dart` is a `part`, so the library must import Flutter.
    if (importMaterial) {
      const material = 'package:flutter/material.dart';
      if (!imports.any((d) => d.uri.stringValue == material)) {
        edits.add(importInsertion(imports, material));
        changes.add("import '$material';");
      }
    }

    // 2) AutoRoute entry.
    final entry = "AutoRoute(page: $pageExpr, path: '$path')";
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
      final authArea = _authAreaSet(unit);
      if (authArea == null) {
        warnings.add(
          '--public: could not find the guard\'s _authArea set — the route was '
          'NOT added to it. Add "$routeType.name" manually if the page should '
          'be reachable while logged out.',
        );
      } else if (!authArea.elements.any(
        (e) => e.toSource() == '$routeType.name',
      )) {
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
  /// import, and a nested `AutoRoute(page: <Shell>.page, path: '<path>',
  /// children: [AutoRoute(page: <Tab>.page, path: '<tab>'), …])` entry.
  /// Idempotent when the shell route is already registered.
  ///
  /// Imports are applied one at a time (re-parsing between) so several relative
  /// imports each land in their own sorted position instead of colliding.
  RouteWireResult wireTabsRoute({
    required String shellRoute,
    required List<String> connectorImports,
    required String path,
    required List<({String route, String path})> tabs,
  }) {
    var source = sourceIndex.sourceOf(file);
    final shellExpr = '$shellRoute.page';

    final already = _routesList(_parse(source)).elements.any((e) {
      final args = _autoRouteArgs(e);
      return args != null && _namedArg(args, 'page')?.toSource() == shellExpr;
    });
    if (already) {
      return RouteWireResult(
        source: source,
        changes: const [],
        alreadyWired: true,
      );
    }

    final changes = <String>[];

    for (final imp in connectorImports) {
      final imports = _parse(
        source,
      ).directives.whereType<ImportDirective>().toList();
      if (!imports.any((d) => d.uri.stringValue == imp)) {
        source = applyEdits(source, [importInsertion(imports, imp)]);
        changes.add("import '$imp';");
      }
    }

    final children = tabs
        .map((t) => "AutoRoute(page: ${t.route}.page, path: '${t.path}')")
        .join(', ');
    final entry =
        "AutoRoute(page: $shellExpr, path: '$path', children: [$children])";
    final list = _routesList(_parse(source));
    source = applyEdits(source, [
      insertIntoList(
        elements: list.elements,
        closer: list.rightBracket,
        element: entry,
      ),
    ]);
    changes.add('routes: $shellRoute with ${tabs.length} tab(s)');

    return RouteWireResult(
      source: source,
      changes: changes,
      alreadyWired: false,
    );
  }

  /// Removes a page from `AppRouter`: drops its `AutoRoute(page: <routeType>
  /// .page, …)` entry, the connector import [connectorImport], and
  /// `<routeType>.name` from the guard's `_authArea` set when present. The
  /// inverse of [wirePage]; `found: false` when no such route is registered. A
  /// removed entry carrying nested `children` (a tab shell) is flagged so the
  /// caller can note the child pages were left in place.
  RouteUnwireResult unwirePage({
    required String routeType,
    required String connectorImport,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = _parse(content);
    final list = _routesList(unit);
    final pageExpr = '$routeType.page';

    final entry = list.elements.where((e) {
      final args = _autoRouteArgs(e);
      return args != null && _namedArg(args, 'page')?.toSource() == pageExpr;
    }).firstOrNull;
    if (entry == null) {
      return RouteUnwireResult(
        source: content,
        changes: const [],
        found: false,
      );
    }

    final edits = <Edit>[removeListItem(content, entry)];
    final changes = <String>['route $routeType'];
    final warnings = <String>[];

    final entryArgs = _autoRouteArgs(entry);
    if (entryArgs != null && _namedArg(entryArgs, 'children') != null) {
      warnings.add(
        '$routeType has nested children (a tab shell) — its child tab pages and '
        'their connectors were left in place; remove them separately.',
      );
    }

    // The connector import, matched exactly against the path add-page used.
    final imp = unit.directives
        .whereType<ImportDirective>()
        .where((d) => d.uri.stringValue == connectorImport)
        .firstOrNull;
    if (imp != null) {
      edits.add(removeDirective(content, imp));
      changes.add("import '$connectorImport'");
    }

    // Auth-area membership, if the page was reachable while logged out.
    final authArea = _authAreaSet(unit);
    if (authArea != null) {
      final member = authArea.elements
          .where((e) => e.toSource() == '$routeType.name')
          .firstOrNull;
      if (member != null) {
        edits.add(removeListItem(content, member));
        changes.add('_authArea: $routeType.name');
      }
    }

    var source = applyEdits(content, edits);

    // Prune the Flutter import once the last param route is gone. `add-page`
    // adds it only for a route with path params, so the generated `.gr.dart`
    // args class (which references `Key`) compiles; `app_router.dart` itself
    // uses no material symbols. Left dangling it would be an unused-import lint,
    // so drop it when no remaining route path carries a `:` segment. Re-parsed
    // (not offset-spliced) so this stays independent of the edits above.
    const material = 'package:flutter/material.dart';
    final after = _parse(source);
    final materialImport = after.directives
        .whereType<ImportDirective>()
        .where((d) => d.uri.stringValue == material)
        .firstOrNull;
    if (materialImport != null && !_anyParamPath(_routesList(after))) {
      source = applyEdits(source, [removeDirective(source, materialImport)]);
      changes.add("import '$material'");
    }

    return RouteUnwireResult(
      source: source,
      changes: changes,
      found: true,
      warnings: warnings,
    );
  }

  /// Whether any `AutoRoute` in [list] (or its nested `children`) has a `path`
  /// with a `:` param segment — the sole reason `app_router.dart` imports
  /// Flutter, so it gates pruning that import on removal.
  bool _anyParamPath(ListLiteral list) {
    for (final element in list.elements) {
      final args = _autoRouteArgs(element);
      if (args == null) continue;
      final path = _namedArg(args, 'path');
      if (path is SimpleStringLiteral && path.value.contains(':')) return true;
      final children = _namedArg(args, 'children');
      if (children is ListLiteral && _anyParamPath(children)) return true;
    }
    return false;
  }

  // --- AST helpers ----------------------------------------------------------

  /// The tree for [file], or for [content] when the caller is mid-edit and
  /// holding text that is not on disk yet.
  CompilationUnit _parse([String? content]) => content == null
      ? sourceIndex.unitFor(file)
      : parseString(content: content, throwIfDiagnostics: false).unit;

  ClassDeclaration _class(CompilationUnit unit, String name) {
    final cls = classNamed(unit, name);
    if (cls == null) {
      throw StateError('class $name not found in "${file.path}".');
    }
    return cls;
  }

  Iterable<ClassMember> _members(ClassDeclaration cls) {
    final body = cls.body;
    return body is BlockClassBody ? body.members : const <ClassMember>[];
  }

  /// The `[...]` literal returned by `AppRouter`'s `routes` getter.
  ListLiteral _routesList(CompilationUnit unit) {
    final router = _class(unit, 'AppRouter');
    final getter = _members(router)
        .whereType<MethodDeclaration>()
        .where((m) => m.isGetter && m.name.lexeme == 'routes')
        .firstOrNull;
    if (getter == null) {
      throw StateError('AppRouter.routes getter not found in "${file.path}".');
    }
    final body = getter.body;
    final expr = body is ExpressionFunctionBody
        ? body.expression
        : body is BlockFunctionBody
        ? _returnedExpression(body)
        : null;
    if (expr is! ListLiteral) {
      throw StateError(
        'AppRouter.routes does not return a list literal — cannot wire '
        'automatically.',
      );
    }
    return expr;
  }

  Expression? _returnedExpression(BlockFunctionBody body) {
    final finder = _ReturnFinder();
    body.accept(finder);
    return finder.expression;
  }

  /// The guard's `static const _authArea = {…}` set, or null if absent.
  SetOrMapLiteral? _authAreaSet(CompilationUnit unit) {
    final guard = classNamed(unit, '_AuthGuard');
    if (guard == null) return null;
    for (final member in _members(guard).whereType<FieldDeclaration>()) {
      for (final v in member.fields.variables) {
        if (v.name.lexeme == '_authArea' && v.initializer is SetOrMapLiteral) {
          return v.initializer! as SetOrMapLiteral;
        }
      }
    }
    return null;
  }

  /// The argument list of an `AutoRoute(...)` / `AutoRoute.guarded(...)` list
  /// element, or null if the element is not an `AutoRoute`.
  ///
  /// Every written form goes through [Construction] — see there for why the
  /// node type alone never answers this.
  ArgumentList? _autoRouteArgs(CollectionElement element) {
    final made = Construction.of(element);
    return made?.typeName == 'AutoRoute' ? made!.arguments : null;
  }

  Expression? _namedArg(ArgumentList args, String name) =>
      namedArgumentIn(args, name);
}

/// Finds the first returned expression in a block body.
class _ReturnFinder extends RecursiveAstVisitor<void> {
  Expression? expression;

  @override
  void visitReturnStatement(ReturnStatement node) {
    expression ??= node.expression;
    super.visitReturnStatement(node);
  }
}
