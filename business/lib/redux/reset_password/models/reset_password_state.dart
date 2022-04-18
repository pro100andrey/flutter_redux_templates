import 'package:freezed_annotation/freezed_annotation.dart';

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
