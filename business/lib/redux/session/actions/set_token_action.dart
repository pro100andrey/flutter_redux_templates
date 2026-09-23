import '../../../persistor.dart';
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

  /// Saves the new token now, not when the persistor's throttle next allows.
  ///
  /// `AppPersistor` batches writes into one a second, which is right for a
  /// theme toggle and wrong here: a user who logged out and closed the app
  /// within that second came back logged in, because the write that removed
  /// the token never ran. `after()` runs once the token is in the state, so
  /// [PersistNow.persistNow] here writes the state this action produced.
  /// Leaving the app is covered separately, in `run_env`, by
  /// `persistAcrossLifecycle`.
  @override
  void after() {
    super.after();
    store.persistNow();
  }
}
