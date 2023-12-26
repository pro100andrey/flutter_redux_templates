import '../app_state.dart';

/// Returns session token
String? selectSessionToken(AppState state) =>
    state.session.token;
