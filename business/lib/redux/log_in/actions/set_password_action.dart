import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetPasswordAction extends ReduxAction<AppState> {
  SetPasswordAction({required this.password});

  final String password;

  @override
  AppState reduce() => state.copyWith.logIn(password: password);
}
