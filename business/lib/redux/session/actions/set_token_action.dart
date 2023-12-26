import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetTokenAction extends ReduxAction<AppState> {
  SetTokenAction({required this.value});

  final String value;

  @override
  AppState reduce() => state.copyWith.session(token: value);
}
