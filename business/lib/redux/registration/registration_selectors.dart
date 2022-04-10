import '../app_state.dart';
import 'models/registration_state.dart';

/// returns waiting value
bool selectRegistrationIsWaiting(AppState state) =>
    state.wait.isWaitingFor(RegistrationWaiting.wait);
