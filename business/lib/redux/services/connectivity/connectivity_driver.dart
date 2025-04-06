import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../connectivity/actions/set_connectivity_status_action.dart';
import '../../connectivity/connectivity_selectors.dart';
import 'connectivity.dart';

class ConnectivityDriver implements ConnectivityServiceDriverInterface {
  ConnectivityDriver({required Store<AppState> store}) : _store = store;

  final Store<AppState> _store;

  @override
  void onStatusChange({required bool isAvailable}) {
    final previousState = selectNetworkConnectionIsAvailable(_store.state);
    if (previousState != isAvailable) {
      _store.dispatchSync(SetConnectivityStatusAction(value: isAvailable));
    }
  }
}
