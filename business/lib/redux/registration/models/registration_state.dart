import 'package:freezed_annotation/freezed_annotation.dart';

import '../../app_state.dart';

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

extension type RegistrationGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns email value
  String? get email => state.registration.email;

  /// Returns password value
  String? get password => state.registration.password;

  /// Returns confirm password value
  String? get confirmPassword => state.registration.confirmPassword;

  /// Returns waiting value
  bool get isWaiting => state.wait.isWaiting(RegistrationWaiting.wait);

  /// Returns true if email, password, confirmPassword is set
  bool get allDataIsSet =>
      (email ?? '').isNotEmpty &&
      (password ?? '').isNotEmpty &&
      (confirmPassword ?? '').isNotEmpty;
}
