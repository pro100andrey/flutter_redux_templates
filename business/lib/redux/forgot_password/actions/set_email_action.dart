import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetEmailAction extends ReduxAction<AppState> {
  SetEmailAction({required this.email});

  final String email;

  @override
  AppState reduce() => state.copyWith.forgotPassword(email: email);
}
