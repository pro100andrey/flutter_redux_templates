import '../app_state.dart';

/// returns waiting value
bool selectNetworkConnectionIsAvailable(AppState state) =>
    state.connectivity.isAvailable;
