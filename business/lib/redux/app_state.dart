import 'package:async_redux/async_redux.dart';
import 'package:business/redux/connectivity/models/connectivity_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'log_in/models/log_in_state.dart';

part 'app_state.freezed.dart';

@freezed
class AppState with _$AppState {
  const factory AppState({
    @Default(Wait.empty) Wait wait,
    required ConnectivityState connectivity,
    required LogInState logIn,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    connectivity: ConnectivityState(),
    logIn: LogInState(),
  );
}
