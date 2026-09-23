/// What frx recognises in `app_router.dart`, read off the tree.
///
/// The shapes every route reader and editor keys on: which list elements
/// register a page, which of them registers a given route, what the guard
/// lets through while logged out, and what a nested `children:` list means
/// for a child's address. `RoutesSource` reads and edits through these so
/// that `list-routes`, `remove` and the audit cannot disagree about what a
/// route is — measured once already, when a subclass one of them did not
/// recognise was a screen the others could not see.
library;

import 'package:analyzer/dart/ast/ast.dart';

import '../ast/construction.dart';
import '../ast/declarations.dart';
import 'route_entry.dart';

/// The auto_route classes that register a page — the ones carrying a `page:`
/// argument that names a generated route type.
///
/// auto_route spells a transition as a *subclass*, not as an argument:
/// `CustomRoute` is how a route stops painting a ground of its own
/// (`opaque: false`, for a sheet over the screen behind it), and
/// `MaterialRoute` / `CupertinoRoute` / `AdaptiveRoute` pick a platform
/// transition. All five register a screen exactly as `AutoRoute` does, so
/// matching the base class by name hid one from every reader here at once:
/// `list-routes` omitted it, doctor called its connector unregistered, and
/// `flow` deleted its generated document as a page that had gone.
///
/// Two subclasses are deliberately absent. `RedirectRoute` takes no `page:`
/// (it supplies `PageInfo.redirect` itself) and `NamedRouteDef` takes a
/// `name:` and a builder. Admitting either would enter a route whose type
/// reads `<unknown>`, and would let an unwiring and [anyParamPath] treat a
/// redirect as a screen.
const _pageRouteTypes = {
  'AutoRoute',
  'MaterialRoute',
  'CupertinoRoute',
  'AdaptiveRoute',
  'CustomRoute',
};

/// The argument list of a page-registering list element — `AutoRoute(...)`,
/// `AutoRoute.guarded(...)`, `CustomRoute<void>(...)` — or null when the
/// element registers no page. [_pageRouteTypes] says which types count.
///
/// Every written form goes through [Construction] — see there for why the
/// node type alone never answers this, and why the `<void>` of a
/// `CustomRoute<void>` is already off the name by the time it arrives here.
ArgumentList? pageRouteArgs(CollectionElement element) {
  final made = Construction.of(element);
  return made != null && _pageRouteTypes.contains(made.typeName)
      ? made.arguments
      : null;
}

/// One page-registering element of a routes list — top-level or nested in a
/// shell's `children:` — with the shell it sits under.
final class PageRouteNode {
  PageRouteNode._(this.element, this.args, this.parent);

  final CollectionElement element;
  final ArgumentList args;

  /// The shell whose `children:` hold this route, or null at the top level.
  final PageRouteNode? parent;

  /// The route type its `page:` names — `HomeRoute` for `HomeRoute.page`.
  String get routeType =>
      namedArgumentIn(args, 'page')?.toSource().replaceAll('.page', '') ??
      '<unknown>';
}

/// Every page route [list] registers, nested `children:` included, in source
/// order with each shell before its tabs.
///
/// **The one walk.** The readers saw nested routes and the editors did not:
/// `readRoutes` descended into `children:`, while the lookup `remove` unwired
/// through searched only the top-level list — so removing a tab page said
/// "route FeedRoute not registered — nothing to unwire", deleted its connector,
/// and left the route pointing at nothing. Both now ask this.
Iterable<PageRouteNode> pageRoutesIn(
  ListLiteral list, [
  PageRouteNode? parent,
]) sync* {
  for (final element in list.elements) {
    final args = pageRouteArgs(element);
    if (args == null) {
      continue;
    }

    final node = PageRouteNode._(element, args, parent);
    yield node;
    final children = namedArgumentIn(args, 'children');
    if (children is ListLiteral) {
      yield* pageRoutesIn(children, node);
    }
  }
}

