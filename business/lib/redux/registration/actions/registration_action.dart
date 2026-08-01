import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/registration_state.dart';

class RegistrationAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _signUpRequest(
      email: registration.email!,
      password: registration.password!,
    );

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
