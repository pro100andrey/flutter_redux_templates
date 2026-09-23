import 'package:async_redux/async_redux.dart';
import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/session/actions/set_token_action.dart';
import 'package:business/redux/store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// The persistor writes at most once a second. These are the two moments that
/// cannot wait for it: a log-out, and the app being hidden — after either, the
/// process may be gone before the throttled write runs.
///
/// Every assertion is made well inside that second, after nothing more than the
/// event queue draining, so a write still parked behind the throttle fails it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryKeyValueStorage storage;

  /// A store over a real [AppPersistor], starting from [initial] — which the
  /// store takes to be what is already saved, so [storage] holds it too.
  Future<Store<AppState>> storeFrom(AppState initial) async {
    final persistor = AppPersistor(storage);
    await persistor.persistDifference(newState: initial);
    return Store<AppState>(initialState: initial, persistor: persistor);
  }

  setUp(() => storage = InMemoryKeyValueStorage());

  test('a log-out removes the saved token at once', () async {
    final store = await storeFrom(
      AppState.initial().copyWith.session(token: 'tok'),
    );

    store.dispatchSync(SetTokenAction(value: null));
    await pumpEventQueue();

    expect(storage.values.containsKey('token'), isFalse);
  });

  group('persistAcrossLifecycle', () {
    late AppLifecycleListener listener;

    void move(List<AppLifecycleState> states) {
      for (final state in states) {
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          state,
        );
      }
    }

    setUp(() => move([.resumed]));
    tearDown(() => listener.dispose());

    test('hiding the app saves what changed a moment ago', () async {
      final store = await storeFrom(AppState.initial());
      listener = persistAcrossLifecycle(store);

      store.dispatchSync(SetLanguageAction('uk'));
      await pumpEventQueue();
      expect(storage.values['locale'], 'en', reason: 'still throttled');

      move([.inactive, .hidden]);
      await pumpEventQueue();

      expect(storage.values['locale'], 'uk');
    });

    test('showing it again resumes saving', () async {
      // A PersistAction ignores the throttle but not a pause, so it is saved
      // here only if `onShow` resumed the persistor.
      final store = await storeFrom(AppState.initial());
      listener = persistAcrossLifecycle(store);
      move([.inactive, .hidden]);

      move([.inactive, .resumed]);
      store
        ..dispatchSync(SetLanguageAction('uk'))
        ..dispatchSync(PersistAction<AppState>());
      await pumpEventQueue();

      expect(storage.values['locale'], 'uk');
    });
  });
}
