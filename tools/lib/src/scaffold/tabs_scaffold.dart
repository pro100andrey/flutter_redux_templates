import '../util/casing.dart';

/// The shell page for a tab flow: a `@RoutePage()` widget hosting auto_route's
/// [AutoTabsScaffold] with a bottom navigation bar over the tab routes.
///
/// Lives in `app/lib/connectors/<name>_page_connector.dart` — it must be in the
/// `app` package because it references the generated tab route classes
/// (`HomeRoute`, …), which live in `app_router.gr.dart`.
class TabsScaffold {
  const TabsScaffold(this.name, this.tabs);

  final Casing name;
  final List<Casing> tabs;

  String shell() {
    final routes = tabs.map((t) => '${t.pascal}Route()').join(', ');
    final items = tabs
        .map(
          (t) =>
              "BottomNavigationBarItem(icon: Icon(Icons.circle_outlined), label: '${t.pascal}')",
        )
        .join(',\n');
    return '''
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../navigation/app_router.dart';

@RoutePage()
class ${name.pascal}PageConnector extends StatelessWidget {
  const ${name.pascal}PageConnector({super.key});

  @override
  Widget build(BuildContext context) => AutoTabsScaffold(
    routes: const [$routes],
    bottomNavigationBuilder: (_, tabsRouter) => BottomNavigationBar(
      currentIndex: tabsRouter.activeIndex,
      onTap: tabsRouter.setActiveIndex,
      items: const [
        $items,
      ],
    ),
  );
}
''';
  }
}
