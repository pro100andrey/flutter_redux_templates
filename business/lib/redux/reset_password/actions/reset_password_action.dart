import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../reset_password_state.dart';

class ResetPasswordAction extends ReduxAction<AppState> with WithWaitState {
  @override
  Future<AppState> reduce() async {
    final graph = ResetPasswordGraph(state);

    await _resetPasswordRequest(
      password: graph.password!,
      confirmPassword: graph.confirmPassword!,
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
