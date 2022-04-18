import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetConfirmPasswordAction extends ReduxAction<AppState> {
  SetConfirmPasswordAction(this.confirmPassword);

  final String confirmPassword;

  @override
  AppState reduce() =>
      state.copyWith.resetPassword(confirmPassword: confirmPassword);
}
