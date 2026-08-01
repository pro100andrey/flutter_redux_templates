/// Reading an artifact back out of a name.
///
/// The inverse of the forward direction in [PageArtifact] and
/// [SubstateArtifact], which turn a name into `LogInRoute`,
/// `LogInPageConnector`, `LogInState`, `SelectLogIn`. This turns those back.
///
/// It lived inside `which_command.dart` — as a candidate list in a private
/// method, next to a `_Match` type also private to that file. The forward
/// mapping and its inverse were in different tiers, so adding a suffix meant
/// finding two unrelated places, and only one of them was where you would look.
library;

import '../util/casing.dart';
import 'selector_shape.dart';
import 'target_resolver.dart';

/// One way a token might decompose: the base name, the artifact kind it would
/// imply, and the affix that was stripped to get there.
typedef NameCandidate = ({
  String base,
  ArtifactKind? kind,
  String? suffix,
  String? prefix,
});

/// The naming conventions frx writes, read backwards.
abstract final class NamingConvention {
  const NamingConvention._();

  /// The suffix a substate's state class carries.
  static const stateSuffix = 'State';

  /// The prefix a substate's selector extension type carries.
  static const selectorPrefix = SelectorShape.facadeType;

  /// Every way [token] might decompose, in the order they should be tried.
  ///
  /// The last entry is always the bare token — a field name (`logIn`) or a
  /// folder name (`log_in`) that carries no affix at all.
  static List<NameCandidate> candidatesFor(String token) => [
    if (token.endsWith('PageConnector'))
      (
        base: _dropEnd(token, 'PageConnector'),
        kind: ArtifactKind.page,
        suffix: 'PageConnector',
        prefix: null,
      ),
    if (token.endsWith('Route'))
      (
        base: _dropEnd(token, 'Route'),
        kind: ArtifactKind.page,
        suffix: 'Route',
        prefix: null,
      ),
    if (token.endsWith('Page') && !token.endsWith('PageConnector'))
      (
        base: _dropEnd(token, 'Page'),
        kind: ArtifactKind.page,
        suffix: 'Page',
        prefix: null,
      ),
    if (token.endsWith(stateSuffix))
      (
        base: _dropEnd(token, stateSuffix),
        kind: ArtifactKind.substate,
        suffix: stateSuffix,
        prefix: null,
      ),
    if (token.startsWith(selectorPrefix) &&
        token.length > selectorPrefix.length)
      (
        base: token.substring(selectorPrefix.length),
        kind: ArtifactKind.substate,
        suffix: null,
        prefix: selectorPrefix,
      ),
    (base: token, kind: null, suffix: null, prefix: null),
  ];

  /// The first candidate whose base parses as a name and satisfies [isSubstate]
  /// or [isPage], or null when nothing matches.
  ///
  /// The predicates are passed in rather than looked up: what exists in a repo
  /// is the caller's question, and keeping it out means this is testable
  /// without one.
  static ResolvedName? resolve(
    String token, {
    required bool Function(Casing) isSubstate,
    required bool Function(Casing) isPage,
  }) {
    for (final c in candidatesFor(token)) {
      final Casing name;
      try {
        name = Casing.parse(c.base);
      } on FormatException {
        continue;
      }
      if ((c.kind == null || c.kind == ArtifactKind.substate) &&
          isSubstate(name)) {
        return ResolvedName(
          ArtifactKind.substate,
          name.snake,
          c.suffix,
          c.prefix,
        );
      }
      if ((c.kind == null || c.kind == ArtifactKind.page) && isPage(name)) {
        return ResolvedName(ArtifactKind.page, name.snake, c.suffix, c.prefix);
      }
    }
    return null;
  }

  static String _dropEnd(String s, String end) =>
      s.substring(0, s.length - end.length);
}

/// What a token resolved to: the artifact, its base name, and the affix that
/// identified it — the editor uses the affix to know how much of a symbol to
/// select when renaming.
class ResolvedName {
  const ResolvedName(this.kind, this.name, this.suffix, this.prefix);

  final ArtifactKind kind;

  /// The base name, snake_cased — the casing every frx command resolves.
  final String name;

  final String? suffix;
  final String? prefix;
}
