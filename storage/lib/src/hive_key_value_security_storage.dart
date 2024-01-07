import 'dart:convert';

import 'package:hive/hive.dart';

import 'key_value_storage.dart';

class KeyValueSecurityStorageImpl extends KeyValueStorage {
  KeyValueSecurityStorageImpl({
    required this.key,
    required super.storageName,
  });

  final String key;

  late final encryptionCipher = HiveAesCipher(base64Url.decode(key));

  Future<Box<dynamic>> get box => Hive.openBox<dynamic>(
        storageName,
        encryptionCipher: encryptionCipher,
      );

  @override
  Future<T?> get<T>(String key) async => (await box).get(key) as T;

  @override
  Future<void> put<T>(String key, T value) async => (await box).put(key, value);

  @override
  Future<void> clear() async => (await box).clear();

  @override
  Future<void> delete(String key) async => (await box).delete(key);
}
