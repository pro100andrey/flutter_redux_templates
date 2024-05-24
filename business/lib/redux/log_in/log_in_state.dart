import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_state.dart';
import 'actions/log_in_with_email_action.dart';

part 'log_in_state.freezed.dart';

@freezed
class LogInState with _$LogInState {
  const factory LogInState({
    String? email,
    String? password,
  }) = _LogInState;
}

extension type LogInGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns email value
  String? get email => state.logIn.email;

  /// Returns password value
  String? get password => state.logIn.password;

  /// Returns waiting value
  bool get isWaiting => state.wait.isWaitingForType<LogInWithEmailAction>();

  /// Returns true login data is set
  bool get allDataIsSet =>
      (email ?? '').isNotEmpty && (password ?? '').isNotEmpty;
}
