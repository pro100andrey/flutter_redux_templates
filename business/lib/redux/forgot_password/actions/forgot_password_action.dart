import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../forgot_password_selectors.dart';
import '../models/forgot_password_state.dart';

class ForgotPasswordAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(ForgotPasswordWaiting.wait));

  @override
  void after() => dispatchSync(WaitAction.remove(ForgotPasswordWaiting.wait));

  @override
  Future<AppState> reduce() async {
    final email = selectForgotPasswordEmail(state)!;

    await _forgotPasswordRequest(email: email);

    return state.copyWith(forgotPassword: const ForgotPasswordState());
  }
}

Future<void> _forgotPasswordRequest({
  required String email,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
