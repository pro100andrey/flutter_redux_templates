import 'package:sembast_web/sembast_web.dart';

/// IndexedDB, through sembast_web.
DatabaseFactory get databaseFactory => databaseFactoryWeb;

/// On the web a "path" is the IndexedDB database's name, and the browser
/// already keeps one set per origin — so the file name is the whole answer.
///
/// It is the name as given, not a fixed one: every storage used to open
/// `/assets/db` here, whatever `dbFile` it asked for, so two storages on the
/// web were one database with two owners.
Future<String> databasePath(String dbFile) async => dbFile;
