import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// A file on disk, through sembast's io factory.
DatabaseFactory get databaseFactory => databaseFactoryIo;

/// The application **support** directory — private to this app on every
/// platform, and not somewhere the user browses.
///
/// It was the *documents* directory, which on Linux is XDG `~/Documents` and
/// on Windows the user's own Documents folder: not app-specific at all. Every
/// app generated from this template wrote its session token and settings to
/// the same `~/Documents/settings.db`, in plain text, and overwrote the
/// others'. The support directory is namespaced by the application id
/// (`~/.local/share/<id>` on Linux, `%APPDATA%\<company>\<product>` on
/// Windows, the app's own container on mobile and macOS).
Future<String> databasePath(String dbFile) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);

  return p.join(dir.path, dbFile);
}
