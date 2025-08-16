import 'package:sembast/sembast_io.dart';

/// Use app data on linux and windows if rootPath is null
///
/// Throw if no path defined
DatabaseFactory getDatabaseFactory({String? packageName, String? rootPath}) =>
    databaseFactoryIo;
