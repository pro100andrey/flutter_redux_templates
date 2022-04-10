import 'package:async_redux/async_redux.dart';

import '../models/___state_name____state.dart';
import '../../app_state.dart';

class ___StateName___Action extends ReduxAction<AppState> {
  ___StateName___Action({
    required this.value,
  });

  final String value;

  @override
  void before() => dispatch(WaitAction.add(___StateName___Waiting.wait));

  @override
  void after() => dispatch(WaitAction.remove(___StateName___Waiting.wait));

  @override
  AppState? reduce() => null;
}
