import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../models/registration_state.dart';
import '../registration_selectors.dart';

class RegistrationAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(RegistrationWaiting.wait));

  @override
  void after() => dispatchSync(WaitAction.remove(RegistrationWaiting.wait));

  @override
  Future<AppState?> reduce() async {
    // ignore: unused_local_variable
    final email = selectRegistrationEmail(state)!;
    // ignore: unused_local_variable
    final password = selectRegistrationPassword(state)!;
    // async registration request ...
    await Future<dynamic>.delayed(const Duration(seconds: 2));

    return state.copyWith(registration: const RegistrationState());
  }
}
