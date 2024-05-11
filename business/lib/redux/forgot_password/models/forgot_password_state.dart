import 'package:freezed_annotation/freezed_annotation.dart';

import '../../app_state.dart';

part 'forgot_password_state.freezed.dart';

@freezed
class ForgotPasswordState with _$ForgotPasswordState {
  const factory ForgotPasswordState({
    String? email,
  }) = _ForgotPasswordState;
}

enum ForgotPasswordWaiting {
  wait,
}

extension type ForgotPasswordGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns email value
  String? get email => state.forgotPassword.email;

  /// Returns waiting value
  bool get isWaiting => state.wait.isWaiting(ForgotPasswordWaiting.wait);
}
