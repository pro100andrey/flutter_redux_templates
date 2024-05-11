import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/models/connectivity_state.dart';
import 'forgot_password/models/forgot_password_state.dart';
import 'log_in/models/log_in_state.dart';
import 'registration/models/registration_state.dart';
import 'reset_password/models/reset_password_state.dart';
import 'session/models/session_state.dart';

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

extension type AppStateGraph(AppState state) {
  /// Returns connectivity graph
  ConnectivityGraph get connectivity => ConnectivityGraph(state);

  /// Returns log in graph
  LogInGraph get logIn => LogInGraph(state);

  /// Returns registration graph
  RegistrationGraph get registration => RegistrationGraph(state);

  /// Returns forgot password graph
  ForgotPasswordGraph get forgotPassword => ForgotPasswordGraph(state);
}

extension type BarrierGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns true if need to show barrier
  ///
  bool get needToShowBarrier =>
      root.logIn.isWaiting || root.registration.isWaiting;

  /// Returns true if need to show no internet connection
  bool get needToShowNoInternetConnection =>
      !root.connectivity.connectionIsAvailable;
}
