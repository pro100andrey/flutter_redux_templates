import 'package:async_redux/async_redux.dart';

import '../models/___state_name____state.dart';
import '../../app_state.dart';

class Retrieve___StateName___Action extends ReduxAction<AppState> {
  Retrieve___StateName___Action();

  @override
  void before() =>
      dispatch(WaitAction.add(___StateName___Waiting.wait, ref: this));

  @override
  void after() => dispatch(
        WaitAction.remove(___StateName___Waiting.wait, ref: this),
        notify: false,
      );

  @override
  Future<AppState?> reduce() {
    // await retrieve actions
    return Future.value(state);
  }
}
