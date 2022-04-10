import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetEmailAction extends ReduxAction<AppState> {
  SetEmailAction(this.email);

  final String email;

  @override
  AppState reduce() => state.copyWith.registration(
        email: email,
      );
}
