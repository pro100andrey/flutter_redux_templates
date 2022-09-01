import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../models/registration_state.dart';

class RegistrationAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(RegistrationWaiting.wait));

  @override
  void after() => dispatchSync(WaitAction.remove(RegistrationWaiting.wait));

  @override
  AppState? reduce() => null;
}
