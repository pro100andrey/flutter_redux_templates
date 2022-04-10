import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/models/connectivity_state.dart';
import 'log_in/models/log_in_state.dart';

part 'app_state.freezed.dart';

@freezed
class AppState with _$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LogInState logIn,
    @Default(Wait.empty) Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
        connectivity: ConnectivityState(),
        logIn: LogInState(),
      );
}
