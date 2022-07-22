import 'package:get_it/get_it.dart';

// ambient variable to access the service locator
final locator = GetIt.instance;

String service() => locator.get<String>();

Future<void> setup() async {
  locator.registerLazySingleton(() => 'Service allocator');
}
