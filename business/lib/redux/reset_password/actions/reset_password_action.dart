import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/reset_password_state.dart';

class ResetPasswordAction extends Action with WaitingAction, BlockingAction {
  @override
  Future<AppState> reduce() async {
    await _resetPasswordRequest(
      password: resetPassword.password!,
      confirmPassword: resetPassword.confirmPassword!,
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
