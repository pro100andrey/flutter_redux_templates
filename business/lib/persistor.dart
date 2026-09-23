import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:storage/storage.dart';

import 'redux/app_state.dart';
import 'redux/language/models/language_state.dart';
import 'redux/session/models/session_state.dart';
import 'redux/theme/models/theme_state.dart';

/// AsyncRedux [Persistor] backed by the `storage` package ([KeyValueStorage]).
///
/// The store calls [persistDifference] (throttled) after state changes and
/// [readState] once on boot. Only the persisted slice (theme, language, session
/// token) is stored — not the whole state.
class AppPersistor extends Persistor<AppState> {
  AppPersistor(this._storage);

  final BaseKeyValueStorage _storage;

  static final _logger = Logger('Persistor');

  static const _themeKey = 'themeMode';
  static const _localeKey = 'locale';
  static const _tokenKey = 'token';

  @override
  Duration? get throttle => const Duration(seconds: 1);

  /// Rebuilds the persisted slices, each on its own: a key that is missing *or*
  /// unreadable falls back to that slice's `AppState.initial()` value, and an
  /// unreadable one is deleted so the next boot does not trip on it again.
  ///
  /// Every value is checked rather than cast. This read runs before `runApp`,
  /// so a throw here is not an error dialog — it is an app that stops on every
  /// launch until the user clears its data. `ThemeMode.values[index]` did
  /// exactly that for an index from a build with more modes, and
  /// `get<int>` on a key that held a string threw a TypeError from inside the
  /// storage's `as T?`.
  @override
  Future<AppState?> readState() async {
    final mode = await _read(
      _themeKey,
      (v) => v is int && v >= 0 && v < ThemeMode.values.length
          ? ThemeMode.values[v]
          : null,
    );
    final locale = await _read(
      _localeKey,
      (v) => v is String && v.isNotEmpty ? v : null,
    );
    final token = await _read(_tokenKey, (v) => v is String ? v : null);

    if (mode == null && locale == null && token == null) {
      return null;
    }

    final initial = AppState.initial();

    return initial.copyWith(
      theme: ThemeState(mode: mode ?? initial.theme.mode),
      language: LanguageState(locale: locale ?? initial.language.locale),
      session: SessionState(token: token),
    );
  }

  /// The one place a stored value becomes a typed one. [decode] returns null
  /// for anything it does not accept; such a value is deleted and read as
  /// absent. Asks the storage for `Object`, never for the expected type — the
  /// storage casts to what it is asked for, and a wrong guess throws there,
  /// before [decode] could see the value.
  Future<T?> _read<T extends Object>(
    String key,
    T? Function(Object value) decode,
  ) async {
    final stored = await _storage.get<Object>(key);
    if (stored == null) {
      return null;
    }

    final value = decode(stored);
    if (value == null) {
      _logger.warning('Dropping unreadable persisted "$key": $stored');
      await _storage.delete(key);
    }

    return value;
  }

  @override
  Future<void> persistDifference({
    required AppState newState,
    AppState? lastPersistedState,
  }) async {
    if (lastPersistedState?.theme != newState.theme) {
      await _storage.put(_themeKey, newState.theme.mode.index);
    }

    if (lastPersistedState?.language != newState.language) {
      await _storage.put(_localeKey, newState.language.locale);
    }

    if (lastPersistedState?.session != newState.session) {
      final token = newState.session.token;
      await (token == null
          ? _storage.delete(_tokenKey)
          : _storage.put(_tokenKey, token));
    }
  }

  @override
  Future<void> deleteState() => Future.wait([
    _storage.delete(_themeKey),
    _storage.delete(_localeKey),
    _storage.delete(_tokenKey),
  ]);
}
