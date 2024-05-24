import '../app_state.dart';
import '../connectivity/connectivity_state.dart';
import '../forgot_password/forgot_password_state.dart';
import '../log_in/log_in_state.dart';
import '../registration/registration_state.dart';
import '../reset_password/reset_password_state.dart';
import '../session/session_state.dart';

/// Mixin with all graphs

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

extension type AppStateGraph(AppState state) {
  ConnectivityGraph get connectivity => ConnectivityGraph(state);

  /// Returns log in graph
  LogInGraph get logIn => LogInGraph(state);

  /// Returns registration graph
  RegistrationGraph get registration => RegistrationGraph(state);

  /// Returns forgot password graph
  ForgotPasswordGraph get forgotPassword => ForgotPasswordGraph(state);

  /// Returns reset password graph
  ResetPasswordGraph get resetPassword => ResetPasswordGraph(state);

  /// Returns session graph
  SessionGraph get session => SessionGraph(state);

  /// Returns barrier graph
  BarrierGraph get barrier => BarrierGraph(state);
}
