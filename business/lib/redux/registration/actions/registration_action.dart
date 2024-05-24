import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../registration_state.dart';

class RegistrationAction extends ReduxAction<AppState> with WithWaitState {
  @override
  Future<AppState?> reduce() async {
    final graph = RegistrationGraph(state);

    await _signUpRequest(email: graph.email!, password: graph.password!);

    return state.copyWith(registration: const RegistrationState());
  }
}

Future<void> _signUpRequest({
  required String email,
  required String password,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