/// The route in [list] — at any depth — that registers [routeType], or null
/// when none does.
///
/// Exact match on the `page:` argument — a substring `contains` would treat
/// `ProfileRoute` as already-wired when `UserProfileRoute` is registered.
PageRouteNode? registeredRoute(ListLiteral list, String routeType) {
  for (final route in pageRoutesIn(list)) {
    if (route.routeType == routeType) {
      return route;
    }
  }
  return null;
}

/// The routes [list] registers, in source order.
///
/// Nested `children:` (a tab shell's pages) are included, each carrying the
/// shell's route type as [RouteEntry.parent] — a tab page is as real a route
/// as a top-level one, so every consumer (doctor's connector check, the
/// navigation map) sees it.
List<RouteEntry> routeEntriesOf(ListLiteral list) {
  // A shell is yielded before its tabs, so its full path is known by the time
  // a child asks for it.
  final fullPaths = <PageRouteNode, String?>{};
  return [
    for (final route in pageRoutesIn(list)) _entryOf(route, fullPaths),
  ];
}

RouteEntry _entryOf(PageRouteNode route, Map<PageRouteNode, String?> full) {
  final path = namedArgumentIn(route.args, 'path');
  final initial = namedArgumentIn(route.args, 'initial');
  final own = path is SimpleStringLiteral ? path.value : path?.toSource();
  final parent = route.parent;
  final fullPath = full[route] = _joinPath(
    parent == null ? null : full[parent],
    own,
    nested: parent != null,
  );
  return RouteEntry(
    routeType: route.routeType,
    path: own,
    fullPath: fullPath,
    initial: initial is BooleanLiteral && initial.value,
    parent: parent?.routeType,
    offset: route.element.offset,
  );
}

/// Joins a child's path onto its shell's, the way auto_route resolves it: a
/// path starting with `/` is absolute and ignores the parent, anything else
/// hangs off it. An empty child path *is* the parent's — the tab that shows
/// when you land on the shell.
String? _joinPath(String? parentPath, String? own, {required bool nested}) {
  if (own == null) {
    return parentPath;
  }

  if (own.startsWith('/') || !nested) {
    return own;
  }
  // Nested under a shell that declares no `path:`: auto_route derives one
  // from its page name, which frx cannot know. Printing the child's own
  // relative path would be the same untruth composing exists to remove.
  if (parentPath == null) {
    return own.isEmpty ? null : '…/$own';
  }

  if (own.isEmpty) {
    return parentPath;
  }

  final base = parentPath.endsWith('/')
      ? parentPath.substring(0, parentPath.length - 1)
      : parentPath;
  return '$base/$own';
}

/// Whether any page route in [list] (or its nested `children`) other than
/// [except] and what it nests has a `path` with a `:` param segment — the sole
/// reason `app_router.dart` imports Flutter, so it gates pruning that import
/// on removal.
bool anyParamPath(ListLiteral list, {PageRouteNode? except}) {
  bool leaving(PageRouteNode route) {
    for (PageRouteNode? at = route; at != null; at = at.parent) {
      if (except != null && identical(at.element, except.element)) {
        return true;
      }
    }
    return false;
  }

  for (final route in pageRoutesIn(list)) {
    final path = namedArgumentIn(route.args, 'path');
    if (!leaving(route) &&
        path is SimpleStringLiteral &&
        path.value.contains(':')) {
      return true;
    }
  }
  return false;
}

/// The guard's `static const _authArea = {…}` set, or null if absent.
SetOrMapLiteral? authAreaSetOf(CompilationUnit unit) {
  final guard = classNamed(unit, '_AuthGuard');
  if (guard == null) {
    return null;
  }

  for (final member in guard.body.members.whereType<FieldDeclaration>()) {
    for (final v in member.fields.variables) {
      if (v.name.lexeme == '_authArea' && v.initializer is SetOrMapLiteral) {
        return v.initializer! as SetOrMapLiteral;
      }
    }
  }
  return null;
}

/// The `<Route>.name` member of [authArea] for [routeType], or null.
CollectionElement? authAreaMember(SetOrMapLiteral authArea, String routeType) {
  final member = '$routeType.name';
  for (final e in authArea.elements) {
    if (e.toSource() == member) {
      return e;
    }
  }

  return null;
}
