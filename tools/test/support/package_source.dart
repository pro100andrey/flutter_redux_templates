import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads a resolved dependency's source off disk, so a test can check frx's
/// transcription of a package against the package.
///
/// `tools/pubspec.yaml` depends on `analyzer`, `args`, `code_builder`,
/// `dart_style` and `path` — and deliberately nothing else, so its heavy
/// analyzer dependency stays out of the app's resolution. The consequence is
/// that **every fact frx knows about async_redux, auto_route or freezed is a
/// transcription**, and a test that asserts one against frx's own enum is
/// testing the transcription against itself. That is how the mixin catalogue
/// drifted five behind the package while the test named "guards against the
/// list drifting behind the package again" stayed green.
///
/// The library cannot import those packages. A test can read them.
abstract final class PackageSource {
  /// The `lib/` of [package] as resolved for the monorepo, or null when it is
  /// not resolved here.
  ///
  /// Null is the normal answer in a checkout where `flutter pub get` has not
  /// run, and in a standalone `dart install --source path tools`. Callers skip
  /// rather than fail — a test that cannot see the package has learned nothing,
  /// which is different from having learned that frx is wrong.
  static Directory? libOf(String package, {Directory? repoRoot}) {
    final config = _configFor(package, repoRoot ?? Directory.current);
    if (config == null) return null;

    final Map<String, Object?> json;
    try {
      json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    } on Object {
      return null;
    }
    for (final entry in (json['packages'] as List? ?? const [])) {
      final e = entry as Map<String, Object?>;
      if (e['name'] != package) continue;
      final root = Uri.parse(e['rootUri'] as String);
      // rootUri is relative to the .dart_tool directory when it is not absolute.
      final base = root.hasScheme
          ? root.toFilePath()
          : p.normalize(p.join(config.parent.path, root.toFilePath()));
      final dir = Directory(p.join(base, e['packageUri'] as String? ?? 'lib'));
      return dir.existsSync() ? dir : null;
    }
    return null;
  }

  /// Every `.dart` file under [dir], recursively.
  static Iterable<File> dartFiles(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  /// Walks up from [start] for a `.dart_tool/package_config.json` that resolves
  /// [package].
  ///
  /// It has to be the *right* config, not the nearest one: this monorepo
  /// resolves `tools` under `tools/.dart_tool/` and the Flutter packages at the
  /// repo root, and only the latter has ever heard of async_redux. Stopping at
  /// the first config found would always answer "not resolved".
  static File? _configFor(String package, Directory start) {
    for (var dir = start.absolute; ; dir = dir.parent) {
      final candidate = File(
        p.join(dir.path, '.dart_tool', 'package_config.json'),
      );
      if (candidate.existsSync() &&
          candidate.readAsStringSync().contains('"$package"')) {
        return candidate;
      }
      if (dir.parent.path == dir.path) return null;
    }
  }
}
