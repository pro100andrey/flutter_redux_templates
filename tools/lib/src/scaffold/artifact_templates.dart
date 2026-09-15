import '../util/casing.dart';
import 'action_mixin.dart';
import 'type_imports.dart';

export 'action_mixin.dart';

/// Pure string templates for the single-file scaffolders, matched to the real
/// repo's style (not the older `templates/common/*`, which use relative imports
/// and stale idioms). Each returns Dart source; `dart format` normalizes it.
///
/// Kept as plain strings — these artifacts are boilerplate a human reads and
/// edits, so matching the hand-written files verbatim beats structural codegen.
class ArtifactTemplates {
  const ArtifactTemplates._();

  /// The two relative imports every action under `redux/<substate>/actions/`
  /// carries: the state it reduces and the app's own action base.
  static const actionImports =
      "import '../../app_state.dart';\n"
      "import '../../common/action.dart';\n";

  /// The `build` of a `StoreConnector<AppState, _Vm>` whose builder returns
  /// [builds] — the same three lines in a widget connector and a page
  /// connector, because the two are the same shape with a different dumb
  /// widget under them.
  static String storeConnectorBuild(String builds) =>
      '''
  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => $builds,
  );
''';

  /// The empty `_Factory`/`_Vm` pair under a connector class named
  /// [connectorClass] — the seam to fill in as the widget starts reading state.
  static String viewModelSeam(String connectorClass) =>
      '''

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, $connectorClass, _Vm>
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

  /// A dumb `StatelessWidget` (in `ui/lib/widgets/`).
  static String widget(Casing n) =>
      '''
import 'package:flutter/material.dart';

class ${n.pascal} extends StatelessWidget {
  const ${n.pascal}({super.key});

  // TODO(frx): build the ${n.pascal} widget.
  @override
  Widget build(BuildContext context) => const Placeholder();
}
''';

  /// A `StoreConnector` for the dumb widget of the same name (in
  /// `ui/widgets/`).
  static String connector(Casing n) =>
      '''
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/widgets/${n.snake}.dart';

class ${n.pascal}Connector extends StatelessWidget {
  const ${n.pascal}Connector({super.key});

${storeConnectorBuild('const ${n.pascal}()')}}
${viewModelSeam('${n.pascal}Connector')}''';

  /// A `ReduxAction<AppState>` — `kind` picks the body shape, [mixins] adds
  /// async_redux behaviour mixins to the `with` clause (plus the tuning
  /// overrides worth surfacing, e.g. `debounce`/`throttle` durations).
  static String action(
    Casing n,
    ActionKind kind, {
    List<ActionMixin> mixins = const [],
  }) {
    // No `<AppState>`: Dart infers a generic mixin's type argument from its
    // `on ReduxAction<St>` constraint against the actual superclass, and
    // `Action extends ReduxAction<AppState>` pins it.
    //
    // `WaitingAction` goes **last**, after the behaviour mixins. Dart calls one
    // `after()` — the last mixin's — and [ActionMixin.swallowsAfter] marks the
    // three that override it without calling `super.after()`. Emitted first, as
    // this used to, `WaitingAction` sat behind one of those and its `after()`
    // never ran: the wait barrier went up and never came down, and every widget
    // reading `isWaitingForType<T>()` stayed disabled for good. The generated
    // file compiled, analyzed clean, and was wrong at runtime.
    //
    // Last works only because the app's `WaitingAction` chains `super` in both
    // hooks — see `business/lib/redux/common/action.dart`, and the
    // `action-mixin-order` audit check, which is what holds that end up in a
    // project frx does not own.
    final withMixins = [
      ...mixins.map((m) => m.clause),
      if (kind == ActionKind.waiting) 'WaitingAction',
    ];
    // Always the app's own base from `common/action.dart` — it is what carries
    // `deps`, `env` and the `Selectors` facade, and it is what every
    // hand-written action in the repo extends. Scaffolding a bare
    // `ReduxAction<AppState>` meant the first edit to a generated action was
    // changing its base class, which is exactly the hand-wiring frx exists to
    // remove.
    final clause = [
      'extends Action',
      if (withMixins.isNotEmpty) 'with ${withMixins.join(', ')}',
    ].join(' ');
    final overrides = mixins.map((m) => m.overrideBlock).join();

    // async_redux is imported only for the behaviour mixins — the one thing
    // here that really does come from the package.
    final imports = [
      if (mixins.isNotEmpty)
        "import 'package:async_redux/async_redux.dart';\n\n",
      actionImports,
    ].join();

    final body = switch (kind) {
      .sync =>
        '  // TODO(frx): return a new state via state.copyWith(...), or null for none.\n'
            '  @override\n'
            '  AppState? reduce() => null;\n',
      .async =>
        '  // TODO(frx): do async work, then return a new state (or null for none).\n'
            '  @override\n'
            '  Future<AppState?> reduce() async => null;\n',
      .waiting =>
        '  // TODO(frx): async work guarded by the waiting barrier (see WaitingAction).\n'
            '  @override\n'
            '  Future<AppState?> reduce() async => null;\n',
    };

    return '$imports\nclass ${n.pascal}Action $clause {\n$overrides$body}\n';
  }

  /// A `Set<Field>Action` that copies [field] (of [type]) onto the [substate]
  /// via `state.copyWith.<substate>(...)` — the setter `add-field --action`
  /// emits alongside a new state field.
  ///
  /// [type] is written into the file, so whatever supplies it has to be
  /// imported here too — asked of [TypeImports] rather than left to the caller,
  /// which is the hole that shipped `final IList<String> tags;` with no
  /// `fast_immutable_collections` import.
  ///
  /// [extraImports] carries what [TypeImports] cannot answer: a type this
  /// *project* defines, which is only resolvable against a workspace this
  /// template does not have. Without it the setter was the one file of the
  /// three `add-field --action` writes that missed the models import — the
  /// state file and the facade both got it — so `final Task? selected;` arrived
  /// undefined.
  static String fieldSetter(
    Casing substate,
    Casing field,
    String type, {
    List<String> extraImports = const [],
  }) {
    final packages = [
      for (final import in {...TypeImports.forType(type), ...extraImports})
        "import '$import';\n",
    ];
    final imports = [
      if (packages.isNotEmpty) ...[...packages, '\n'],
      actionImports,
    ].join();
    return '''
$imports
class Set${field.pascal}Action extends Action {
  Set${field.pascal}Action(this.${field.camel});

