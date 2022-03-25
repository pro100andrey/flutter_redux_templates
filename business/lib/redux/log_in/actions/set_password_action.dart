import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetPasswordAction extends ReduxAction<AppState> {
  SetPasswordAction({
    required this.value,
  });

  final String value;

  @override
  AppState reduce() => state.copyWith.logIn(password: value);
}
