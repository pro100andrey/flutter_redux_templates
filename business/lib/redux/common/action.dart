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
///
/// **Both hooks call `super`, and that is load-bearing.** Dart gives a class
/// one `after()` — the last mixin's — and several async_redux mixins
/// (`NonReentrant`, `Throttle`, `Fresh`) override it to release their own lock
/// *without* calling `super.after()`. So in `with WaitingAction, NonReentrant`
/// this mixin's `after()` is never reached: the barrier goes up and never comes
/// down, and every widget reading `isWaitingForType<T>()` stays disabled for
/// the rest of the session. Reversing the pair only moves the loss — then it is
/// the reentrancy lock that is never released, and the action never runs twice.
///
/// Neither order works while this mixin swallows the chain, so it does not: it
/// cleans up and passes the baton, and `add-action` puts it **last** in the
/// `with` clause so it is the one Dart calls. `frx doctor` checks both halves.
///
/// `before()` returns `Future<void>` rather than `void` for a narrower reason:
/// `CheckInternet` declares `Future<void> before()`, and a `void` override of
/// it is a compile error — which is what a `WaitingAction` placed last, in
/// front of nothing, would otherwise be.
mixin WaitingAction on ReduxAction<AppState> {
  bool get notifyBefore => true;
  bool get notifyAfter => false;

  @override
  Future<void> before() async {
    // Synchronous — the body runs to the first `await` before the store gets
    // its future back, so the indicator is up in the same frame as the tap.
    dispatchSync(WaitAction.add(this), notify: notifyBefore);
    await super.before();
  }

  @override
  void after() {
    // Locks first, barrier second: whoever wakes on the barrier coming down
    // finds a dispatchable action rather than one still holding its own lock.
    super.after();
    dispatchSync(WaitAction.remove(this), notify: notifyAfter);
  }
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
