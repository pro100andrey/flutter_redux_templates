import 'package:business/persistor.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

/// [AppPersistor] is the one module here that can silently lose a user's data,
/// and until `storage` exported its interface there was no way to run it: the
/// only adapter reached path_provider and a real file.
///
/// `InMemoryKeyValueStorage` is why this file exists. It is the second adapter
/// the seam was always shaped for.
void main() {
  late InMemoryKeyValueStorage storage;
  late AppPersistor persistor;

  setUp(() {
    storage = InMemoryKeyValueStorage();
    persistor = AppPersistor(storage);
  });

  group('readState', () {
    test(
      'an empty storage means no persisted state, not a default one',
      () =>
          // The distinction matters at boot: `createStore` falls back to
          // `AppState.initial()` on null. Returning a state here instead would
          // make the two paths indistinguishable.
          expectLater(persistor.readState(), completion(isNull)),
    );

    test('restores the three persisted slices', () async {
      await storage.put('themeMode', ThemeMode.dark.index);
      await storage.put('locale', 'uk');
      await storage.put('token', 'tok');

      final state = await persistor.readState();

      expect(state?.theme.mode, ThemeMode.dark);
      expect(state?.language.locale, 'uk');
      expect(state?.session.token, 'tok');
    });

    test('one persisted key is enough to rebuild a state', () async {
      await storage.put('locale', 'uk');

      final state = await persistor.readState();

      expect(state, isNotNull);
      expect(state?.language.locale, 'uk');
      expect(state?.theme.mode, ThemeMode.light, reason: 'falls back');
      expect(state?.session.token, isNull);
    });
  });

  group('persistDifference', () {
    test('writes every slice on the first pass', () async {
      await persistor.persistDifference(
        newState: AppState.initial(),
      );

      expect(storage.values.keys, containsAll(['themeMode', 'locale']));
    });

    test('writes nothing when nothing changed', () async {
      final state = AppState.initial().copyWith.session(token: 'tok');
      await persistor.persistDifference(
        newState: state,
      );
      await storage.clear();

      await persistor.persistDifference(
        newState: state,
        lastPersistedState: state,
      );

      expect(storage.values, isEmpty);
    });

    test('writes only the slice that changed', () async {
      final before = AppState.initial();
      await storage.clear();

      await persistor.persistDifference(
        newState: before.copyWith.language(locale: 'uk'),
        lastPersistedState: before,
      );

      expect(storage.values.keys, ['locale']);
    });

    test('a cleared token is deleted, not written as null', () async {
      // The one asymmetric branch in the file. Writing null would leave a key
      // whose presence says "there is a session" to `readState`, which checks
      // for null keys to decide whether any state was persisted at all.
      await storage.put('token', 'tok');
      final before = AppState.initial().copyWith.session(token: 'tok');

      await persistor.persistDifference(
        newState: before.copyWith.session(token: null),
        lastPersistedState: before,
      );

      expect(storage.values.containsKey('token'), isFalse);
    });

    test('logging out and back in round-trips through readState', () async {
      final loggedIn = AppState.initial().copyWith.session(token: 'tok');
      await persistor.persistDifference(
        newState: loggedIn,
      );
      await persistor.persistDifference(
        newState: loggedIn.copyWith.session(token: null),
        lastPersistedState: loggedIn,
      );

      expect((await persistor.readState())?.session.token, isNull);
    });
  });

  group('deleteState', () {
    test('removes all three keys', () async {
      await storage.put('themeMode', 1);
      await storage.put('locale', 'uk');
      await storage.put('token', 'tok');

      await persistor.deleteState();

      expect(storage.values, isEmpty);
    });
  });
}
