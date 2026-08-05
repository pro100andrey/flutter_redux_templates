import 'package:async_redux/async_redux.dart';
import 'package:logging/logging.dart';
import 'package:storage/storage.dart';

import '../dependencies.dart';
import '../environment.dart';
import '../persistor.dart';
import 'app_state.dart';
import 'models/localized_message.dart';

late Store<AppState>? _store;

Store<AppState> newStore({
  required Environment environment,
  required AppState initialState,
  required BaseKeyValueStorage settings,
  Persistor<AppState>? persistor,
  UserErrorWrapperHandler? userErrorWrapper,
}) {
  WaitAction.reducer = _waitReducer;

  _store = Store<AppState>(
    initialState: initialState,
    environment: environment,
    dependencies: (store) => AppDependencies(store, settings),
    persistor: persistor,
    globalErrorObserver: (store) =>
        _MyErrorObserver(customErrorWrapper: userErrorWrapper),
    actionObservers: [_ReduxActionLogger()],
    stateObservers: [_StateChangeObserver()],
    modelObserver: _DefaultModelObserver<dynamic>(),
  );

  return _store!;
}

/// Full boot for the app layer: opens storage, wires the [AppPersistor],
/// restores the last persisted state, and builds the store. Keeps the storage
/// backend inside `business` — the app never touches it.
///
/// [onError] turns a thrown object into the title and body the user sees. It is
/// the app's to supply, because translating is the app's job: `business` names
/// [LocalizedMessage] and never names `S`, so the arrow between the two
/// packages keeps pointing one way. Leaving it off means every failure reaches
/// the user as the raw `toString()` of a Dart object — which is what happened
/// while `newStore` took this parameter and `createStore` did not forward it.
Future<Store<AppState>> createStore(
  Environment environment, {
  UserErrorWrapperHandler? onError,
}) async {
  final settings = KeyValueStorage();
  await settings.setupStorage(dbFile: 'settings.db');

  final persistor = AppPersistor(settings);
  final initialState = await persistor.readState() ?? AppState.initial();

  return newStore(
    environment: environment,
    initialState: initialState,
    settings: settings,
    persistor: persistor,
    userErrorWrapper: onError,
  );
}

void _waitReducer(
  dynamic state,
  WaitOperation operation,
  Object? flag,
  Object? ref,
) =>
    //
    // ignore: avoid_dynamic_calls
    state.copyWith(
      //
      // ignore: avoid_dynamic_calls
      wait: state.wait.process(operation, flag: flag, ref: ref),
    );

class _MyErrorObserver extends GlobalErrorObserver<AppState> {
  _MyErrorObserver({this.customErrorWrapper});

  final _logger = Logger('Redux');
  final UserErrorWrapperHandler? customErrorWrapper;

  @override
  Object? observe() {
    _logger.shout('Error thrown during $action: $error');

    if (customErrorWrapper != null) {
      final message = customErrorWrapper!(error);
      if (message != null) {
        // `titleAndContent()` returns (message, reason) when both are set, so
        // the first argument is the dialog's *title*. These two were the other
        // way round, which would have rendered a LocalizedMessage's title as
        // the body and its message as the heading — invisible until now,
        // because nothing supplied a wrapper for this branch to run.
        return UserException(message.title, reason: message.message);
      }
    }

    if (error is UserException) {
      return error;
    }

    // Reached only when no wrapper was supplied, or it declined this error.
    // Both arguments are the same string on purpose: without a translator
    // there is no title to show, and repeating the text is less confusing
    // than a heading that says something the body contradicts. The place to
    // fix this is `createStore(onError:)`, not here.
    return UserException('$error', reason: error.toString());
  }
}

typedef UserErrorWrapperHandler = LocalizedMessage? Function(Object? error);

/// One in-flight dispatch, keyed by the action instance — stable across nested
/// WaitActions that would otherwise bump the global dispatchCount mid-action.
/// Lets the action logger print duration + the state diff on the action's line.
final _pending = <ReduxAction<AppState>, _PendingAction>{};

class _PendingAction {
  _PendingAction(ReduxAction<AppState> action)
    : stopwatch = Stopwatch()..start(),
      isSync = action.isSync();

  final Stopwatch stopwatch;
  final bool isSync;
  List<String> changed = const [];
}

class _ReduxActionLogger extends ActionObserver<AppState> {
  final _logger = Logger('Redux');

  @override
  void observe(
    ReduxAction<AppState> action,
    int dispatchCount, {
    bool ini = false,
  }) {
    if (action is WaitAction<AppState>) {
      // WaitActions log once, on end. The flag is usually the awaited action
      // (WaitingAction does `WaitAction.add(this)`) — show its type.
      if (!ini) {
        final flag = action.flag;
        final target = flag is ReduxAction ? flag.runtimeType : flag;
        _logger.info('⏳ WaitAction  ${action.operation.name}  $target');
      }
      return;
    }

    if (ini) {
      _pending[action] = _PendingAction(action);
      return;
    }

    // On end, one line: action, sync/async, duration, and the state diff
    // collected by _StateChangeObserver during this dispatch.
    final pending = _pending.remove(action);
    final kind = (pending?.isSync ?? true) ? 'sync' : 'async';
    final ms = ((pending?.stopwatch.elapsedMicroseconds ?? 0) / 1000)
        .toStringAsFixed(1);
    final changed = pending?.changed ?? const <String>[];
    final diff = changed.isEmpty ? '' : '  Δ ${changed.join(', ')}';
    _logger.info('${action.runtimeType}  #$dispatchCount  $kind ${ms}ms$diff');
  }
}

/// Records which top-level [AppState] substates an action changed into
/// [_pending], for the action logger to print. (`wait` is omitted — WaitActions
/// log themselves.)
class _StateChangeObserver implements StateObserver<AppState> {
  @override
  void observe(
    ReduxAction<AppState> action,
    AppState prev,
    AppState next,
    Object? error,
    int dispatchCount,
  ) {
    final pending = _pending[action];
    if (pending == null || error != null || identical(prev, next)) {
      return;
    }

    pending.changed = <String>[
      if (prev.connectivity != next.connectivity) 'connectivity',
      if (prev.login != next.login) 'login',
      if (prev.registration != next.registration) 'registration',
      if (prev.forgotPassword != next.forgotPassword) 'forgotPassword',
      if (prev.resetPassword != next.resetPassword) 'resetPassword',
      if (prev.session != next.session) 'session',
      if (prev.theme != next.theme) 'theme',
      if (prev.language != next.language) 'language',
    ];
  }
}

/// Logs each connector that actually rebuilt, tagged by #N (its action).
class _DefaultModelObserver<Model> implements ModelObserver<Model> {
  final _logger = Logger('Redux');

  @override
  void observe({
    required Model? modelPrevious,
    required Model? modelCurrent,
    bool? isDistinct,
    StoreConnectorInterface<dynamic, dynamic>? storeConnector,
    int? reduceCount,
    int? dispatchCount,
  }) {
    // Skip connectors that didn't rebuild.
    if (isDistinct != true) {
      return;
    }

    final name =
        (storeConnector?.debug == null ? storeConnector : storeConnector!.debug)
            .runtimeType;
    _logger.info('  ↻ $name  #$dispatchCount');
  }
}
