import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../models/reset_password_state.dart';

class ResetPasswordAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(ResetPasswordWaiting.wait));

  @override
  void after() => dispatchSync(WaitAction.remove(ResetPasswordWaiting.wait));

  @override
  AppState? reduce() => null;
}
