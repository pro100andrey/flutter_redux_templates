/// Whether a piece of source names an identifier as a word of its own.
///
/// Asked of *text*, and that is deliberate: the readers that ask it are looking
/// at the members of a class frx did not write, and what they need is "does
/// this member's source still spell the name" — not what the name resolves to,
/// which a parse without resolution cannot say anyway. Two readers had the same
/// rule as two private functions, one word apart.
library;

/// Whether [source] names [identifier] as a bare word — not as the tail of
/// `other.identifier`, and not inside a longer name.
///
/// `token != null` reads the getter called `token`; `_state.session.token`
/// names the state's field of that name, which survives the getter's removal
/// and must not be counted as a reader of it.
bool mentionsIdentifier(String source, String identifier) {
  for (final match in RegExp(
    '\\b${RegExp.escape(identifier)}\\b',
  ).allMatches(source)) {
    final at = match.start;
    if (at == 0 || source[at - 1] != '.') {
      return true;
    }
  }

  return false;
}
