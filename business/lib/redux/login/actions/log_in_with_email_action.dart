import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../session/models/session_state.dart';
import '../models/login_state.dart';

/// Exchanges the typed credentials for a session token.
///
/// One reduce writes both halves — the token in, the draft out — because they
/// are one change: a state where the user is logged in *and* the login form
/// still holds their password is one no screen should ever observe.
///
/// Writing `session.token` is what lets the user in. `run_env` hands auto_route
/// a `reevaluateListenable` over `session.token != null`, so the auth guard
/// re-runs the moment this returns and the router leaves the auth area by
/// itself — no navigation is dispatched here.
class LogInWithEmailAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    final token = await _logInWithEmailRequest(
      email: login.email!,
      password: login.password!,
    );

    return state.copyWith(
      session: SessionState(token: token),
      login: const LoginState(),
    );
  }
}

/// **Placeholder.** Returns a token after a delay instead of calling a server,
/// because this template ships no backend.
///
/// It fakes a success where the other three async actions throw
/// `UserException('Not implemented yet.')`, and the difference is deliberate:
/// this is the one request whose *state effect* the rest of the app is built
/// on. The auth guard, the `reevaluateListenable`, the persisted session and
/// every protected route are unreachable — and so undemonstrable and
/// untestable — until something writes a token. Registration and the two
/// password flows gate nothing, so their placeholders stay honest refusals.
///
/// Replace the body with a real call: `frx add-package http_client` and
/// `frx add-retrofit auth` scaffold the client, and the token then comes off
/// the response instead of from here.
Future<String> _logInWithEmailRequest({
  required String email,
  required String password,
}) async {
  // Call the server and return the token off its response. Until
  // this line goes, ANY email and password are accepted and the session is
  // real — the whole app downstream of a token behaves as if someone logged in.
  await Future<dynamic>.delayed(const Duration(seconds: 2));

  return 'placeholder-session-token';
}
