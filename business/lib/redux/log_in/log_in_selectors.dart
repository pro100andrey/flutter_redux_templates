import '../../redux/app_state.dart';
import 'models/waiting.dart';

/// Returns waiting value
bool selectLogInWaiting(AppState state) =>
    state.wait.isWaitingFor(LogInWarning.wait);

/// Returns email value
String? selectLogInEmail(AppState state) => state.logIn.email;

/// Returns password value
String? selectLogInPassword(AppState state) => state.logIn.password;
