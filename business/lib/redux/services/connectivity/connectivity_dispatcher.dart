import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../connectivity/actions/set_connectivity_status_action.dart';
import 'connectivity.dart';

class ConnectivityDispatcher implements ConnectivityServiceListener {
  ConnectivityDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onStatusChange({required bool isAvailable}) {
    final previousState = SelectConnectivity(_store.state).isConnected;
    if (previousState != isAvailable) {
      _store.dispatchSync(SetConnectivityStatusAction(value: isAvailable));
    }
  }
}
