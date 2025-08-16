import 'package:sembast/sembast.dart';

import 'base_key_value_storage.dart';
import 'sembast/sembast_setup_mixin.dart';

final class KeyValueStorage extends BaseKeyValueStorage with SembastSetupMixin {
  @override
  Future<void> clear() async => mainStore.delete(db);

  @override
  Future<void> delete(String key) async {
    await mainStore.record(key).delete(db);
  }

  @override
  Future<T?> get<T>(String key) async =>
      await mainStore.record(key).get(db) as T?;

  @override
  Future<void> put<T>(String key, T value) async =>
      mainStore.record(key).put(db, value);
}
