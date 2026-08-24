import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WaitingAction` composed with the async_redux behaviour mixins.
///
/// **The one thing about this mixin that no other test can see.** The template
/// tests in `tools/` check what `frx add-action` *writes*; the analyzer checks
/// that it compiles. Neither notices that
///
///     class SendVoiceAction extends Action with WaitingAction, NonReentrant
///
/// runs to completion and leaves `isWaitingForType<SendVoiceAction>()` true for
/// the rest of the session — a button that never re-enables. Dart runs one
/// `after()`, the last mixin's, and `NonReentrant.after()` releases its own
/// lock and returns without `super.after()`. `Throttle` and `Fresh` do the
/// same.
///
/// So the fix has two halves and this file pins both: `WaitingAction` chains
/// `super` in `before()` and `after()`, and it is mixed in **last** so it is
/// the one Dart calls. Reversing either half is a silent regression — which is
/// what shipped.
Store<AppState> _store() => Store<AppState>(initialState: AppState.initial());

/// The reduce body every probe shares: async, so `Wait` is observable.
mixin _Probe on ReduxAction<AppState> {
  static var runs = 0;

  @override
  Future<AppState?> reduce() async {
    _Probe.runs++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return null;
  }
}

/// The shape `frx add-action -k waiting -m nonReentrant` writes.
class NonReentrantProbe extends Action
    with NonReentrant, WaitingAction, _Probe {}

/// `-m throttle`.
class ThrottleProbe extends Action with Throttle, WaitingAction, _Probe {}

/// `-m fresh`.
class FreshProbe extends Action with Fresh, WaitingAction, _Probe {}

/// `-m checkInternet` — the reason `before()` returns `Future<void>` rather
/// than `void`. `CheckInternet` narrows the return type, so a `void` override
/// of it does not compile; this class existing is the assertion.
class CheckInternetProbe extends Action
    with CheckInternet, WaitingAction, _Probe {}

/// The template's own combination, which Dart pins the other way round:
/// `BlockingAction` is declared `on WaitingAction`, so it must follow it.
class BlockingProbe extends Action with WaitingAction, BlockingAction, _Probe {}

/// The same defect with the clause in the right order and the base mixin
/// chaining correctly — the *action* ends the chain.
///
/// A class member wins over the whole `with` clause, so this `after()` is the
/// only one Dart runs. Nothing about it looks wrong, and nothing else in the
/// tree can see it: the doctor rule and this test are the two things that can.
class _OwnAfter extends Action with NonReentrant, WaitingAction, _Probe {
  @override
  void after() {}
}

/// And the other hook: a `before()` that does not chain never raises the
/// barrier at all, so the indicator simply never appears.
class _OwnBefore extends Action with NonReentrant, WaitingAction, _Probe {
  @override
  Future<void> before() async {}
}

/// The correct spelling of both, as the control — an action with real work in
/// its own hooks that still passes the chain on.
class _OwnHooksChained extends Action with NonReentrant, WaitingAction, _Probe {
  final ran = <String>[];

  @override
  Future<void> before() async {
    ran.add('before');
    await super.before();
  }

  @override
  void after() {
    ran.add('after');
    super.after();
  }
}

void main() {
  setUp(() => _Probe.runs = 0);

  group('the barrier comes down', () {
    for (final probe in <String, Action Function()>{
      'NonReentrant': NonReentrantProbe.new,
      'Throttle': ThrottleProbe.new,
      'Fresh': FreshProbe.new,
      'BlockingAction': BlockingProbe.new,
    }.entries) {
      test('with ${probe.key}', () async {
        final store = _store();
        final action = probe.value();
        await store.dispatchAndWait(action);

        expect(
          store.state.wait.isWaiting(action),
          isFalse,
          reason:
              '${action.runtimeType} finished and is still in Wait — '
              '${probe.key} ended the after() chain, so WaitingAction.after() '
              'never ran and every widget reading isWaiting stays disabled',
        );
      });
    }
  });

  test('it composes with a mixin that narrows before()', () {
    // Not dispatched — `CheckInternet.before()` reaches connectivity_plus,
    // which is not a thing to boot for this. Constructing it is the assertion:
    // `CheckInternet` declares `Future<void> before()`, so a `WaitingAction`
    // placed after it that returned `void` would not compile, and this file
    // would not load.
    expect(CheckInternetProbe(), isA<WaitingAction>());
  });

  group('an action that writes its own hook', () {
    test('a bare after() leaves the barrier up', () async {
      final store = _store();
      final action = _OwnAfter();
      await store.dispatchAndWait(action);

      expect(
        store.state.wait.isWaiting(action),
        isTrue,
        reason:
            'if this ever goes false the defect is gone and the doctor rule '
            'that reports it has nothing left to report',
      );
    });

    test('a bare before() never raises it', () async {
      final store = _store();
      final pending = store.dispatchAndWait(_OwnBefore());

      expect(store.state.wait.isWaitingAny, isFalse);
      await pending;
    });

    test('chaining both is correct in both directions', () async {
      final store = _store();
      final action = _OwnHooksChained();
      final pending = store.dispatchAndWait(action);

      expect(store.state.wait.isWaiting(action), isTrue, reason: 'up');
      await pending;
      expect(store.state.wait.isWaiting(action), isFalse, reason: 'and down');
      expect(action.ran, ['before', 'after'], reason: 'its own work ran too');
    });
  });

  test('the barrier is up while the action runs', () async {
    // The other direction, or "comes down" would pass on a mixin that never
    // raised it: `before()` has to still put the action into Wait, and
    // synchronously, so the indicator is up in the same frame as the tap.
    final store = _store();
    final pending = store.dispatchAndWait(NonReentrantProbe());

    expect(store.state.wait.isWaitingForType<NonReentrantProbe>(), isTrue);
    await pending;
  });

  test('NonReentrant still releases its own lock', () async {
    // The half a bare reorder would have lost. `WaitingAction.after()` calls
    // `super.after()`, so `NonReentrant.after()` runs too and the key is freed
    // — without it the action is dispatchable exactly once per session.
    final store = _store();
    await store.dispatchAndWait(NonReentrantProbe());
    await store.dispatchAndWait(NonReentrantProbe());

    expect(
      _Probe.runs,
      2,
      reason:
          'the second dispatch was aborted — the non-reentrant key from '
          'the first was never released',
    );
  });

  test('NonReentrant still blocks a concurrent dispatch', () async {
    // And the lock is real while it is held, or the test above would pass on a
    // NonReentrant that had stopped working altogether.
    final store = _store();
    final first = store.dispatchAndWait(NonReentrantProbe());
    final second = store.dispatchAndWait(NonReentrantProbe());
    await Future.wait([first, second]);

    expect(_Probe.runs, 1);
  });
}
