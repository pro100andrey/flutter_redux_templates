import 'package:async_redux/async_redux.dart';

import '../models/forgot_password_state.dart';
import '../../app_state.dart';

class ForgotPasswordAction extends ReduxAction<AppState> {
  ForgotPasswordAction({
    required this.value,
  });

  final String value;

  @override
  void before() => dispatch(WaitAction.add(ForgotPasswordWaiting.wait));

  @override
  void after() => dispatch(WaitAction.remove(ForgotPasswordWaiting.wait));

  @override
  AppState? reduce() => null;
}
