import '../util/casing.dart';

/// A typed route parameter, e.g. `(name: 'id', type: 'int')` → `/…/:id`.
typedef PageParam = ({String name, String type});

/// Produces the two source files for a new page: a dumb [StatelessWidget] in the
/// `ui` package and a `@RoutePage()` StoreConnector in the `app` package.
///
/// Plain string templates (no `code_builder`) — pages and connectors are boring
/// boilerplate whose shape mirrors the hand-written connectors already in the
/// repo, so matching them verbatim matters more than structural generation.
/// `dart format` normalizes the output afterwards.
///
/// [params] become constructor fields on both the connector and the page (and
/// path params on the route); auto_route binds `/:id` to the `id` field by name.
class PageScaffold {
  const PageScaffold(this.name, {this.params = const []});

  final Casing name;
  final List<PageParam> params;

  String get _snake => name.snake;
  String get _pascal => name.pascal;

  String get _ctorParams =>
      params.map((p) => 'required this.${p.name}, ').join();
  String get _fields =>
      params.map((p) => '  final ${p.type} ${p.name};').join('\n');

  /// The dumb page — lives in `ui/lib/pages/<snake>_page.dart`, store-agnostic.
  String page() {
    final body = params.isEmpty
        ? "const Center(child: Text('$_pascal — coming soon'))"
        : "Center(child: Text('${params.map((p) => '${p.name}: \$${p.name}').join(', ')}'))";
    return '''
import 'package:flutter/material.dart';

// TODO(frx): flesh out the $_pascal page. Keep it a dumb, store-agnostic
// widget — wire state in through ${_pascal}PageConnector (app package).
class ${_pascal}Page extends StatelessWidget {
  const ${_pascal}Page({$_ctorParams super.key});

$_fields

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('$_pascal')),
    body: $body,
  );
}
''';
  }

  /// The connector — lives in `app/lib/connectors/<snake>_page_connector.dart`.
  /// `@RoutePage()` makes auto_route generate a `${_pascal}Route` class. The
  /// empty `_Vm` is the seam to fill in as the page starts reading state.
  String connector() {
    final pageCall = params.isEmpty
        ? 'const ${_pascal}Page()'
        : '${_pascal}Page(${params.map((p) => '${p.name}: ${p.name}').join(', ')})';
    return '''
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/${_snake}_page.dart';

@RoutePage()
class ${_pascal}PageConnector extends StatelessWidget {
  const ${_pascal}PageConnector({$_ctorParams super.key});

$_fields

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => $pageCall,
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ${_pascal}PageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm();
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm() : super(equals: const []);
}
''';
  }
}
