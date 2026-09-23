import 'package:path/path.dart' as p;

/// The project file a directive's [uri] names, written in the file at [from] —
/// or null when it names none of the project's: a `dart:` library, another
/// scheme, or a `package:` URI of a package that is not one of [packages]
/// (package name → absolute `lib/` directory).
///
/// Without a `package_config.json`, deliberately. The questions asked of it —
/// which import follows a moved file, which import names a file a removal
/// deletes, which import names nothing at all — are about the project's own
/// files, whose `lib/` directories the workspace already knows, and a fixture
/// or a freshly unpacked project has no resolution to read yet.
String? workspaceTarget(
  String uri, {
  required String from,
  required Map<String, String> packages,
}) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    final lib = slash <= 0 ? null : packages[rest.substring(0, slash)];
    return lib == null
        ? null
        : p.normalize(p.join(lib, rest.substring(slash + 1)));
  }

  if (uri.contains(':')) {
    return null; // dart:, or a scheme that names no file of the project
  }
  return p.normalize(p.join(p.dirname(from), uri));
}

/// [path] spelled as a `package:` URI of the package whose `lib/` holds it, or
/// null when none of [packages] does.
String? packageUriOf(String path, Map<String, String> packages) {
  for (final MapEntry(key: name, value: lib) in packages.entries) {
    if (p.isWithin(lib, path)) {
      return 'package:$name/${uriPath(p.relative(path, from: lib))}';
    }
  }
  return null;
}

/// A platform path as a URI path: `/`-separated whatever the platform's is.
String uriPath(String path) => p.split(path).join('/');
