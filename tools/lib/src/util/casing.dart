/// Turns any identifier-ish input — `profile`, `user_profile`, `UserProfile`,
/// `user-profile` — into the case variants the scaffolder needs.
class Casing {
  Casing(this.words);

  /// Lower-cased words, e.g. `['user', 'profile']`.
  final List<String> words;

  /// A name must start with a letter and contain only letters, digits, and the
  /// separators space / `_` / `-`. Enforced here — the single normalization
  /// seam — so no scaffolder (page templates, connector, actions) can emit a
  /// class name or string literal with an injectable character.
  static final _validName = RegExp(r'^[A-Za-z][A-Za-z0-9 _-]*$');

  factory Casing.parse(String input) {
    if (!_validName.hasMatch(input.trim())) {
      throw const FormatException(
        'name must start with a letter and use only letters, digits, '
        'spaces, _ or -',
      );
    }
    final spaced = input
        // split camelCase / PascalCase boundaries: "userProfile" -> "user Profile"
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        // collapse separators to spaces
        .replaceAll(RegExp(r'[_\-\s]+'), ' ')
        .trim();

    final words = spaced
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();

    if (words.isEmpty) {
      throw const FormatException('name must contain at least one letter');
    }
    return Casing(words);
  }

  /// `user_profile`
  String get snake => words.join('_');

  /// `UserProfile`
  String get pascal => words.map(_capitalize).join();

  /// `userProfile`
  String get camel {
    final p = pascal;
    return p[0].toLowerCase() + p.substring(1);
  }

  static String _capitalize(String w) => w[0].toUpperCase() + w.substring(1);
}
