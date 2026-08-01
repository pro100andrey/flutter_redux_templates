import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/models/connectivity_state.dart';
import 'forgot_password/models/forgot_password_state.dart';
import 'language/models/language_state.dart';
import 'login/models/login_state.dart';
import 'registration/models/registration_state.dart';
import 'reset_password/models/reset_password_state.dart';
import 'session/models/session_state.dart';
import 'theme/models/theme_state.dart';

export 'selectors.dart';

part 'app_state.freezed.dart';

@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LoginState login,
    required RegistrationState registration,
    required ForgotPasswordState forgotPassword,
    required ResetPasswordState resetPassword,
    required SessionState session,
    required ThemeState theme,
    required LanguageState language,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    connectivity: ConnectivityState(),
    login: LoginState(),
    registration: RegistrationState(),
    forgotPassword: ForgotPasswordState(),
    resetPassword: ResetPasswordState(),
    session: SessionState(),
    theme: ThemeState(),
    language: LanguageState(),
    wait: Wait.empty,
  );
}
