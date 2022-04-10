import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetPasswordAction extends ReduxAction<AppState> {
  SetPasswordAction(this.password);

  final String password;

  @override
  AppState reduce() => state.copyWith.registration(
        password: password,
      );
}
