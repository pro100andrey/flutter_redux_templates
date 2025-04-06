import 'package:async_redux/async_redux.dart';
import 'package:logging/logging.dart';
import 'app_state.dart';
import 'models/localized_message.dart';

late Store<AppState>? _store;

Store<AppState> newStore({UserErrorWrapperHandler? userErrorWrapper}) {
  WaitAction.reducer = _waitReducer;

  _store = Store<AppState>(
    initialState: AppState.initial(),
    errorObserver: _MyErrorObserver(),
    globalWrapError: _MyWrapError(customErrorWrapper: userErrorWrapper),
    actionObservers: [_ReduxActionLogger()],
    modelObserver: _DefaultModelObserver<dynamic>(),
  );

  return _store!;
}

void _waitReducer(
  // ignore: avoid_annotating_with_dynamic
  dynamic state,
  WaitOperation operation,
  Object? flag,
  Object? ref,
) =>
// ignore: avoid_dynamic_calls
state.copyWith(
  // ignore: avoid_dynamic_calls
  wait: state.wait.process(operation, flag: flag, ref: ref),
);

class _MyErrorObserver implements ErrorObserver<AppState> {
  final _logger = Logger('Redux');

  @override
  bool observe(
    Object error,
    StackTrace stackTrace,
    ReduxAction<AppState> action,
    Store store,
  ) {
    _logger.shout('Error thrown during $action: $error');

    return false;
  }
}

typedef UserErrorWrapperHandler = LocalizedMessage? Function(Object? error);

class _MyWrapError extends GlobalWrapError<AppState> {
  _MyWrapError({this.customErrorWrapper});
  final UserErrorWrapperHandler? customErrorWrapper;

  @override
  Object? wrap(Object error, StackTrace stackTrace, ReduxAction action) {
    if (customErrorWrapper != null) {
      final message = customErrorWrapper!(error);
      if (message != null) {
        return UserException(message.message, reason: message.title);
      }
    }

    if (error is UserException) {
      return error;
    }

    return UserException('$error', reason: error.toString());
  }
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
      final iniString = ini ? 'start' : 'end';

      _logger.info(
        'WaitAction '
        'flag: ${action.flag} '
        'ref: ${action.ref} '
        'O: ${action.operation.name} '
        'D: $dispatchCount - $iniString',
      );

      return;
    }

    _logger.info('$action D: $dispatchCount - ${ini ? 'start' : 'end'}');
  }
}

class _DefaultModelObserver<Model> implements ModelObserver<Model> {
  final _logger = Logger('Redux');

  @override
  // ignore: long-parameter-list
  void observe({
    required Model? modelPrevious,
    required Model? modelCurrent,
    bool? isDistinct,
    StoreConnectorInterface? storeConnector,
    int? reduceCount,
    int? dispatchCount,
  }) {
    final debug =
        (storeConnector?.debug == null ? storeConnector : storeConnector!.debug)
            .runtimeType;
    _logger.info(
      '$debug D: $dispatchCount R: $reduceCount Rebuild: $isDistinct',
    );
  }
}
