import '../app_state.dart';
import 'models/___stateName____state.dart';

/// returns waiting value
bool select___StateName___IsWaiting(AppState state) =>
    state.wait.isWaitingFor(___StateName___Waiting.wait);
