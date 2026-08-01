import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/routing/routes_source.dart';

import 'support/parses.dart';

const _appRouter = '''
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';

import '../connectors/home_page_connector.dart';
import '../connectors/log_in_page_connector.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'PageConnector|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LogInRoute.page, path: '/log-in'),
    AutoRoute(page: HomeRoute.page, path: '/home'),
  ];
}

class _AuthGuard extends AutoRouteGuard {
  static const _authArea = {
    LogInRoute.name,
  };
}
''';

void main() {
  _fullPathTests();
  late Directory dir;
  late RoutesSource source;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('frx_routes_');
    final file = File('${dir.path}/app_router.dart')
      ..writeAsStringSync(_appRouter);
    source = RoutesSource(file);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('readRoutes lists the registered routes with their paths', () {
    final routes = source.readRoutes();
    expect(routes.map((r) => r.routeType), ['LogInRoute', 'HomeRoute']);
    expect(routes.map((r) => r.path), ['/log-in', '/home']);
  });

  test(
    'wire adds a public route + connector import + auth-area membership',
    () {
      final r = source.wirePage(
        routeType: 'IntroRoute',
        connectorImport: '../connectors/intro_page_connector.dart',
        path: '/intro',
        public: true,
      );
      expect(r.alreadyWired, isFalse);
      expect(r.warnings, isEmpty);
      expect(
        r.source,
        contains("import '../connectors/intro_page_connector.dart';"),
      );
      expect(
        r.source,
        contains("AutoRoute(page: IntroRoute.page, path: '/intro')"),
      );
      expect(r.source, contains('IntroRoute.name'));
      expectParses(r.source);

      source.file.writeAsStringSync(r.source);
      expect(
        source.readRoutes().map((e) => e.routeType),
        contains('IntroRoute'),
      );
    },
  );

  test('wire is idempotent and exact-matches the page argument', () {
    final r = source.wirePage(
      routeType: 'HomeRoute',
      connectorImport: '../connectors/home_page_connector.dart',
      path: '/home',
      public: false,
    );
    expect(r.alreadyWired, isTrue);
    expect(r.source, _appRouter);
  });

  test('unwire is the inverse of wire (route set returns to the original)', () {
    final wired = source.wirePage(
      routeType: 'IntroRoute',
      connectorImport: '../connectors/intro_page_connector.dart',
      path: '/intro',
      public: true,
    );
    source.file.writeAsStringSync(wired.source);

    final unwired = source.unwirePage(
      routeType: 'IntroRoute',
      connectorImport: '../connectors/intro_page_connector.dart',
    );
    expect(unwired.found, isTrue);
    source.file.writeAsStringSync(unwired.source);

    expect(source.readRoutes().map((r) => r.routeType), [
      'LogInRoute',
      'HomeRoute',
    ]);
    expect(unwired.source, isNot(contains('IntroRoute')));
    expect(unwired.source, isNot(contains('intro_page_connector')));
    expectParses(unwired.source);
  });
}

void _fullPathTests() {
  RoutesSource sourceOf(String routes) {
    final dir = Directory.systemTemp.createTempSync('frx_paths_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'app_router.dart'))
      ..writeAsStringSync('''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
$routes
  ];
}
''');
    return RoutesSource(file);
  }

  group('fullPath', () {
    test('a tab child hangs off its shell', () {
      final routes = sourceOf('''
    AutoRoute(page: AccountRoute.page, path: '/account', children: [
      AutoRoute(page: ProfileRoute.page, path: 'profile'),
    ]),
''').readRoutes();
      final profile = routes.firstWhere((r) => r.routeType == 'ProfileRoute');
      // `path` stays the source fact; `fullPath` is the address that exists.
      expect(profile.path, 'profile');
      expect(profile.fullPath, '/account/profile');
    });

    test('a child path starting with / ignores its shell', () {
      final routes = sourceOf('''
    AutoRoute(page: AccountRoute.page, path: '/account', children: [
      AutoRoute(page: RootRoute.page, path: '/root'),
    ]),
''').readRoutes();
      // auto_route treats a leading slash as absolute — joining it would state
      // an address the router never serves.
      expect(
        routes.firstWhere((r) => r.routeType == 'RootRoute').fullPath,
        '/root',
      );
    });

    test('an empty child path is the shell itself', () {
      final routes = sourceOf('''
    AutoRoute(page: AccountRoute.page, path: '/account', children: [
      AutoRoute(page: ProfileRoute.page, path: ''),
    ]),
''').readRoutes();
      // The tab you land on when you open the shell — not `/account/`.
      expect(
        routes.firstWhere((r) => r.routeType == 'ProfileRoute').fullPath,
        '/account',
      );
    });

    test('a child of a pathless shell says so instead of guessing', () {
      final routes = sourceOf('''
    AutoRoute(page: ShellRoute.page, children: [
      AutoRoute(page: TabRoute.page, path: 'tab'),
    ]),
''').readRoutes();
      // auto_route derives the shell's path from its page name, which frx
      // cannot know. Reporting `tab` would be the address-that-does-not-exist
      // this composition was added to stop printing.
      expect(
        routes.firstWhere((r) => r.routeType == 'TabRoute').fullPath,
        '…/tab',
      );
    });

    test('a relative path at top level is not treated as nested', () {
      final routes = sourceOf(
        "    AutoRoute(page: HomeRoute.page, path: 'home'),\n",
      ).readRoutes();
      // No shell above it, so nothing is missing — it is the path as written.
      expect(routes.single.fullPath, 'home');
    });

    test('a top-level route is its own full path', () {
      final routes = sourceOf(
        "    AutoRoute(page: HomeRoute.page, path: '/home'),\n",
      ).readRoutes();
      expect(routes.single.fullPath, '/home');
    });

    test('two levels of nesting compose all the way down', () {
      final routes = sourceOf('''
    AutoRoute(page: ShopRoute.page, path: '/shop', children: [
      AutoRoute(page: AccountRoute.page, path: 'account', children: [
        AutoRoute(page: ProfileRoute.page, path: 'profile'),
      ]),
    ]),
''').readRoutes();
      expect(
        routes.firstWhere((r) => r.routeType == 'ProfileRoute').fullPath,
        '/shop/account/profile',
      );
    });
  });
}
