import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:flutter_test/flutter_test.dart';

/// What actually happens to a mixin pair async_redux declares incompatible.
///
/// **Here because `tools/` cannot ask.** frx depends on nothing the app depends
/// on, so every fact it holds about async_redux is a transcription its own
/// tests check by reading the package source. That settles what the source
/// *says*. It cannot settle what Dart does with it — and the two turned out to
/// disagree with each other, which no amount of reading would have shown.
///
/// Every member of a group declares the same private marker
/// (`_cannot_combine_mixins_Fresh_Throttle_NonReentrant_…`), and `dart analyze`
/// reports the combination as `private_collision_in_mixin_application`. **The
/// compiler does not.** The CFE builds the class, so a test file the gate
/// rejects still runs, and the only thing left standing between the pair and a
/// working app is async_redux's own `assert` inside `_incompatible<T1, T2>` —
/// which fires on the first dispatch of a debug build and is stripped from a
/// release one.
///
/// So the guard is the analyzer, the runtime is a backstop a release build does
/// not have, and `add-action` refusing the pair is the only one of the three
/// that happens before the file exists.
///
/// The `ignore` is the subject of the test, not a workaround: this is the
/// combination the analyzer forbids, and the question is what survives it.
// ignore: private_collision_in_mixin_application
class TwoSwallowers extends Action with NonReentrant, Throttle, WaitingAction {
  static var ran = false;

  @override
  Future<AppState?> reduce() async {
    ran = true;
    return null;
  }
}

void main() {
  setUp(() => TwoSwallowers.ran = false);

  test('the compiler builds what the analyzer refuses', () {
    // The assertion is that this file loaded at all. If the CFE ever catches up
    // with the analyzer, this stops compiling — which is the notification
    // wanted, and the reason the finding lives in a test and not only in a
    // comment.
    expect(TwoSwallowers(), isA<ReduxAction<AppState>>());
  });

  test('and an assert stops it on dispatch, in a debug build', () {
    final store = Store<AppState>(initialState: AppState.initial());

    // Synchronously, out of the `dispatchAndWait` call itself rather than the
    // future it would have returned: `Throttle.abortDispatch` runs the marker
    // before the store has an action in flight. Awaiting the future instead
    // never sees it.
    expect(
      () => store.dispatchAndWait(TwoSwallowers()),
      throwsA(isA<AssertionError>()),
    );
    expect(TwoSwallowers.ran, isFalse, reason: 'the reducer must not have run');
  }, skip: _assertsAreOff ? 'asserts are disabled in this run' : null);
}

/// Whether this run has asserts compiled out — a release build, where the whole
/// runtime guard is absent. `flutter test` enables them, so the test above
/// runs; saying so in the skip reason beats a green tick that proved nothing.
bool get _assertsAreOff {
  var on = false;
  assert(() {
    on = true;
    return true;
  }(), 'probe');
  return !on;
}
