import 'package:async_redux/async_redux.dart';
import 'package:get_it/get_it.dart';
import 'package:storage/storage.dart';

import 'environment.dart';
import 'redux/app_state.dart';
import 'redux/services/connectivity/connectivity.dart';
import 'redux/services/connectivity/connectivity_driver.dart';

// ambient variable to access the service locator
final _locator = GetIt.instance;

ConnectivityService get getConnectivity => _locator.get<ConnectivityService>();

Future<void> initLocator(Store<AppState> store, Environment env) async {
  await setupStorage();

  // Connectivity Service
  final connectivity = ConnectivityService(
    driver: ConnectivityDriver(store: store),
  );

  await connectivity.start();
  _locator.registerSingleton(connectivity);

  // Other services
  // ...
}
