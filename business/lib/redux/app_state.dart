import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/connectivity_state.dart';
import 'forgot_password/forgot_password_state.dart';
import 'log_in/log_in_state.dart';
import 'registration/registration_state.dart';
import 'reset_password/reset_password_state.dart';
import 'session/session_state.dart';

export 'common.dart';

part 'app_state.freezed.dart';

@freezed
class AppState with _$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LogInState logIn,
    required RegistrationState registration,
    required ForgotPasswordState forgotPassword,
    required ResetPasswordState resetPassword,
    required SessionState session,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
        connectivity: ConnectivityState(),
        logIn: LogInState(),
        registration: RegistrationState(),
        forgotPassword: ForgotPasswordState(),
        resetPassword: ResetPasswordState(),
        session: SessionState(),
        wait: Wait.empty,
      );
}
