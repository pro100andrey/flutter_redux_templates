import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';

class SetQueryAction extends ReduxAction<AppState> {
  SetQueryAction({required this.query});

  final String query;

  @override
  AppState reduce() => state.copyWith();
}
