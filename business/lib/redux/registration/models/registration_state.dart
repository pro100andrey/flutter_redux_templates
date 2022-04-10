import 'package:freezed_annotation/freezed_annotation.dart';

part 'registration_state.freezed.dart';

@freezed
class RegistrationState with _$RegistrationState {
  const factory RegistrationState({
     String? email,
     String? password,
     String? confirmPassword,
  }) = _RegistrationState;
}

enum RegistrationWaiting {
  wait,
}
