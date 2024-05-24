import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../forgot_password_state.dart';

class ForgotPasswordAction extends ReduxAction<AppState> with WithWaitState {
  @override
  Future<AppState> reduce() async {
    final graph = ForgotPasswordGraph(state);
    await _forgotPasswordRequest(email: graph.email!);

    return state.copyWith(forgotPassword: const ForgotPasswordState());
  }
}

Future<void> _forgotPasswordRequest({
  required String email,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
