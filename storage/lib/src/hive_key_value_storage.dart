import 'package:hive/hive.dart';

import 'key_value_storage.dart';

class HiveKeyValueStorageImpl extends KeyValueStorage {
  HiveKeyValueStorageImpl({
    required super.storageName,
  });

  Future<Box<dynamic>> get _box => Hive.openBox<dynamic>(storageName);

  @override
  Future<T?> get<T>(String key) async => (await _box).get(key) as T;

  @override
  Future<void> put<T>(String key, T? value) async =>
      (await _box).put(key, value);

  @override
  Future<void> clear() async => (await _box).clear();

  @override
  Future<void> delete(String key) async => (await _box).delete(key);
}
