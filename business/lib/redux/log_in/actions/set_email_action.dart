import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetEmailAction extends ReduxAction<AppState> {
  SetEmailAction({
    required this.value,
  });

  final String value;

  @override
  AppState reduce() => state.copyWith.logIn(email: value);
}
