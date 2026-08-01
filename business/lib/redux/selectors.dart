import 'package:flutter/material.dart';

import 'app_state.dart';
import 'forgot_password/actions/forgot_password_action.dart';
import 'login/actions/log_in_with_email_action.dart';
import 'registration/actions/registration_action.dart';
import 'reset_password/actions/reset_password_action.dart';

extension type const Selector(AppState _state) {
  Select get select => Select(_state);
}

extension type Select(AppState _state) implements Selector {
  SelectConnectivity get connectivity => SelectConnectivity(_state);
  SelectForgotPassword get forgotPassword => SelectForgotPassword(_state);
  SelectLogin get login => SelectLogin(_state);
  SelectRegistration get registration => SelectRegistration(_state);
  SelectResetPassword get resetPassword => SelectResetPassword(_state);
  SelectSession get session => SelectSession(_state);
  SelectTheme get theme => SelectTheme(_state);
  SelectLanguage get language => SelectLanguage(_state);
}

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

extension SelectComposites on Select {
  bool get canEnterApp => session.isAvailable && !login.isWaiting;
}

extension type SelectConnectivity(AppState _state) implements Selector {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectForgotPassword(AppState _state) implements Selector {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<ForgotPasswordAction>();

  /// returns
  String? get email => _state.forgotPassword.email;
}

extension type SelectLogin(AppState _state) implements Selector {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();

  /// Returns email value
  String? get email => _state.login.email;

  /// Returns password value
  String? get password => _state.login.password;
}

extension type SelectRegistration(AppState _state) implements Selector {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RegistrationAction>();

  /// Returns email value
  String? get email => _state.registration.email;

  /// Returns password value
  String? get password => _state.registration.password;

  /// Returns confirm password value
  String? get confirmPassword => _state.registration.confirmPassword;
}

extension type SelectResetPassword(AppState _state) implements Selector {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<ResetPasswordAction>();

  /// Returns password value
  String? get password => _state.resetPassword.password;

  /// Returns confirm password value
  String? get confirmPassword => _state.resetPassword.confirmPassword;
}

extension type SelectSession(AppState _state) implements Selector {
  /// Returns session token
  String? get token => _state.session.token;

  /// Returns true if session is available
  bool get isAvailable => token != null;
}

extension type SelectTheme(AppState _state) implements Selector {
  /// Returns the selected theme mode
  ThemeMode get mode => _state.theme.mode;
}

extension type SelectLanguage(AppState _state) implements Selector {
  /// Returns the selected locale code (e.g. `en`)
  String get locale => _state.language.locale;
}
