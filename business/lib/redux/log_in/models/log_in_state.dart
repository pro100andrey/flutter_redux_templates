import 'package:freezed_annotation/freezed_annotation.dart';

part 'log_in_state.freezed.dart';

@freezed
abstract class LogInState with _$LogInState {
  const factory LogInState({String? email, String? password}) = _LogInState;
}

enum LogInWaiting { wait }
