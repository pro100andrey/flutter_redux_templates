import 'package:async_redux/async_redux.dart';
import 'package:storage/storage.dart';

import 'redux/app_state.dart';
import 'redux/services/connectivity/connectivity.dart';
import 'redux/services/connectivity/connectivity_dispatcher.dart';

/// Container for the app's injected services, one instance per [Store].
///
/// Wired via the store's `dependencies` factory, which receives the store — so
/// services that need to dispatch (like connectivity) are built here without a
/// circular dependency. Services are lazy (`late final`); [warmUp] runs the
/// async setup the synchronous factory can't do itself.
///
/// Access it from actions via the `deps` getter on the base `Action`.
class AppDependencies {
  AppDependencies(this._store, this.settings);

  final Store<AppState> _store;

  /// Storage backend, opened once in run_env and shared with the Persistor.
  ///
  /// Typed on the interface, not on `KeyValueStorage`: the concrete adapter
  /// reaches path_provider, so a consumer naming it cannot be built without a
  /// Flutter binding and a real file.
  final BaseKeyValueStorage settings;

  late final connectivity = ConnectivityService(
    listener: ConnectivityDispatcher(store: _store),
  );

  /// Runs the async service initialization. Call once, right after the store
  /// is created (see `run_env.dart`).
  Future<void> warmUp() async {
    await connectivity.start();
  }
}
