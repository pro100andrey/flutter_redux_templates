import 'package:async_redux/async_redux.dart';
import 'package:get_it/get_it.dart';
import 'package:storage/key_value_storage.dart';

import 'redux/app_state.dart';

// ambient variable to access the service locator
final locator = GetIt.instance;

String service() => locator.get<String>();

Future<void> initLocator(Store<AppState> store) async {
  await initHiveStorage();

  locator.registerLazySingleton(() => 'Service allocator');
}
