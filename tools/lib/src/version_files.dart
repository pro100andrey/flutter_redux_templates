/// Where the version is declared, and how each declaration is read and
/// written — stated once.
///
/// Three statements of one fact, and each was parsed by hand in every place
/// that touched it: the `version` verb's replacement patterns, the test's
/// matching regexes, and the release workflow's `sed`s. Two of those agreeing
/// was a coincidence; the verb accepted a `+build` the test's regex took and
/// npm then stripped. The workflow's shell is the one copy left, because it
/// runs before any Dart is set up.
library;

/// One file's declaration of the version, relative to `tools/`.
class VersionDeclaration {
  const VersionDeclaration(this.path, this._pattern);

  /// Relative to the `tools/` package, `/`-separated.
  final String path;

  /// Group 1 is everything up to the version, group 2 the version itself.
  final String _pattern;

  RegExp get _regex => RegExp(_pattern, multiLine: true);

  /// The version [content] declares, or null when it declares none.
  String? readFrom(String content) => _regex.firstMatch(content)?.group(2);

  /// [content] declaring [version] instead, or null when it declares none.
  String? writeTo(String content, String version) {
    if (!_regex.hasMatch(content)) {
      return null;
    }
    return content.replaceFirstMapped(_regex, (m) => '${m[1]}$version');
  }
}

/// What `dart install` reports.
const pubspecVersion = VersionDeclaration(
  'pubspec.yaml',
  r'^(version:[ \t]*)(\S+)',
);

/// What `frx --version` prints.
const constantVersion = VersionDeclaration(
  'lib/src/version.dart',
  "(frxVersion = ')([^']*)",
);

/// What the Marketplace publishes. Written by `npm version`, which also keeps
/// the lock in step, so nothing here writes it.
const extensionVersion = VersionDeclaration(
  'vscode/package.json',
  r'^(\s*"version"\s*:\s*")([^"]+)',
);

/// A version all three files can hold as written: MAJOR.MINOR.PATCH with an
/// optional `-prerelease`. No `+build` — npm strips it from package.json, so
/// the three could never agree.
final versionShape = RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$');
