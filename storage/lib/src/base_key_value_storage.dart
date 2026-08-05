/// The contract every storage backend satisfies — and the type consumers name.
///
/// `interface` and not a plain abstract class: it declares no behaviour, so
/// there is nothing to inherit, and an implementer that forgets a member should
/// hear about it from the compiler rather than from an inherited stub.
///
/// Two adapters satisfy it — `KeyValueStorage` on sembast for the app, and
/// `InMemoryKeyValueStorage` for anything that must not touch a disk. Hold this
/// type, not either of them: `KeyValueStorage` pulls in path_provider, which is
/// a Flutter plugin, so a consumer typed on it cannot be exercised without a
/// binding and a real file.
abstract interface class BaseKeyValueStorage {
  ///
  /// Reads a value from the storage.
  ///
  ///
  /// [key] - The key of the value to read.
  ///
  /// Returns: The value stored, or null if not found.
  ///
  Future<T?> get<T>(String key);

  ///
  /// Writes a value to the storage.
  ///
  ///
  /// [key] - The key of the value to write.
  ///
  /// [value] - The value to write.
  ///
  Future<void> put<T>(String key, T value);

  ///
  /// Deletes a value from the storage.
  ///
  ///
  /// [key] - The key of the value to delete.
  ///
  Future<void> delete(String key);

  ///
  /// Clears all values from the storage.
  ///
  Future<void> clear();
}
