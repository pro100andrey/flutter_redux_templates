/// Where an import URI points on disk, without the analyzer's resolver.
///
/// Three schemes, three answers. A relative URI is a path from the importing
/// file; a `package:` one goes through the nearest `package_config.json`; a
/// `dart:` one through whichever of the two SDK maps this project has. Each
/// map is read at most once per resolver, and only when a URI of its kind is
/// asked about — the common case is a file whose imports are all relative or
/// all within the workspace, and it should not pay for reading the SDK's
/// library table.
///
/// Every failure is null, never an exception: a URI in a scheme this cannot
/// read, a package outside the config, a map that will not parse. The caller
/// treats null as "unknown", and unknown is the answer that keeps an import.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class LibraryResolver {
  LibraryResolver(this.dir);

  /// The directory of the file whose imports are being judged: where a
  /// relative URI starts from, and where the walk up to `package_config.json`
  /// begins.
  final String dir;

  Map<String, String>? _packages;
  var _readPackages = false;
  Map<String, String>? _embedded;
  var _readSdk = false;

  /// The file [uri] names, read from [from].
  File? resolve(String uri, String from) {
    if (uri.startsWith('dart:')) {
      return _sdk(uri);
    }

    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash <= 0) {
        return null;
      }
      final lib = _packageLib(rest.substring(0, slash));
      return lib == null ? null : File(p.join(lib, rest.substring(slash + 1)));
    }

    if (uri.contains(':')) {
      return null; // some other scheme
    }

    return File(p.normalize(p.join(from, uri)));
  }

  /// The source of a `dart:` library.
  ///
  /// Reached because packages re-export them — `serverpod_auth_core_client`
  /// hands on `dart:collection`, `flutter/painting.dart` hands on `dart:ui` —
  /// and a re-export that could not be read made the whole answer unknown.
  /// Which meant the pass could prune a relative import and never a package
  /// one, since every package worth importing reaches the SDK somewhere.
  ///
  /// Two files hold the mapping and a project has exactly one of them: a
  /// Flutter project resolves `dart:ui` and the rest through `sky_engine`'s
  /// embedder file, a plain Dart one through the SDK's own `libraries.json`.
  File? _sdk(String uri) {
    if (!_readSdk) {
      _readSdk = true;
      _embedded =
          _embeddedLibraries(_packageLib('sky_engine')) ?? _sdkLibraries();
    }
    final path = _embedded?[uri];
    return path == null ? null : File(path);
  }

  /// The `lib/` directory of [package], from the nearest `package_config.json`.
  String? _packageLib(String package) {
    if (!_readPackages) {
      _readPackages = true;
      _packages = _readPackageConfig(dir);
    }
    return _packages?[package];
  }
}

/// `dart:x → file`, from a Flutter project's `sky_engine/lib/_embedder.yaml`.
///
/// Null when there is no `sky_engine` to read, which is what a plain Dart
/// project looks like.
Map<String, String>? _embeddedLibraries(String? skyEngineLib) {
  if (skyEngineLib == null) {
    return null;
  }

  final file = File(p.join(skyEngineLib, '_embedder.yaml'));
  if (!file.existsSync()) {
    return null;
  }

  final Object? doc;
  try {
    doc = loadYaml(file.readAsStringSync());
  } on YamlException {
    return null;
  }

  if (doc is! YamlMap) {
    return null;
  }

  final libs = doc['embedded_libs'];
  if (libs is! YamlMap) {
    return null;
  }
  return {
    for (final entry in libs.entries)
      if (entry.key case final String uri)
        if (entry.value case final String path) uri: p.join(skyEngineLib, path),
  };
}

/// `dart:x → file`, from the running SDK's `lib/libraries.json`.
Map<String, String>? _sdkLibraries() {
  final lib = p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'lib');
  final file = File(p.join(lib, 'libraries.json'));
  if (!file.existsSync()) {
    return null;
  }

  final Object? doc;
  try {
    doc = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }

  if (doc is! Map) {
    return null;
  }
  // The VM's list, since that is the platform frx and its project are built
  // for. The others describe the same libraries for a different compiler.
  final platform = doc['vm'];
  if (platform is! Map || platform['libraries'] is! Map) {
    return null;
  }

  return {
    for (final entry
        in (platform['libraries']! as Map<String, Object?>).entries)
      if (entry.key case final String name)
        if (entry.value case final Map<String, Object?> spec)
          if (spec['uri'] case final String uri)
            'dart:$name': p.normalize(p.join(lib, uri)),
  };
}

/// `package name → lib directory`, from the nearest `package_config.json` above
/// [dir].
///
/// Walked up rather than joined onto a known root because both layouts have to
/// answer: a pub workspace writes one config at the workspace root, a
/// standalone package writes its own.
Map<String, String>? _readPackageConfig(String dir) {
  for (var at = Directory(dir); at.parent.path != at.path; at = at.parent) {
    final config = File(p.join(at.path, '.dart_tool', 'package_config.json'));
    if (!config.existsSync()) {
      continue;
    }

    final Object? doc;
    try {
      doc = jsonDecode(config.readAsStringSync());
    } on FormatException {
      return null;
    }

    if (doc is! Map || doc['packages'] is! List) {
      return null;
    }

    final base = p.join(at.path, '.dart_tool');
    final packages = <String, String>{};
    for (final entry in doc['packages'] as List) {
      if (entry is! Map) {
        continue;
      }

      final name = entry['name'];
      final root = entry['rootUri'];
      if (name is! String || root is! String) {
        continue;
      }

      final rootPath = _fromUri(root, base);
      if (rootPath == null) {
        continue;
      }

      final lib = entry['packageUri'];
      packages[name] = p.normalize(
        p.join(rootPath, lib is String ? lib : 'lib'),
      );
    }
    return packages;
  }

  return null;
}

/// A `package_config.json` root, which is a URI and may be relative to the
/// `.dart_tool` directory holding it.
String? _fromUri(String uri, String base) {
  if (uri.startsWith('file://')) {
    return p.fromUri(Uri.parse(uri));
  }

  if (uri.contains(':')) {
    return null;
  }

  return p.normalize(p.join(base, p.fromUri(uri)));
}
