import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_state.dart';

part 'connectivity_state.freezed.dart';

@freezed
class ConnectivityState with _$ConnectivityState {
  const factory ConnectivityState({
    @Default(true) bool isAvailable,
  }) = _ConnectivityState;
}

extension type ConnectivityGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns true if connection is available
  bool get connectionIsAvailable => state.connectivity.isAvailable;
}
