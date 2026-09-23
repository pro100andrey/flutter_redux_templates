import 'package:sembast/sembast.dart';

import 'sembast.dart';

mixin SembastSetupMixin {
  Database? _db;

  Database get db {
    if (_db == null) {
      throw StateError('Database is not initialized. Call setupStorage first.');
    }
    return _db!;
  }

  StoreRef get mainStore => StoreRef.main();

  /// Opens [dbFile] where this platform keeps an app's private data.
  ///
  /// Holds no platform logic of its own: [databasePath] and [databaseFactory]
  /// come from `sembast.dart`, whose one conditional export picks the io or
  /// the web implementation of both. The platform test used to live here, as
  /// a second opinion that disagreed with the export under `--wasm`.
  Future<void> setupStorage({
    String dbFile = 'database.db',
    String? password,
  }) async {
    _db = await databaseFactory.openDatabase(
      await databasePath(dbFile),
      codec: password != null
          ? getEncryptSembastCodec(password: password)
          : null,
    );
  }
}
