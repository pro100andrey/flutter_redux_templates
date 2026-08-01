import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/routing/nav_source.dart';

import 'support/parses.dart';

/// A connector exactly as `frx add-page` writes one — the shape every hop
/// starts from, and the one the wiring has to handle without help.
const _connector = '''
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/catalog_page.dart';

@RoutePage()
class CatalogPageConnector extends StatelessWidget {
  const CatalogPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => const CatalogPage(),
  );
}

class _Factory extends VmFactory<AppState, CatalogPageConnector, _Vm> {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm();
}

class _Vm extends Vm {
  _Vm() : super(equals: const []);
}
''';

const _page = '''
import 'package:flutter/material.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) => const Placeholder();
}
''';

/// A destination connector with two typed route parameters.
const _itemConnector = '''
@RoutePage()
class ItemPageConnector extends StatelessWidget {
  const ItemPageConnector({required this.id, required this.slug, super.key});

  final int id;
  final String slug;
}
''';

File _tmp(String name, String content) {
  final dir = Directory.systemTemp.createTempSync('frx_nav_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File(p.join(dir.path, name))..writeAsStringSync(content);
}

const _nav = NavSource();

void main() {
  group('reading the destination', () {
    test('takes each route parameter with its declared type', () {
      final params = NavSource.paramsOf(
        _tmp('item_page_connector.dart', _itemConnector),
      );
      // The path says `:id` exists; only the field says it is an int.
      expect(params.map((p) => '${p.type} ${p.name}'), [
        'int id',
        'String slug',
      ]);
    });

    test('a destination with no parameters yields none', () {
      final params = NavSource.paramsOf(
        _tmp('home_page_connector.dart', '''
class HomePageConnector extends StatelessWidget {
  const HomePageConnector({super.key});
}
'''),
      );
      expect(params, isEmpty);
    });

    test('a field the constructor does not bind is not a route parameter', () {
      final params = NavSource.paramsOf(
        _tmp('item_page_connector.dart', '''
class ItemPageConnector extends StatelessWidget {
  const ItemPageConnector({required this.id, super.key});

  final int id;
  final ScrollController controller = ScrollController();
}
'''),
      );
      // A connector's own field would otherwise be handed to a route
      // constructor that does not accept it.
      expect(params.map((p) => p.name), ['id']);
    });
  });

  group('wiring the connector', () {
    NavWireResult wire({
      List<NavParam> params = const [NavParam('id', 'int')],
    }) => _nav.wireConnector(
      original: _connector,
      callback: 'onTapItem',
      routeType: 'ItemRoute',
      method: 'push',
      args: params.map((p) => '${p.name}: ${p.name}').join(', '),
      params: params,
      pageClass: 'CatalogPage',
    );

    test('the result parses', () {
      expectParses(wire().source, reason: 'the wired connector');
    });

    test('opens a named group on a constructor that has none', () {
      // `_Vm()` takes nothing, and every generated one starts that way.
      // Inserting straight into its parameter list makes the callback
      // positional — `_Vm(required this.onTapItem)`, which does not parse.
      expect(wire().source, contains('_Vm({required this.onTapItem})'));
    });

    test('the callback dispatches the route with its arguments', () {
      expect(
        wire().source,
        contains(
          'onTapItem: (id) => dispatch(GoAction.push(ItemRoute(id: id)))',
        ),
      );
    });

    test('a page gaining an argument stops being const', () {
      final source = wire().source;
      // `const CatalogPage()` cannot take `vm.onTapItem`. The trailing comma
      // is `insertIntoList` filling an empty argument list; these editors
      // return source, and the command runs `dart format` over it.
      expect(source, contains('CatalogPage(onTapItem: vm.onTapItem,)'));
      expect(source, isNot(contains('const CatalogPage(')));
    });

    test('both imports land sorted, in one block', () {
      final source = wire().source;
      final router = source.indexOf("import '../navigation/app_router.dart';");
      final go = source.indexOf("import '../navigation/go_action.dart';");
      expect(router, greaterThan(0));
      expect(go, greaterThan(router), reason: 'sorted');
      // Computed against the same parse, the second aims at the spot the first
      // is about to take — and they land split by a blank line, out of order.
      expect(
        source.substring(router, go),
        isNot(contains('\n\n')),
        reason: 'one block, no blank line between them',
      );
    });

    test('a destination with no parameters takes no lambda argument', () {
      final source = wire(params: const []).source;
      expect(source, contains('onTapItem: () => dispatch('));
      expect(source, contains('final void Function() onTapItem;'));
    });

    test('two parameters arrive in order', () {
      final source = wire(
        params: const [NavParam('id', 'int'), NavParam('slug', 'String')],
      ).source;
      expect(source, contains('(id, slug) =>'));
      expect(source, contains('ItemRoute(id: id, slug: slug)'));
      expect(source, contains('final void Function(int, String) onTapItem;'));
    });

    test('wiring the same hop twice changes nothing', () {
      final once = wire().source;
      final twice = _nav.wireConnector(
        original: once,
        callback: 'onTapItem',
        routeType: 'ItemRoute',
        method: 'push',
        args: 'id: id',
        params: const [NavParam('id', 'int')],
        pageClass: 'CatalogPage',
      );
      expect(twice.alreadyWired, isTrue);
      expect(twice.source, once);
    });

    test('--kind picks the GoAction factory', () {
      final source = _nav
          .wireConnector(
            original: _connector,
            callback: 'onTapItem',
            routeType: 'ItemRoute',
            method: 'replace',
            args: '',
            params: const [],
            pageClass: 'CatalogPage',
          )
          .source;
      expect(source, contains('GoAction.replace(ItemRoute())'));
    });

    test('a connector frx did not write is refused, not mangled', () {
      expect(
        () => _nav.wireConnector(
          original: 'class Whatever {}',
          callback: 'onTapItem',
          routeType: 'ItemRoute',
          method: 'push',
          args: '',
          params: const [],
          pageClass: 'CatalogPage',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('wiring the page', () {
    NavWireResult wire() => _nav.wirePage(
      content: _page,
      callback: 'onTapItem',
      pageClass: 'CatalogPage',
      params: const [NavParam('id', 'int')],
    );

    test('the result parses', () {
      expectParses(wire().source, reason: 'the wired page');
    });

    test('the parameter goes before super.key, which stays last', () {
      expect(
        wire().source,
        contains('const CatalogPage({required this.onTapItem, super.key})'),
      );
    });

    test('an optional-positional constructor is refused, not mangled', () {
      // Dart forbids `[optional]` alongside named parameters, so there is no
      // place to put the callback — splicing it after the last parameter
      // lands it inside the brackets and the file stops parsing.
      expect(
        () => _nav.wirePage(
          content:
              'class P extends StatelessWidget {\n'
              '  const P([this.a]);\n  final int? a;\n}\n',
          callback: 'onTap',
          pageClass: 'P',
          params: const [],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the field comes with it', () {
      expect(wire().source, contains('final void Function(int) onTapItem;'));
    });

    test('doing it twice changes nothing', () {
      final once = wire().source;
      final twice = _nav.wirePage(
        content: once,
        callback: 'onTapItem',
        pageClass: 'CatalogPage',
        params: const [NavParam('id', 'int')],
      );
      expect(twice.alreadyWired, isTrue);
      expect(twice.source, once);
    });
  });
}
