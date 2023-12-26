import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../models/reset_password_state.dart';
import '../reset_password_selectors.dart';

class ResetPasswordAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(ResetPasswordWaiting.wait));

  @override
  void after() => dispatchSync(WaitAction.remove(ResetPasswordWaiting.wait));

  @override
  Future<AppState> reduce() async {
    final password = selectResetPasswordPassword(state)!;
    final confirmPassword = selectResetPasswordConfirmPassword(state)!;

    await _resetPasswordRequest(
      password: password,
      confirmPassword: confirmPassword,
    );

    return state.copyWith(resetPassword: const ResetPasswordState());
  }
}

Future<void> _resetPasswordRequest({
  required String password,
  required String confirmPassword,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
