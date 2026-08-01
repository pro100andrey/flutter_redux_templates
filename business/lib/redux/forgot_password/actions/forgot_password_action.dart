import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../models/forgot_password_state.dart';

class ForgotPasswordAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _forgotPasswordRequest(email: forgotPassword.email!);

    return state.copyWith(forgotPassword: const ForgotPasswordState());
  }
}

Future<void> _forgotPasswordRequest({required String email}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
