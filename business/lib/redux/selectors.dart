import 'package:flutter/material.dart';

import 'app_state.dart';
import 'common/action.dart';
import 'forgot_password/actions/forgot_password_action.dart';
import 'login/actions/log_in_with_email_action.dart';
import 'registration/actions/registration_action.dart';
import 'reset_password/actions/reset_password_action.dart';

/// The facade: mix it in and every substate's selectors are in scope.
///
/// `Action` mixes it in, and so does every connector's `_Factory` — which is
/// the whole surface. A reducer reads `login.email`; nothing has to go through
/// a root type and a hop to get there.
mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectForgotPassword get forgotPassword => SelectForgotPassword(state);
  SelectLogin get login => SelectLogin(state);
  SelectRegistration get registration => SelectRegistration(state);
  SelectResetPassword get resetPassword => SelectResetPassword(state);
  SelectSession get session => SelectSession(state);
  SelectTheme get theme => SelectTheme(state);
  SelectLanguage get language => SelectLanguage(state);
}

/// Values that span substates. They belong on the facade rather than on any
/// one substate's selectors, which is what `on Selectors` says.
extension SelectComposites on Selectors {
  bool get canEnterApp => session.isAvailable && !login.isWaiting;

  /// Whether any foreground operation is in flight — what the modal barrier
  /// covers.
  ///
  /// **Folded off `Wait`, not named slice by slice.** The barrier read
  /// `login.isWaiting || registration.isWaiting`, and the two features written
  /// after that line showed no loading state at all: both mix in
  /// `WaitingAction`, both have an `isWaiting` getter, and neither was in the
  /// disjunction. A list of the slices that count is a list somebody has to
  /// remember, and it was already wrong.
  ///
  /// **Keyed on `BlockingAction`, which is a claim, not a side effect.** Two
  /// narrower predicates were tried and both were too wide. `isWaitingAny` is
  /// true for any flag in `Wait`, including ones that are not actions.
  /// `isWaitingForType<WaitingAction>()` looks narrower and is not: every async
  /// action that wants an indicator mixes in `WaitingAction`, because that is
  /// what puts it in `Wait` — so the first background refresh anyone adds would
  /// blank the app.
  ///
  /// `BlockingAction` is written on purpose and means only this. The set stays
  /// a fold rather than a list: `WaitAction.add(this)` files the action as the
  /// flag and `isWaitingForType<T>` tests `flag is T`, so the mixin answers for
  /// every action carrying it and nothing here names any of them.
  bool get isBusy => state.wait.isWaitingForType<BlockingAction>();
}

extension type SelectConnectivity(AppState _state) {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectForgotPassword(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<ForgotPasswordAction>();

  /// returns
  String? get email => _state.forgotPassword.email;
}

extension type SelectLogin(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();

  /// Returns email value
  String? get email => _state.login.email;

  /// Returns password value
  String? get password => _state.login.password;
}

extension type SelectRegistration(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RegistrationAction>();

  /// Returns email value
  String? get email => _state.registration.email;

  /// Returns password value
  String? get password => _state.registration.password;

  /// Returns confirm password value
  String? get confirmPassword => _state.registration.confirmPassword;
}

extension type SelectResetPassword(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<ResetPasswordAction>();

  /// Returns password value
  String? get password => _state.resetPassword.password;

  /// Returns confirm password value
  String? get confirmPassword => _state.resetPassword.confirmPassword;
}

extension type SelectSession(AppState _state) {
  /// Returns session token
  String? get token => _state.session.token;

  /// Returns true if session is available
  bool get isAvailable => token != null;
}

extension type SelectTheme(AppState _state) {
  /// Returns the selected theme mode
  ThemeMode get mode => _state.theme.mode;
}

extension type SelectLanguage(AppState _state) {
  /// Returns the selected locale code (e.g. `en`)
  String get locale => _state.language.locale;
}
