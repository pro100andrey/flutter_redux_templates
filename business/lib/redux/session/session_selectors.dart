import '../app_state.dart';

/// Returns session token
String? selectSessionToken(AppState state) => state.session.token;

// Returns true if session is available
bool selectIsSessionAvailable(AppState state) => state.session.token != null;
