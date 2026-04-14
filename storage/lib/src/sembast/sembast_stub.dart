import 'package:sembast/sembast.dart';

DatabaseFactory getDatabaseFactory({String? packageName, String? rootPath}) =>
    _stub('getDatabaseFactory(packageName: $packageName, rootPath: $rootPath)');

T _stub<T>(String message) {
  throw UnimplementedError(message);
}
