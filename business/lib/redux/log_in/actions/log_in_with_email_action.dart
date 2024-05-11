import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../log_in_state.dart';

class LogInWithEmailAction extends ReduxAction<AppState> {
  @override
  void before() => dispatchSync(WaitAction.add(LogInWaiting.wait));

  @override
  void after() =>
      dispatchSync(WaitAction.remove(LogInWaiting.wait), notify: false);

  @override
  Future<AppState> reduce() async {
    final graph = LogInGraph(state);

    await _logInWithEmailRequest(
      email: graph.email!,
      password: graph.password!,
    );

    return state.copyWith(logIn: const LogInState());
  }
}

Future<void> _logInWithEmailRequest({
  required String email,
  required String password,
}) async {
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  throw const UserException('Not implemented yet.');
}
