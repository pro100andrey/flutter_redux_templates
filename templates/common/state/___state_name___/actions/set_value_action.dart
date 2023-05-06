import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetValueAction extends ReduxAction<AppState> {
  SetValueAction({required this.value});

  final String value;

  @override
  AppState reduce() => state.copyWith();
}
