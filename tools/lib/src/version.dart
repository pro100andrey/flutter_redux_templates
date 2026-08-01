/// The frx CLI version.
///
/// Keep in sync with `version:` in `pubspec.yaml`. Kept as a compile-time
/// constant (not read from pubspec at runtime) so `frx --version` works after
/// `dart install`, where the pubspec no longer sits next to the executable.
const frxVersion = '0.1.6';
