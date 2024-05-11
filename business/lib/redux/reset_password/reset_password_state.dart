import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_state.dart';

part 'reset_password_state.freezed.dart';

@freezed
class ResetPasswordState with _$ResetPasswordState {
  const factory ResetPasswordState({
    String? password,
    String? confirmPassword,
  }) = _ResetPasswordState;
}

enum ResetPasswordWaiting {
  wait,
}

extension type ResetPasswordGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns password value
  String? get password => state.resetPassword.password;

  /// Returns confirm password value
  String? get confirmPassword => state.resetPassword.confirmPassword;

  /// Returns waiting value
  bool get isWaiting => state.wait.isWaiting(ResetPasswordWaiting.wait);

  /// Returns true if email, password, confirmPassword is set
  bool get allDataIsSet =>
      (password ?? '').isNotEmpty && (confirmPassword ?? '').isNotEmpty;
}
