import 'package:hive/hive.dart';

import 'hive_types.dart';

part 'biometric_data.g.dart';

@HiveType(typeId: HiveTypes.biometricData)
class BiometricData extends HiveObject {
  BiometricData({required this.email, required this.password});

  @HiveField(0)
  String email;

  @HiveField(1)
  String password;
}
