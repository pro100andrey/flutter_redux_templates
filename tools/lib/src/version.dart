/// The frx CLI version.
///
/// Pinned to `version:` in `pubspec.yaml` by `version_test.dart` — the doc
/// used to say "keep in sync" and nothing checked. Kept as a compile-time
/// constant (not read from pubspec at runtime) so `frx --version` works after
/// `dart install`, where the pubspec no longer sits next to the executable.
const frxVersion = '0.3.3';
