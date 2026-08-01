import 'package:async_redux/async_redux.dart';

import '../../dependencies.dart';
import '../../environment.dart';
import '../app_state.dart';

abstract class Action extends ReduxAction<AppState> with Selectors {
  /// Injected services for this store (see [AppDependencies]).
  AppDependencies get deps => store.dependencies! as AppDependencies;

  /// The store environment (base URL, prod/dev, …).
  Environment get env => store.environment! as Environment;
}

mixin WaitingAction on ReduxAction<AppState> {
  bool get notifyBefore => true;
  bool get notifyAfter => false;

  @override
  void before() => dispatchSync(WaitAction.add(this), notify: notifyBefore);

  @override
  void after() => dispatchSync(WaitAction.remove(this), notify: notifyAfter);
}
