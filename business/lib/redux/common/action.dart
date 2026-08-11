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

/// Registers the action in `Wait` while it runs, so a selector can read that it
/// is in flight — `_state.wait.isWaitingForType<MyAction>()`.
///
/// That is all it says. It drives an indicator; it does not decide whether the
/// screen is usable meanwhile. A background refresh, a poll or a paginating
/// load wants exactly this and nothing more.
mixin WaitingAction on ReduxAction<AppState> {
  bool get notifyBefore => true;
  bool get notifyAfter => false;

  @override
  void before() => dispatchSync(WaitAction.add(this), notify: notifyBefore);

  @override
  void after() => dispatchSync(WaitAction.remove(this), notify: notifyAfter);
}

/// The user is blocked on this: the modal barrier covers the app while it runs.
///
/// **Separate from [WaitingAction] because "is in flight" and "the screen is
/// unusable" are different claims,** and the second is the one nobody should
/// make by accident. The barrier asks `isWaitingForType<BlockingAction>()` —
/// `WaitAction.add(this)` files the action itself as the flag and
/// `isWaitingForType<T>` tests `flag is T`, so a mixin answers as readily as a
/// class, and the set needs no list anywhere.
///
/// Keyed on this rather than on `Wait` membership because every async action
/// that wants an indicator reaches for [WaitingAction]; if that also meant the
/// barrier, the first background operation anyone adds would blank the app.
/// Opting in is a sentence you write on purpose.
mixin BlockingAction on WaitingAction {}
