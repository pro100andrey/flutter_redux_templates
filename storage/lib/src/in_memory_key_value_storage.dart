import 'base_key_value_storage.dart';

/// [BaseKeyValueStorage] backed by a map — the adapter for anything that must
/// not touch a disk.
///
/// It is the second adapter, and that is its point: one implementation behind
/// an interface is a seam nobody can use. `KeyValueStorage` reaches
/// path_provider and a real sembast file, so a test, a preview, or a run
/// that should forget everything on exit had no way to build an
/// `AppPersistor` or a store at all.
///
/// Ships in `lib/` rather than in a test helper because the consumers that
/// need it — `AppPersistor`, `AppDependencies`, `newStore` — live in another
/// package.
final class InMemoryKeyValueStorage implements BaseKeyValueStorage {
  final _values = <String, Object?>{};

  /// What the storage currently holds, for a test to assert against without
  /// awaiting a [get] per key.
  Map<String, Object?> get values => Map.unmodifiable(_values);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<T?> get<T>(String key) async => _values[key] as T?;

  @override
  Future<void> put<T>(String key, T value) async {
    _values[key] = value;
  }
}
