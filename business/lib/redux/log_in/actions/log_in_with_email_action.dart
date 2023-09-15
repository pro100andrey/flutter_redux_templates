import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../log_in_selectors.dart';
import '../models/log_in_state.dart';

class LogInWithEmailAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(LogInWaiting.wait));

  @override
  void after() =>
      dispatchSync(WaitAction.remove(LogInWaiting.wait), notify: false);

  @override
  Future<AppState> reduce() async {
    // ignore: unused_local_variable
    final email = selectLogInEmail(state);
    // ignore: unused_local_variable
    final password = selectLogInPassword(state);
    // async login request ...
    await Future<dynamic>.delayed(const Duration(seconds: 2));

    return state.copyWith(logIn: const LogInState());
  }
}
