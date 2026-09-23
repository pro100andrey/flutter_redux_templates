import 'package:sembast/sembast.dart';

DatabaseFactory get databaseFactory => _stub('databaseFactory');

Future<String> databasePath(String dbFile) => _stub('databasePath($dbFile)');

Never _stub(String member) => throw UnimplementedError(
  '$member: no sembast backend for this platform — it has neither '
  'dart:io nor dart:js_interop.',
);
