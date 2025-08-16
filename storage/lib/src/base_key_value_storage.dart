abstract class BaseKeyValueStorage {
  const BaseKeyValueStorage();

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
