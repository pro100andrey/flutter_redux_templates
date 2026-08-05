import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_with_email_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds an [AppState] and nothing else — which is the entire contract
/// [Selectors] asks for.
///
/// That one-member requirement is the facade's best property, and this class is
/// the proof: a reducer, a connector's `_Factory` and a test all satisfy it the
/// same way, so the selectors are exercised through exactly the surface
/// production code uses.
class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}

void main() {
  group('the facade reads through to its slice', () {
    test('every selector answers from AppState.initial()', () {
      final r = _Reader(AppState.initial());

      expect(r.connectivity.isConnected, isTrue);
      expect(r.login.email, isNull);
      expect(r.login.password, isNull);
      expect(r.registration.confirmPassword, isNull);
      expect(r.resetPassword.password, isNull);
      expect(r.forgotPassword.email, isNull);
      expect(r.session.token, isNull);
      expect(r.theme.mode, ThemeMode.light);
      expect(r.language.locale, 'en');
    });

    test('a written slice is what the selector returns', () {
      final r = _Reader(
        AppState.initial().copyWith
            .login(email: 'a@b.c', password: 'secret')
            .copyWith
            .session(token: 'tok'),
      );

      expect(r.login.email, 'a@b.c');
      expect(r.login.password, 'secret');
      expect(r.session.token, 'tok');
    });

    test('the four auth slices do not read each other', () {
      // They hold the same field names over the same types, so a selector
      // pointed at the wrong slice would still compile and still return a
      // String?. This is the test that would catch it.
      final r = _Reader(
        AppState.initial().copyWith.login(email: 'only-login@b.c'),
      );

      expect(r.login.email, 'only-login@b.c');
      expect(r.registration.email, isNull);
      expect(r.forgotPassword.email, isNull);
    });
  });

  group('SelectSession.isAvailable', () {
    test('is false without a token and true with one', () {
      expect(_Reader(AppState.initial()).session.isAvailable, isFalse);
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: 'tok'),
        ).session.isAvailable,
        isTrue,
      );
    });

    test('an empty string is a token — the check is null, not blank', () {
      // Pinning the rule rather than endorsing it: the router gates the whole
      // app on this (`_AuthGuard`), so if it should reject `''` the change
      // belongs here, where one test names it.
      expect(
        _Reader(
          AppState.initial().copyWith.session(token: ''),
        ).session.isAvailable,
        isTrue,
      );
    });
  });

  group('SelectComposites.canEnterApp', () {
    test('needs a token', () {
      expect(_Reader(AppState.initial()).canEnterApp, isFalse);
    });

    test('is true once a token is present and nothing is in flight', () {
      final r = _Reader(AppState.initial().copyWith.session(token: 'tok'));
      expect(r.canEnterApp, isTrue);
    });

    test('is false while the login action is in flight', () {
      // `isWaiting` is keyed on the action *type*, which is why the read layer
      // imports the write layer. Renaming the action silently changes what
      // this selector observes, so the pairing is worth a test.
      final waiting = AppState.initial().copyWith
          .session(token: 'tok')
          .copyWith(wait: Wait.empty.add(flag: LogInWithEmailAction()));

      expect(_Reader(waiting).login.isWaiting, isTrue);
      expect(_Reader(waiting).canEnterApp, isFalse);
    });
  });
}
