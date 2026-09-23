import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../ast/construction.dart';
import '../ast/file_source.dart';
import '../redux/ast_edit.dart';

/// A tab shell's connector — the `AutoTabsScaffold` `add-tabs` writes, whose
/// `routes:` and whose bottom bar's `items:` list the tabs index for index.
///
/// Removing a tab page unwired its route from the router and left it here:
/// `routes: [FeedRoute(), …]` named a class the next build no longer
/// generates, and the project stopped compiling in a file the preview only
/// listed. The two lists are one fact written twice — the bar's item *i* is
/// the tab *i* shows — so a tab leaves both at the same index or neither:
/// dropping the route alone would compile and then fail at runtime, the bar
/// holding one item more than the scaffold has tabs.
class TabShellSource extends FileSource {
  TabShellSource(super.file);

  /// The smallest bar `BottomNavigationBar` accepts; it asserts on fewer.
  static const minTabs = 2;

  /// This file without the tab [routeType], or [Unwired.absent] when it does
  /// not list that tab in the shape `add-tabs` writes — a shell edited into
  /// another shape, or one whose lists have drifted apart, is left for its
  /// author, and so is a shell the removal would leave with fewer than
  /// [minTabs] tabs.
  Unwired withoutTab(String routeType) {
    final (source: content, :unit) = snapshot;
    final finder = _TabLists();
    unit.accept(finder);
    for (final (:routes, :items) in finder.found) {
      final i = routes.elements.indexWhere(
        (e) => Construction.of(e)?.fullName == routeType,
      );
      if (i < 0 ||
          items == null ||
          items.elements.length != routes.elements.length ||
          routes.elements.length - 1 < minTabs) {
        continue;
      }
      return Unwired(
        source: applyEdits(content, [
          removeListItem(content, routes.elements[i]),
          removeListItem(content, items.elements[i]),
        ]),
        changes: ['tab $routeType (routes: and its bar item)'],
      );
    }
    return Unwired.absent(content);
  }
}

/// Every `AutoTabsScaffold(routes: [...])` and the `items: [...]` its bottom
/// bar builder passes, when it has one.
class _TabLists extends GeneralizingAstVisitor<void> {
  final found = <({ListLiteral routes, ListLiteral? items})>[];

  @override
  void visitNode(AstNode node) {
    if (Construction.of(node) case final c?
        when c.fullName == 'AutoTabsScaffold') {
      if (c.namedArgument('routes') case final ListLiteral routes) {
        final items = _ItemsList();
        c.namedArgument('bottomNavigationBuilder')?.accept(items);
        found.add((routes: routes, items: items.list));
      }
    }
    super.visitNode(node);
  }
}

/// The first `items: [...]` argument under the node it visits.
class _ItemsList extends RecursiveAstVisitor<void> {
  ListLiteral? list;

  @override
  void visitArgumentList(ArgumentList node) {
    if (namedArgumentIn(node, 'items') case final ListLiteral items
        when list == null) {
      list = items;
    }
    super.visitArgumentList(node);
  }
}