  final $type ${field.camel};

  @override
  AppState reduce() =>
      state.copyWith.${substate.camel}(${field.camel}: ${field.camel});
}
''';
  }

  /// The freezed preamble of a model file: the annotation import and the
  /// `part` directives — the `.g.dart` one only when [json] asks for it.
  static String _freezedHeader(Casing n, {required bool json}) =>
      '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${n.snake}.freezed.dart';
${json ? "part '${n.snake}.g.dart';\n" : ''}
@freezed
''';

  /// The `fromJson` factory a serializable model carries, or nothing.
  static String _fromJson(Casing n, {required bool json}) => json
      ? '\n  factory ${n.pascal}.fromJson(Map<String, dynamic> json) =>\n'
            '      _\$${n.pascal}FromJson(json);\n'
      : '';

  /// A `@freezed` model; with [json] it also emits `fromJson`/`toJson`.
  static String model(Casing n, {required bool json}) =>
      '''
${_freezedHeader(n, json: json)}abstract class ${n.pascal} with _\$${n.pascal} {
  factory ${n.pascal}({required int id}) = _${n.pascal};
${_fromJson(n, json: json)}}
''';

  /// One case of a sealed union: the redirecting factory and the note that
  /// its fields are still to be written.
  static String _unionCase(Casing n, Casing c) =>
      '  // TODO(frx): give the ${c.camel} case its fields.\n'
      '  const factory ${n.pascal}.${c.camel}() = ${n.pascal}${c.pascal};\n';

  /// A `@freezed` sealed union (in `models/lib/`): one factory per case,
  /// `<Pascal><Case>` implementation classes. With [json], a discriminated
  /// `fromJson` (freezed keys on `runtimeType` by default).
  static String modelUnion(Casing n, List<Casing> cases, {required bool json}) {
    final factories = [for (final c in cases) _unionCase(n, c)].join('\n');
    return '''
${_freezedHeader(n, json: json)}sealed class ${n.pascal} with _\$${n.pascal} {
$factories${_fromJson(n, json: json)}}
''';
  }

  /// A plain enum (in `models/lib/`).
  static String enumeration(Casing n, List<Casing> values) =>
      '''
enum ${n.pascal} {
${values.map((v) => '  ${v.camel},').join('\n')}
}
''';

  /// The service half of a service/listener pair (in `redux/services/<name>/`).
  ///
  /// The subject of an Observer: it talks to the outside world, knows nothing
  /// of Redux, and names only what it needs from whoever is listening. The
  /// interface is declared here, beside the class that calls it, so the
  /// dependency points from the listener to the service and not back.
  static String service(Casing n) =>
      '''
import '../../../common/services/interface.dart';

abstract class ${n.pascal}ServiceListener {
  void onStatusChange();
}

class ${n.pascal}Service extends DisposableServiceInterface {
  ${n.pascal}Service({required this._listener});

  final ${n.pascal}ServiceListener _listener;

  @override
  Future<void> start() async {
    super.start();
    // TODO(frx): begin work; call _listener.onStatusChange() on updates.
    _listener.onStatusChange();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    // TODO(frx): release resources.
  }
}
''';

  /// The listening half — turns a service event into a store dispatch.
  ///
  /// Named for what it does rather than for the role the interface gives it:
  /// the contract says "something the service notifies", this implementation
  /// dispatches. That leaves room for a second listener — a test double, a
  /// logger — that listens without dispatching.
  static String serviceDispatcher(Casing n) =>
      '''
import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '${n.snake}.dart';

class ${n.pascal}Dispatcher implements ${n.pascal}ServiceListener {
  ${n.pascal}Dispatcher({required this._store});

  // Held so onStatusChange can dispatch once you implement this.
  // ignore: unused_field
  final Store<AppState> _store;

  @override
  void onStatusChange() {
    // TODO(frx): dispatch onto _store based on the service event, e.g.
    // _store.dispatchSync(SomeAction());
  }
}
''';

  /// A Retrofit `@RestApi()` client (in `http_client/lib/api/`).
  static String retrofit(Casing n) =>
      '''
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part '${n.snake}.g.dart';

@RestApi()
abstract class ${n.pascal}Service {
  factory ${n.pascal}Service(Dio dio, {required String baseUrl}) =
      _${n.pascal}Service;

  @GET('/api/${n.words.join('-')}')
  Future<void> list();
}
''';

  /// A `ThemeExtension` (in `ui/lib/theme/extensions/`), matching `AppRadii`.
  static String themeExtension(Casing n) =>
      '''
import 'package:flutter/material.dart';
import 'package:theme_extensions_builder_annotation/theme_extensions_builder_annotation.dart';

part '${n.snake}.g.theme.dart';

/// Access via `context.${n.camel}`.
@ThemeExtensions(contextAccessorName: '${n.camel}')
class ${n.pascal} extends ThemeExtension<${n.pascal}> with _\$${n.pascal} {
  const ${n.pascal}({this.value = 0});

  // TODO(frx): replace with real design tokens.
  final double value;
}
''';
}
