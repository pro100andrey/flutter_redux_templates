import '../../app_state.dart';
import '../../common/action.dart';

/// Sets or clears the session token — the one field the whole app is gated on.
///
/// `value` is nullable, and that is the point: null is a log-out. It used to be
/// a plain `String`, so the action could only ever put a session *in*, and the
/// app had no way to end one. Every other field setter in this template takes a
/// nullable value for the same reason.
///
/// Writing it re-runs the auth guard — `run_env` hands auto_route a
/// `reevaluateListenable` over `session.token != null` — so this action is also
/// what bounces the user between the auth area and the app.
class SetTokenAction extends Action {
  SetTokenAction({required this.value});

  final String? value;

  @override
  AppState reduce() => state.copyWith.session(token: value);
}
