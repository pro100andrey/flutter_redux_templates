import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';
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

  final KeyValueStorage _storage;

  static const _themeKey = 'themeMode';
  static const _localeKey = 'locale';
  static const _tokenKey = 'token';

  @override
  Duration? get throttle => const Duration(seconds: 1);

  @override
  Future<AppState?> readState() async {
    final themeIndex = await _storage.get<int>(_themeKey);
    final locale = await _storage.get<String>(_localeKey);
    final token = await _storage.get<String>(_tokenKey);

    if (themeIndex == null && locale == null && token == null) {
      return null;
    }

    return AppState.initial().copyWith(
      theme: ThemeState(
        mode: ThemeMode.values[themeIndex ?? ThemeMode.light.index],
      ),
      language: LanguageState(locale: locale ?? 'en'),
      session: SessionState(token: token),
    );
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
