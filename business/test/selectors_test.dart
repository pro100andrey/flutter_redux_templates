import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/forgot_password/actions/forgot_password_action.dart';
import 'package:business/redux/login/actions/log_in_with_email_action.dart';
import 'package:business/redux/registration/actions/registration_action.dart';
import 'package:business/redux/reset_password/actions/reset_password_action.dart';
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

  group('SelectComposites.isBusy', () {
    test('is false when nothing is in flight', () {
      expect(_Reader(AppState.initial()).isBusy, isFalse);
    });

    test('every waiting action raises it', () {
      // Named one by one rather than folded, because *which* actions count is
      // the claim. The barrier read `login.isWaiting || registration.isWaiting`
      // and the last two are the ones that were missing from it — they mix in
      // `WaitingAction` and have an `isWaiting` getter, and still showed the
      // user nothing for the two seconds they ran.
      for (final action in <ReduxAction<AppState>>[
        LogInWithEmailAction(),
        RegistrationAction(),
        ForgotPasswordAction(),
        ResetPasswordAction(),
      ]) {
        final r = _Reader(
          AppState.initial().copyWith(wait: Wait.empty.add(flag: action)),
        );
        expect(
          r.isBusy,
          isTrue,
          reason: '${action.runtimeType} should raise the barrier',
        );
      }
    });

    test('an action written later raises it with no edit here', () {
      // The property a list of slices cannot have: membership is the mixin, so
      // nothing has to be told about a new action.
      final r = _Reader(
        AppState.initial().copyWith(wait: Wait.empty.add(flag: _LaterAction())),
      );

      expect(r.isBusy, isTrue);
    });

    test('an action that waits without the mixin leaves the screen', () {
      // The reason this is `isWaitingForType<WaitingAction>()` rather than
      // `isWaitingAny`. A background refresh, a poll or a paginating load may
      // each sit in `Wait` to drive an indicator of its own, and none of them
      // should blank the app. Consent is the mixin.
      final r = _Reader(
        AppState.initial().copyWith(
          wait: Wait.empty.add(flag: _BackgroundAction()),
        ),
      );

      expect(r.isBusy, isFalse);
    });

    test('a flag that is not an action at all does not either', () {
      // `Wait` takes any `Object?` as a flag, so `isWaitingAny` was true for
      // things that are not operations the user is waiting on.
      final r = _Reader(
        AppState.initial().copyWith(wait: Wait.empty.add(flag: 'some-flag')),
      );

      expect(r.isBusy, isFalse);
    });
  });
}

/// Stands in for an action written after this test that opts into the barrier —
/// the case the hand-listed disjunction could not cover.
class _LaterAction extends ReduxAction<AppState> with WaitingAction {
  @override
  AppState? reduce() => null;
}

/// Waits, and does not ask to be covered.
class _BackgroundAction extends ReduxAction<AppState> {
  @override
  AppState? reduce() => null;
}
