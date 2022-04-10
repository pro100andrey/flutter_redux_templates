import 'package:get_it/get_it.dart';

// ambient variable to access the service locator
final sl = GetIt.instance;

String service() => sl.get<String>();

Future<void> setup() async {
  sl.registerLazySingleton(() => 'Service allocator');
}
