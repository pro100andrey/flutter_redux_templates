import '../app_state.dart';
import 'models/reset_password_state.dart';

/// returns waiting value
bool selectResetPasswordIsWaiting(AppState state) =>
    state.wait.isWaitingFor(ResetPasswordWaiting.wait);

/// Returns password value
String? selectResetPasswordPassword(AppState state) =>
    state.resetPassword.password;

/// Returns confirm password value
String? selectResetPasswordConfirmPassword(AppState state) =>
    state.resetPassword.confirmPassword;

/// Returns true if email, password, confirmPassword is setted
bool selectResetPasswordDataIsSet(AppState state) {
  final password = selectResetPasswordPassword(state) ?? '';
  final confirmPassword = selectResetPasswordConfirmPassword(state) ?? '';

  return password.isNotEmpty && confirmPassword.isNotEmpty;
}
