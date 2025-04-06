import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetConnectivityStatusAction extends ReduxAction<AppState> {
  SetConnectivityStatusAction({required this.value});

  final bool value;

  @override
  AppState reduce() => state.copyWith.connectivity(isAvailable: value);
}
