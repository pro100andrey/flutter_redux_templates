import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:storage/storage.dart';

/// Answers each path_provider question with its own directory under [root],
/// so a test can tell *which* one the storage asked for. Over the plugin's
/// method channel, which is what `flutter test` reaches: no platform
/// implementation is registered there.
void _answerPathsUnder(Directory root) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => switch (call.method) {
          'getApplicationSupportDirectory' => p.join(root.path, 'support'),
          'getApplicationDocumentsDirectory' => p.join(root.path, 'documents'),
          _ => null,
        },
      );
}

/// `KeyValueStorage` holds the session token. Where its file lands decides who
/// else can read or overwrite it, and that was the user's shared Documents
/// folder on Linux and Windows — one `settings.db` for every app generated
/// from this template.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('storage_test');
    _answerPathsUnder(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the database is opened in the application support directory', () async {
    final storage = KeyValueStorage();
    await storage.setupStorage(dbFile: 'settings.db');
    await storage.put('token', 'tok');

    expect(
      File(p.join(root.path, 'support', 'settings.db')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(root.path, 'documents')).existsSync(), isFalse);
  });

  test('a value survives reopening the same file', () async {
    final first = KeyValueStorage();
    await first.setupStorage(dbFile: 'settings.db');
    await first.put('locale', 'uk');
    await first.db.close();

    final second = KeyValueStorage();
    await second.setupStorage(dbFile: 'settings.db');

    expect(await second.get<String>('locale'), 'uk');
  });
}
