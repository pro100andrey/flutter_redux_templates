import 'package:async_redux/async_redux.dart';

import '../app_state.dart';

mixin WithWaitState implements ReduxAction<AppState> {
  /// Whether to notify before the action is dispatched.
  bool get notifyBefore => false;

  @override
  void before() => dispatchSync(
        WaitAction.add(this),
        notify: notifyBefore,
      );

  bool get notifyAfter => false;

  @override
  void after() => dispatchSync(
        WaitAction.remove(this),
        notify: notifyAfter,
      );
}
