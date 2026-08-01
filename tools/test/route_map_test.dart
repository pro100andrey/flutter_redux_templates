import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/flow/flow_docs.dart';
import 'package:tools/src/flow/mermaid.dart';
import 'package:tools/src/flow/route_map.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// A workspace with a realistic router (initial route, auth area, a tab shell)
/// and connectors that navigate in every way the map has to draw.
FrxWorkspace _workspace() {
  final root = Directory.systemTemp.createTempSync('frx_map_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) {
    File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  put('app/lib/navigation/app_router.dart', '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: SplashRoute.page, path: '/splash', initial: true),
    AutoRoute(page: LogInRoute.page, path: '/login'),
    AutoRoute(page: RegistrationRoute.page, path: '/registration'),
    AutoRoute(page: SettingsRoute.page, path: '/settings'),
    AutoRoute(page: ShellRoute.page, path: '/shell', children: [
      AutoRoute(page: FeedRoute.page, path: 'feed'),
    ]),
  ];
}

class _AuthGuard extends AutoRouteGuard {
  static const _authArea = {LogInRoute.name, RegistrationRoute.name};
}
''');

  // Navigates from a reducer — the `⚡` edge the view-model never shows.
  put('business/lib/redux/session/actions/log_out_action.dart', '''
class LogOutAction extends Action {
  @override
  AppState reduce() {
    dispatch(GoAction.push(const LogInRoute()));
    return state.copyWith(session: const SessionState());
  }
}
''');

  put('app/lib/connectors/splash_page_connector.dart', '''
class _Factory extends VmFactory<AppState, SplashPageConnector, _Vm> {
  @override
  _Vm fromStore() => _Vm(title: 'nothing dispatched here');
}
''');

  put('app/lib/connectors/log_in_page_connector.dart', '''
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm> {
  @override
  _Vm fromStore() => _Vm(
    onPressedRegister: () => dispatch(GoAction.push(const RegistrationRoute())),
    onPressedSettings: () => dispatch(GoAction.push(const SettingsRoute())),
  );
}
''');

  // Pops back to its only pusher, and reaches a route with no connector.
  put('app/lib/connectors/registration_page_connector.dart', '''
class _Factory extends VmFactory<AppState, RegistrationPageConnector, _Vm> {
  @override
  _Vm fromStore() => _Vm(
    onPressedBack: () => dispatch(GoAction.pop()),
    onPressedDone: () async {
      final status = await dispatchAndWait(RegistrationAction());
      if (status.isCompletedOk) {
        dispatch(GoAction.replace(const GhostRoute()));
      }
    },
  );
}
''');

  // Two callbacks reaching the same navigating action — one edge, not two.
  put('app/lib/connectors/settings_page_connector.dart', '''
import 'package:business/redux/session/actions/log_out_action.dart';

class _Factory extends VmFactory<AppState, SettingsPageConnector, _Vm> {
  @override
  _Vm fromStore() => _Vm(
    onPressedLogOut: () => dispatch(LogOutAction()),
    onPressedLogOutAgain: () => dispatch(LogOutAction()),
  );
}
''');

  return FrxWorkspace.locate(startDir: root.path);
}

RouteMap _map() => RouteMapReader(_workspace()).read();

PageNode _node(RouteMap map, String page) =>
    map.pages.firstWhere((n) => n.page == page);

Iterable<NavEdge> _from(RouteMap map, String page) =>
    map.edges.where((e) => e.from == page);

void main() {
  group('RouteMapReader', () {
    test('every registered route becomes a node, nested ones included', () {
      final map = _map();
      expect(map.pages.map((n) => n.page), [
        'splash',
        'logIn',
        'registration',
        'settings',
        'shell',
        'feed',
      ]);
      expect(
        _node(map, 'feed').parent,
        'ShellRoute',
        reason: 'a tab page carries its shell',
      );
    });

    test('carries the routing facts the source states', () {
      final map = _map();
      expect(_node(map, 'splash').initial, isTrue);
      expect(_node(map, 'logIn').initial, isFalse);
      expect(_node(map, 'logIn').public, isTrue, reason: 'in _authArea');
      expect(_node(map, 'settings').public, isFalse);
      expect(_node(map, 'logIn').path, '/login');
      expect(_node(map, 'logIn').useCases, 2);
    });

    test('a route with no connector is still a node, without a flow', () {
      final map = _map();
      expect(_node(map, 'shell').connectorFile, isNull);
      expect(map.flows.containsKey('shell'), isFalse);
    });

    test('reads push hops with their trigger', () {
      final map = _map();
      final push = _from(
        map,
        'logIn',
      ).firstWhere((e) => e.to == 'registration');
      expect(push.kind, NavKind.push);
      expect(push.via, 'onPressedRegister');
      expect(push.fromAction, isFalse);
      expect(push.toRoute, 'RegistrationRoute');
    });

    test('a pop resolves to the only page that pushes it', () {
      final map = _map();
      final pop = _from(
        map,
        'registration',
      ).firstWhere((e) => e.kind == NavKind.pop);
      expect(pop.to, 'logIn');
      expect(pop.inferred, isTrue, reason: 'deduced from the stack, not read');
    });

    test('a pop nobody can resolve stays open rather than guessing', () {
      // `settings` is pushed only by `logIn`… so make sure the *unpushed* case
      // is the one left open: nothing pushes `feed`, so a pop there is a guess.
      final map = _map();
      final unresolvable = map.edges.where(
        (e) => e.kind == NavKind.pop && e.to == null,
      );
      expect(unresolvable, isEmpty, reason: 'this fixture pops only once');
      final pushers = map.edges
          .where((e) => e.kind == NavKind.push && e.to == 'registration')
          .length;
      expect(pushers, 1);
    });

    test('a guarded hop keeps its condition and its method', () {
      final map = _map();
      final replace = _from(
        map,
        'registration',
      ).firstWhere((e) => e.method == 'replace');
      expect(replace.condition, 'status.isCompletedOk');
      expect(replace.kind, NavKind.other);
      expect(replace.toRoute, 'GhostRoute');
    });

    test(
      'navigation dispatched from a reducer is attributed to the action',
      () {
        final map = _map();
        final edges = _from(map, 'settings').toList();
        expect(
          edges,
          hasLength(1),
          reason: 'two callbacks, one action, one hop',
        );
        expect(edges.single.via, 'LogOutAction');
        expect(edges.single.fromAction, isTrue);
        expect(edges.single.to, 'logIn');
      },
    );

    test('entryPoints are the pages nothing pushes', () {
      final map = _map();
      expect(
        map.entryPoints.map((n) => n.page),
        ['splash', 'shell'],
        reason:
            'logIn is not one: LogOutAction pushes it, which is exactly the '
            'hop a hand-drawn map misses',
      );
    });

    test('toJson round-trips the shape the extension reads', () {
      final json = _map().toJson();
      expect(json['pages'], isA<List<Object?>>());
      expect(json['edges'], isA<List<Object?>>());
      expect(json['entryPoints'], contains('splash'));
    });
  });

  group('renderRouteMap', () {
    test(
      'groups the public pages and gives the initial route its own shape',
      () {
        final out = renderRouteMap(_map());
        expect(out, startsWith('flowchart LR'));
        expect(out, contains('subgraph frxPublic'));
        expect(out, contains('splash(["SplashPage · /splash"])'));
        expect(out, contains('settings["SettingsPage · /settings"]'));
      },
    );

    test('the model resolves the shell join the renderer used to', () {
      // `parent` names a route *type*, pages are keyed by *name*. The renderer
      // walked every page for every page to bridge that; the reader had both
      // halves all along.
      const map = RouteMap(
        pages: [
          PageNode(
            page: 'account',
            routeType: 'AccountRoute',
            pageClass: 'AccountPage',
            path: '/account',
          ),
          PageNode(
            page: 'profile',
            routeType: 'ProfileRoute',
            pageClass: 'ProfilePage',
            path: '/account/profile',
            parent: 'AccountRoute',
          ),
          PageNode(
            page: 'settings',
            routeType: 'SettingsRoute',
            pageClass: 'SettingsPage',
            path: '/account/settings',
            parent: 'AccountRoute',
          ),
        ],
        edges: [],
      );
      expect(map.children, {
        'account': ['profile', 'settings'],
      });
      expect(map.shellOf('profile'), 'account');
      expect(map.shellOf('account'), isNull);
    });

    test(
      'a parent route with no page of its own leaves the child top-level',
      () {
        // The shape the old renderer handled by returning null from its lookup:
        // a `parent` naming a route frx could not pair with a page. Keeping that
        // behaviour matters — the alternative is dropping the node entirely,
        // which is the bug the public-shell fix was about.
        const map = RouteMap(
          pages: [
            PageNode(
              page: 'profile',
              routeType: 'ProfileRoute',
              pageClass: 'ProfilePage',
              path: '/x/profile',
              parent: 'NoSuchRoute',
            ),
          ],
          edges: [],
        );
        expect(map.children, isEmpty);
        expect(map.shellOf('profile'), isNull);
        expect(renderRouteMap(map), contains('profile['));
      },
    );

    test('a tab shell and its children are drawn as one region', () {
      final out = renderRouteMap(
        const RouteMap(
          pages: [
            PageNode(
              page: 'account',
              routeType: 'AccountRoute',
              pageClass: 'AccountPage',
              path: '/account',
            ),
            PageNode(
              page: 'profile',
              routeType: 'ProfileRoute',
              pageClass: 'ProfilePage',
              path: '/account/profile',
              parent: 'AccountRoute',
            ),
          ],
          edges: [],
        ),
      );
      // Without the box a tab child reads as another top-level screen you can
      // push to — the one thing a flat list of nodes cannot state.
      expect(out, contains('subgraph frxTabs_account'));
      final box = out.substring(out.indexOf('subgraph frxTabs_account'));
      expect(box.substring(0, box.indexOf('end')), contains('profile['));
      // And it appears once — inside the region, not also beside it.
      expect(RegExp('profile\\[').allMatches(out).length, 1);
    });

    test('a public tab shell keeps its children', () {
      final out = renderRouteMap(
        const RouteMap(
          pages: [
            PageNode(
              page: 'logIn',
              routeType: 'LogInRoute',
              pageClass: 'LogInPage',
              path: '/login',
              public: true,
            ),
            PageNode(
              page: 'account',
              routeType: 'AccountRoute',
              pageClass: 'AccountPage',
              path: '/account',
              public: true,
            ),
            PageNode(
              page: 'profile',
              routeType: 'ProfileRoute',
              pageClass: 'ProfilePage',
              path: '/account/profile',
              parent: 'AccountRoute',
            ),
          ],
          edges: [],
        ),
      );
      // Grouping only what survived the public/private split left a public
      // shell in one region and its children in neither — they disappeared.
      expect(out, contains('profile['));
      expect(RegExp(r'profile\[').allMatches(out).length, 1);
      // And the group travels with its shell, into the public region.
      final tabs = out.indexOf('subgraph frxTabs_account');
      final publicEnd = out.indexOf('    end');
      expect(tabs, greaterThan(0));
      expect(tabs, lessThan(publicEnd), reason: 'nested inside frxPublic');
    });

    test('draws push solid, pop dashed and a stack-replacing hop thick', () {
      final out = renderRouteMap(_map());
      expect(out, contains('logIn -->|"onPressedRegister"| registration'));
      expect(out, contains('registration -.->|"onPressedBack"| logIn'));
      expect(out, contains('(replace) [status.isCompletedOk]'));
    });

    test('marks a reducer-driven hop so it is not read as a button', () {
      expect(renderRouteMap(_map()), contains('⚡ LogOutAction'));
    });

    test('dashes the pages nothing pushes', () {
      final out = renderRouteMap(_map());
      final line = out
          .split('\n')
          .firstWhere((l) => l.trimLeft().startsWith('class '));
      expect(line, contains('shell'));
      expect(line, isNot(contains('splash')), reason: 'initial has its shape');
      expect(line, isNot(contains('registration')), reason: 'logIn pushes it');
    });

    test('a page named after mermaid syntax cannot break the diagram', () {
      final out = renderRouteMap(
        RouteMap(
          pages: const [
            PageNode(page: 'end', routeType: 'EndRoute', pageClass: 'EndPage'),
            PageNode(
              page: 'home',
              routeType: 'HomeRoute',
              pageClass: 'HomePage',
            ),
          ],
          edges: const [
            NavEdge(from: 'home', to: 'end', method: 'push', via: 'onDone'),
          ],
        ),
      );
      expect(out, contains('end_["EndPage"]'));
      expect(out, contains('home -->|"onDone"| end_'));
    });

    test('a label cannot smuggle in an edge or statement delimiter', () {
      final out = renderRouteMap(
        RouteMap(
          pages: const [
            PageNode(page: 'a', routeType: 'ARoute', pageClass: 'APage'),
            PageNode(page: 'b', routeType: 'BRoute', pageClass: 'BPage'),
          ],
          edges: const [
            NavEdge(
              from: 'a',
              to: 'b',
              method: 'push',
              via: 'tap',
              condition: 'x == "y" || z',
            ),
          ],
        ),
      );
      final edge = out.split('\n').firstWhere((l) => l.contains('-->'));
      expect('|'.allMatches(edge), hasLength(2), reason: 'exactly one label');
      expect(edge, isNot(contains('"y"')));
      expect(edge, contains('x == \'y\' or z'));
    });
  });

  group('FlowDocs', () {
    test('is opt-in: no docs/flows means nothing to check', () {
      final docs = FlowDocs(_workspace());
      expect(docs.enabled, isFalse);
      expect(docs.check(), isEmpty);
    });

    test('write creates the export and check then passes', () {
      final docs = FlowDocs(_workspace())..write();
      expect(docs.enabled, isTrue);
      expect(File(p.join(docs.dir.path, 'README.md')).existsSync(), isTrue);
      expect(docs.check(), isEmpty);
    });

    test('a second write is a no-op — the export is a pure function', () {
      final docs = FlowDocs(_workspace())..write();
      expect(docs.write(), isEmpty);
    });

    test('every generated file is stamped, and paths stay repo-relative', () {
      final docs = FlowDocs(_workspace())..write();
      for (final f in docs.dir.listSync().whereType<File>()) {
        final text = f.readAsStringSync();
        expect(text, contains(FlowDocs.marker), reason: p.basename(f.path));
        expect(
          text,
          isNot(contains(docs.workspace.root.path)),
          reason: 'an absolute path would drift on another machine',
        );
      }
    });

    test('a source change makes the export stale', () {
      final ws = _workspace();
      FlowDocs(ws).write();

      final connector = File(
        p.join(ws.appConnectors.path, 'log_in_page_connector.dart'),
      );
      connector.writeAsStringSync(
        connector.readAsStringSync().replaceAll(
          'onPressedRegister',
          'onTappedRegister',
        ),
      );

      final drift = FlowDocs(ws).check();
      expect(drift, isNotEmpty);
      expect(
        drift.map((d) => p.basename(d.path)),
        containsAll(['README.md', 'logIn.md']),
      );
      expect(drift.first.kind, DocDriftKind.stale);
    });

    test('a deleted doc is reported missing', () {
      final ws = _workspace();
      final docs = FlowDocs(ws)..write();
      File(p.join(docs.dir.path, 'logIn.md')).deleteSync();

      final drift = docs.check();
      expect(drift, hasLength(1));
      expect(drift.single.kind, DocDriftKind.missing);
      expect(drift.single.relative, 'docs/flows/logIn.md');
    });

    test('a doc whose page is gone is an orphan, and write deletes it', () {
      final ws = _workspace();
      final docs = FlowDocs(ws)..write();
      final ghost = File(p.join(docs.dir.path, 'ghost.md'))
        ..writeAsStringSync('${FlowDocs.marker}\n\n# GhostPage\n');

      expect(docs.check().single.kind, DocDriftKind.orphan);
      docs.write();
      expect(ghost.existsSync(), isFalse);
      expect(docs.check(), isEmpty);
    });

    test('a hand-written file in docs/flows is never touched', () {
      final ws = _workspace();
      final docs = FlowDocs(ws)..write();
      final mine = File(p.join(docs.dir.path, 'notes.md'))
        ..writeAsStringSync('# my own notes\n');

      expect(docs.check(), isEmpty, reason: 'unstamped: not ours to report');
      docs.write();
      expect(mine.readAsStringSync(), '# my own notes\n');
    });
  });
}
