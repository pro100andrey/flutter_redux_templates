import 'package:sembast/sembast.dart';

import 'base_key_value_storage.dart';
import 'sembast/sembast_setup_mixin.dart';

/// Sembast-backed storage — the adapter the app runs on.
///
/// `implements` rather than `extends`: [BaseKeyValueStorage] is an interface
/// with no behaviour to inherit. Stays `final` because the sembast wiring below
/// is not something to subclass; vary the backend by writing another adapter,
/// not by extending this one.
///
/// Requires [SembastSetupMixin.setupStorage] before any access — and that
/// reaches path_provider, so this type cannot be used without a Flutter
/// binding. See `InMemoryKeyValueStorage` for the one that can.
final class KeyValueStorage
    with SembastSetupMixin
    implements BaseKeyValueStorage {
  @override
  Future<void> clear() => mainStore.delete(db);

  @override
  Future<void> delete(String key) async {
    await mainStore.record(key).delete(db);
  }

  @override
  Future<T?> get<T>(String key) async =>
      await mainStore.record(key).get(db) as T?;

  @override
  Future<void> put<T>(String key, T value) =>
      mainStore.record(key).put(db, value);
}
