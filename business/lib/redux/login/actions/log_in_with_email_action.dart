import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/login_state.dart';

class LogInWithEmailAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _logInWithEmailRequest(
      email: login.email!,
      password: login.password!,
    );

    return state.copyWith(login: const LoginState());
  }
}

Future<void> _logInWithEmailRequest({
  required String email,
  required String password,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
