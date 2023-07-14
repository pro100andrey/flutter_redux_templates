import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '___service_name___.dart';

class ___ServiceName___Driver implements ___ServiceName___ServiceDriverInterface {
 ___ServiceName___Driver({required Store<AppState> store}) : _store = store;

  final Store<AppState> _store;

  @override
  void onDispose() {
    // TODO: implement onDispose
  }

  @override
  void onStatusChange() {
    // TODO: implement onStatusChange
  }
}
