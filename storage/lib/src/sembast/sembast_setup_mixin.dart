import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

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

  Future<void> setupStorage({
    String dbFile = 'database.db',
    String? password,
  }) async {
    final getPath = () async {
      // ignore: do_not_use_environment
      const isWeb = bool.fromEnvironment('dart.library.js_util');

      if (!isWeb) {
        final dir = await getApplicationDocumentsDirectory();
        await dir.create(recursive: true);
        final dbPath = p.join(dir.path, dbFile);

        return dbPath;
      }

      return '/assets/db';
    }();

    final dbPath = await getPath;

    final dbFactory = getDatabaseFactory();

    _db = await dbFactory.openDatabase(
      dbPath,
      codec: password != null
          ? getEncryptSembastCodec(password: password)
          : null,
    );
  }
}
