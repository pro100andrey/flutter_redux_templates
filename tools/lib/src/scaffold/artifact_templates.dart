import '../util/casing.dart';
import 'type_imports.dart';

/// Pure string templates for the single-file scaffolders, matched to the real
/// repo's style (not the older `templates/common/*`, which use relative imports
/// and stale idioms). Each returns Dart source; `dart format` normalizes it.
///
/// Kept as plain strings — these artifacts are boilerplate a human reads and
/// edits, so matching the hand-written files verbatim beats structural codegen.
class ArtifactTemplates {
  const ArtifactTemplates._();

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

  /// A `StoreConnector` for the dumb widget of the same name (in `ui/widgets/`).
  static String connector(Casing n) =>
      '''
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:ui/widgets/${n.snake}.dart';

class ${n.pascal}Connector extends StatelessWidget {
  const ${n.pascal}Connector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => const ${n.pascal}(),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ${n.pascal}Connector, _Vm>
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
    // three that override it without calling `super.after()`. Emitted first,
    // as this used to, `WaitingAction` sat behind one of those and its `after()`
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
      "import '../../app_state.dart';\n",
      "import '../../common/action.dart';\n",
    ].join();

    final body = switch (kind) {
      ActionKind.sync =>
        '  // TODO(frx): return a new state via state.copyWith(...), or null for none.\n'
            '  @override\n'
            '  AppState? reduce() => null;\n',
      ActionKind.async =>
        '  // TODO(frx): do async work, then return a new state (or null for none).\n'
            '  @override\n'
            '  Future<AppState?> reduce() async => null;\n',
      ActionKind.waiting =>
        '  // TODO(frx): async work guarded by the waiting barrier (see WaitingAction).\n'
            '  @override\n'
            '  Future<AppState?> reduce() async => null;\n',
    };

    return '${imports}\nclass ${n.pascal}Action $clause {\n$overrides$body}\n';
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
  /// template does not have. Without it the setter was the one file of the three
  /// `add-field --action` writes that missed the models import — the state file
  /// and the facade both got it — so `final Task? selected;` arrived undefined.
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
      "import '../../app_state.dart';\n",
      "import '../../common/action.dart';\n",
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

  /// A `@freezed` model; with [json] it also emits `fromJson`/`toJson`.
  static String model(Casing n, {required bool json}) {
    final gPart = json ? "part '${n.snake}.g.dart';\n" : '';
    final fromJson = json
        ? '\n  factory ${n.pascal}.fromJson(Map<String, dynamic> json) =>\n'
              '      _\$${n.pascal}FromJson(json);\n'
        : '';
    return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${n.snake}.freezed.dart';
${gPart}
@freezed
abstract class ${n.pascal} with _\$${n.pascal} {
  factory ${n.pascal}({required int id}) = _${n.pascal};
$fromJson}
''';
  }

  /// A `@freezed` sealed union (in `models/lib/`): one factory per case,
  /// `<Pascal><Case>` implementation classes. With [json], a discriminated
  /// `fromJson` (freezed keys on `runtimeType` by default).
  static String modelUnion(Casing n, List<Casing> cases, {required bool json}) {
    final gPart = json ? "part '${n.snake}.g.dart';\n" : '';
    final fromJson = json
        ? '\n  factory ${n.pascal}.fromJson(Map<String, dynamic> json) =>\n'
              '      _\$${n.pascal}FromJson(json);\n'
        : '';
    final factories = [
      for (final c in cases)
        '  // TODO(frx): give the ${c.camel} case its fields.\n'
            '  const factory ${n.pascal}.${c.camel}() = ${n.pascal}${c.pascal};\n',
    ].join('\n');
    return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${n.snake}.freezed.dart';
${gPart}
@freezed
sealed class ${n.pascal} with _\$${n.pascal} {
$factories$fromJson}
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

/// The body shape for a generated action.
enum ActionKind {
  sync,
  async,
  waiting;

  static ActionKind parse(String v) =>
      ActionKind.values.byName(v.toLowerCase());
}

/// async_redux behaviour mixins `add-action --mixin` can attach.
///
/// [clause] is the mixin name as it appears in the `with` clause (typed with
/// `<AppState>` by the template); [implies] is a mixin that must precede this
/// one (`NoDialog on CheckInternet`, `UnlimitedRetries on Retry`);
/// [overrideBlock] surfaces the tuning override worth editing right away.
enum ActionMixin {
  /// Check connectivity in `before()`; show the error dialog when offline.
  checkInternet(
    'CheckInternet',
    'Check connectivity first; error dialog when offline',
  ),

  /// With [checkInternet]: mark the error dialog-less (`ifOpenDialog: false`).
  noDialog(
    'NoDialog',
    'With checkInternet: fail without the dialog',
    implies: checkInternet,
  ),

  /// Abort silently when offline (no dialog, no error).
  abortWhenNoInternet('AbortWhenNoInternet', 'Abort silently when offline'),

  /// Ignore a dispatch while the same action is already running.
  nonReentrant(
    'NonReentrant',
    'Ignore a dispatch while already running',
    swallowsAfter: true,
    knobs: {'nonReentrantKeyParams'},
    overrideBlock:
        '  // One lock per action type: LoadX(a) is ignored while LoadX(b) is\n'
        '  // running. Override to let each instance run on its own:\n'
        '  // Object? nonReentrantKeyParams() => someId;\n\n',
  ),

  /// Retry a failing `reduce()` with exponential backoff.
  retry(
    'Retry',
    'Retry failures with exponential backoff',
    knobs: {'maxRetries', 'initialDelay', 'multiplier', 'maxDelay'},
    overrideBlock:
        '  // TODO(frx): tune the backoff — also initialDelay (350ms),\n'
        '  // multiplier (2) and maxDelay (5s).\n'
        '  @override\n'
        '  int get maxRetries => 3;\n\n',
  ),

  /// With [retry]: keep retrying forever.
  unlimitedRetries(
    'UnlimitedRetries',
    'With retry: never stop retrying',
    implies: retry,
  ),

  /// Wait for a pause in dispatches before running (search-as-you-type).
  debounce(
    'Debounce',
    'Run only after a pause in dispatches',
    knobs: {'debounce', 'lockBuilder'},
    overrideBlock:
        '  // TODO(frx): tune the pause that must elapse before the action runs.\n'
        '  @override\n'
        '  int get debounce => 300; // milliseconds\n\n'
        '  // One lock per action type. Override lockBuilder() to give each\n  // instance its own: Object? lockBuilder() => someId;\n\n',
  ),

  /// Drop dispatches while a recent run is still fresh.
  throttle(
    'Throttle',
    'Drop dispatches while a recent run is fresh',
    swallowsAfter: true,
    knobs: {'throttle', 'lockBuilder'},
    overrideBlock:
        '  // TODO(frx): tune how long a run stays fresh (dispatches are dropped).\n'
        '  @override\n'
        '  int get throttle => 1000; // milliseconds\n\n'
        '  // One lock per action type. Override lockBuilder() to give each\n  // instance its own: Object? lockBuilder() => someId;\n\n',
  ),

  /// Skip the run entirely while the last result is still considered fresh.
  fresh(
    'Fresh',
    'Skip the run while the last result is still fresh',
    // Milliseconds, like `debounce` and `throttle` — async_redux declares
    // `int get freshFor => 1000; // Milliseconds`. This used to emit
    // `60; // seconds`, so a scaffolded action stayed fresh for 60ms while its
    // own comment promised a minute, and `Fresh` silently did nothing.
    swallowsAfter: true,
    knobs: {'freshFor', 'freshKeyParams'},
    overrideBlock:
        '  // TODO(frx): tune how long the last result stays fresh.\n'
        '  @override\n'
        '  int get freshFor => 60000; // milliseconds (1 minute)\n\n'
        '  // The fresh-key is the action TYPE, so LoadX(a) and LoadX(b) share\n'
        '  // one window and the second is skipped. Override to split them:\n'
        '  // Object? freshKeyParams() => someId;\n\n',
  ),

  /// Retry forever, treating "offline" as just another failure to retry —
  /// a single mixin replacing [checkInternet] + [retry] + [unlimitedRetries].
  unlimitedRetryCheckInternet(
    'UnlimitedRetryCheckInternet',
    'Retry forever, treating offline as a failure to retry',
    knobs: {'initialDelay', 'multiplier', 'maxDelay', 'maxDelayNoInternet'},
    overrideBlock:
        '  // TODO(frx): tune initialDelay / multiplier / maxDelay / maxDelayNoInternet.\n',
  );

  const ActionMixin(
    this.clause,
    this.summary, {
    this.implies,
    this.overrideBlock = '',
    this.knobs = const {},
    this.swallowsAfter = false,
  });

  /// The identifier used in the generated `with` clause.
  final String clause;

  /// One line on what it does, for a picker or `--help`.
  ///
  /// Here rather than in each consumer: the CLI's `allowedHelp`, the editor's
  /// multi-select and the wizard all showed their own hand-typed copy, and two
  /// of the three had drifted to eight of the ten mixins.
  final String summary;

  /// A mixin this one is declared `on` — must be present and precede it.
  final ActionMixin? implies;

  /// Tuning override(s) emitted into the class body.
  final String overrideBlock;

  /// Whether the mixin overrides `after()` **without** calling `super.after()`.
  ///
  /// Dart calls one `after()` per class — the last mixin's. One of these placed
  /// last therefore ends the chain, and every earlier mixin's cleanup is simply
  /// never run. That is not a hazard the analyzer can see: `with WaitingAction,
  /// NonReentrant` compiles, analyzes clean, and leaves the wait barrier raised
  /// for the rest of the session.
  ///
  /// So it is data, in the catalogue, next to [implies] and [exclusiveGroups] —
  /// the two other facts frx transcribes from async_redux. It is why [action]
  /// emits `WaitingAction` last (unconditionally: last is safe whether or not
  /// one of these is present, and a rule with no branch cannot take the wrong
  /// one). `list-mixins` prints it, and the `action-mixin-order` audit check
  /// enforces the position in files frx did not write.
  ///
  /// `action_template_test` derives the set from the package source and checks
  /// the emitted clause against it, so a mixin that gains or loses its
  /// `super.after()` upstream cannot leave either this flag or the order stale.
  final bool swallowsAfter;

  /// The async_redux members [overrideBlock] names — as data, not prose.
  ///
  /// The block is a string, so a renamed member on the package side would
  /// leave frx writing a `TODO` about a knob that no longer exists, and nothing
  /// would notice: a wrong name in a comment is still valid Dart.
  /// `action_template_test` checks this set against what async_redux declares.
  final Set<String> knobs;

  /// Sets of mixins async_redux declares mutually exclusive.
  ///
  /// **Declared, and enforced far more weakly than this comment used to say.**
  /// It said the members collide on a private name, so combining two is a
  /// compile error (`private_collision_in_mixin_application`). Measured: they
  /// are all declared in one library, and `private_collision_in_mixin_application`
  /// is about mixins from *different* libraries — so
  /// `with NonReentrant, Throttle` compiles and analyzes clean. What stops it is
  /// `_incompatible<T1, T2>`, which is an `assert`: it throws on the first
  /// dispatch in a debug build, and is stripped from a release one.
  ///
  /// That makes mirroring the groups here more valuable, not less: `add-action`
  /// refusing the pair up front is the only check that happens before the code
  /// exists. The marker method's *name* is still the readable source of the
  /// rule, which is what `action_template_test` derives the groups from.
  static const List<Set<ActionMixin>> exclusiveGroups = [
    {fresh, throttle, nonReentrant, unlimitedRetryCheckInternet},
    {checkInternet, abortWhenNoInternet, unlimitedRetryCheckInternet},
    {debounce, retry, unlimitedRetryCheckInternet},
  ];

  /// Every mixin this one cannot be combined with, implications included.
  ///
  /// Pairwise is exact here: [expand] adds each mixin's [implies] chain
  /// independently, so a set conflicts exactly when some pair in its expansion
  /// shares a group. That is what lets a picker filter by set membership
  /// instead of re-running [conflictIn] over every candidate — and lets the
  /// rule stay here, where async_redux's own constraint is mirrored, rather
  /// than being re-encoded in an editor.
  ///
  /// `noDialog` conflicts with `abortWhenNoInternet` for this reason: it does
  /// not share a group with it, but the `checkInternet` it implies does.
  Set<ActionMixin> get conflictsWith => {
    for (final other in ActionMixin.values)
      if (other != this && conflictIn(expand([name, other.name])) != null)
        other,
  };

  /// The first conflicting pair among [mixins], or null when they compose.
  static (ActionMixin, ActionMixin)? conflictIn(List<ActionMixin> mixins) {
    for (final group in exclusiveGroups) {
      final clash = mixins.where(group.contains).toList();
      if (clash.length > 1) return (clash[0], clash[1]);
    }
    return null;
  }

  static ActionMixin parse(String v) => ActionMixin.values.byName(v);

  /// Expands [names] into mixins with every [implies] inserted before its
  /// dependent, deduplicated, in a stable order.
  static List<ActionMixin> expand(Iterable<String> names) {
    final out = <ActionMixin>[];
    void add(ActionMixin m) {
      if (out.contains(m)) return;
      if (m.implies != null) add(m.implies!);
      out.add(m);
    }

    names.map(parse).forEach(add);
    return out;
  }
}
