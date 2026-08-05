import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/login/actions/log_in_with_email_action.dart';
import 'package:business/redux/login/actions/set_email_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/session/actions/set_token_action.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two slices nothing could reach: `session` had no writer a user could
/// trigger, and `language` had none at all. Both are what the app is gated on —
/// the auth guard reads the token, `MaterialApp.locale` reads the code — so
/// "the state exists and is persisted" was never the same as "it works".
void main() {
  Store<AppState> store([AppState? initial]) =>
      Store<AppState>(initialState: initial ?? AppState.initial());

  group('the session can be started and ended', () {
    test('logging in writes a token', () async {
      final s = store();
      await s.dispatchAndWait(SetEmailAction('a@b.c'));
      await s.dispatchAndWait(SetPasswordAction('Secret123'));

      await s.dispatchAndWait(LogInWithEmailAction());

      expect(s.state.session.token, isNotNull);
    });

    test('logging in clears the draft it read', () async {
      // One reduce writes both: a state that is logged in *and* still holding
      // the password is one no screen should observe.
      final s = store();
      await s.dispatchAndWait(SetEmailAction('a@b.c'));
      await s.dispatchAndWait(SetPasswordAction('Secret123'));

      await s.dispatchAndWait(LogInWithEmailAction());

      expect(s.state.login.email, isNull);
      expect(s.state.login.password, isNull);
    });

    test('SetTokenAction accepts null — that is what a log-out is', () async {
      // It took a non-nullable String, so a session could be started and never
      // ended: the token survived every attempt and came back from the
      // persistor on the next launch.
      final s = store(
        AppState.initial().copyWith.session(token: 'tok'),
      );

      await s.dispatchAndWait(SetTokenAction(value: null));

      expect(s.state.session.token, isNull);
    });

    test('the guard sees the flip in both directions', () async {
      // `canEnterApp` is what the auth area is decided on, and `run_env` feeds
      // the router a listenable over the same field.
      final s = store();
      expect(SelectSession(s.state).isAvailable, isFalse);

      await s.dispatchAndWait(SetTokenAction(value: 'tok'));
      expect(SelectSession(s.state).isAvailable, isTrue);

      await s.dispatchAndWait(SetTokenAction(value: null));
      expect(SelectSession(s.state).isAvailable, isFalse);
    });
  });

  group('the language can be changed', () {
    test('SetLanguageAction writes the locale code', () async {
      final s = store();
      expect(s.state.language.locale, 'en');

      await s.dispatchAndWait(SetLanguageAction('uk'));

      expect(s.state.language.locale, 'uk');
    });

    test('the code is what MaterialApp.locale reads', () async {
      // The plumbing from state to `MaterialApp` already existed — selector,
      // view-model, `locale: Locale(vm.locale)`. Only the dispatch was
      // missing, so the app restored a language it could not be told to
      // change. This asserts the whole path is one value.
      final s = store();
      await s.dispatchAndWait(SetLanguageAction('uk'));

      expect(SelectLanguage(s.state).locale, 'uk');
    });
  });
}
