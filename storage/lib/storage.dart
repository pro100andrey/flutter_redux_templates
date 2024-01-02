/// Storage library
library storage;

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'src/models/biometric_data.dart';

export 'src/hive_key_value_security_storage.dart';
export 'src/key_value_storage.dart';
export 'src/models/biometric_data.dart';
export 'src/security_storage.dart';

Future<void> setupStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  Hive
    ..init(dir.path)
    ..registerAdapter(BiometricDataAdapter());
}
