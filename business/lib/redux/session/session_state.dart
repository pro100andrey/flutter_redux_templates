import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_state.dart';

part 'session_state.freezed.dart';

@freezed
class SessionState with _$SessionState {
  const factory SessionState({
    String? token,
  }) = _SessionState;
}

extension type SessionGraph(AppState state) {
  /// Returns root graph
  AppStateGraph get root => AppStateGraph(state);

  /// Returns session token
  String? get token => state.session.token;

  /// Returns true if session is available
  bool get isAvailable => token != null;
}
