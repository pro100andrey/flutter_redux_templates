/// What a selector declaration looks like — the one place that decides.
///
/// Four modules used to answer this independently: the graph reader, the
/// placement rules, the substate scaffold that writes one, and the facade
/// writer that wires one in. Two of those answers disagreed, and the gap
/// between them was reachable:
///
/// - The placement rules required `implements Selector`, so a selector written
///   outside the facade *without* that clause — the easiest half to forget, and
///   the half that actually puts the getters on the facade — was reported by
///   nothing. The rule went silent in exactly the case it exists for.
/// - The graph reader matched a composite only as `on Select` or `on Selector`
///   exactly, so `extension … on SelectLogIn` was invisible and the selectors it
///   read counted as read by nobody — a false "nothing reads it" in the
///   dead-selector list, which is the direction that invites deleting working
///   code.
///
/// **Recognition is wider than generation.** [declare] writes the one shape frx
/// makes; [of] accepts several, including the ones a project scaffolded before
/// the spine collapsed still contains (`implements Selector`, an `extension type
/// Select`). The declaration this architecture most needs to notice is the one a
/// human wrote by hand and got subtly wrong, and a recognizer that only sees
/// what the generator writes today cannot report either a bad one or an old
/// one.
///
/// This module is the *primitive*: it owns the facade's vocabulary and the test
/// for belonging to it. [SubstateArtifact] keeps the substate-shaped questions
/// and asks here for the naming, so `Select` is spelled in one place rather than
/// in each module that happens to need it.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// One selector declaration, read off the parse tree.
class SelectorDecl {
  const SelectorDecl({
    required this.name,
    required this.owner,
    required this.members,
    required this.declaresOwner,
  });

  /// The declaration's own name, or null for an unnamed `extension on Select…`.
  final String? name;

  /// Whether this declaration *is* [owner], rather than adding to it.
  ///
  /// `extension type SelectLogIn(…)` declares it; `extension X on SelectLogIn`
  /// adds to it. The distinction is what separates the facade's spine being
  /// *declared* — whose getters are hops onto other selectors, not selectors —
  /// from it being *extended*, whose getters are composites and are.
  final bool declaresOwner;

  /// The type whose members these getters become — itself for an
  /// `extension type Select…`, whatever it extends for an `extension … on`.
  ///
  /// This is what decides how a getter is *called*, which is not what it is
  /// *declared* on: a getter added by `extension X on SelectLogIn` is reached as
  /// `select.logIn.<getter>`, not as `select.<getter>`, however `X` is named.
  final String owner;

  /// The declaration's members, empty when it has no block body.
  final List<ClassMember> members;

  /// Whether these getters land on the facade's own spine rather than on a
  /// substate's selectors — `Selectors`, or the `Select` an older project has.
  ///
  /// Reached *through*, so they carry no substate of their own; a reader that
  /// files nodes per substate has nowhere to put them.
  bool get onFacadeSpine => SelectorShape.isFacadeSpine(owner);

  /// How to name it in a message, for a declaration that may have none.
  String get label => name ?? 'the extension on $owner';
}

/// The facade's vocabulary, and the test for belonging to it.
abstract final class SelectorShape {
  const SelectorShape._();

  /// The extension type every substate's selectors hang off, and the prefix
  /// each of their type names carries.
  static const facadeType = 'Select';

  /// The mixin **is** the facade: what a consumer mixes in to reach every
  /// substate's selectors.
  ///
  /// There used to be two more spine types beside it — a root `Selector` whose
  /// one member was `Select get select`, and a `Select` extension type carrying
  /// one getter per substate, the same list the mixin carries. Measured across
  /// the template: nothing constructed a `Selector`, nothing read `.select`,
  /// and the one composite hanging off `Select` was unreachable because the
  /// only route to it was. Every consumer — six connectors and the base
  /// `Action` — reaches the facade by `with Selectors`.
  ///
  /// So a substate cost two parallel getter lists to add, one of which nobody
  /// could call. `Select` survives as the *prefix* on `SelectLogin` and friends
  /// ([typeFor]); only the declaration is gone.
  static const mixinType = 'Selectors';

  /// The `Select<Pascal>` type name for a substate.
  static String typeFor(String pascal) => '$facadeType$pascal';

  /// The selector [node] declares, or null when it declares none.
  ///
  /// Deliberately syntactic, and deliberately generous: it keys on the name and
  /// on what an extension extends, never on what a type *is*. The placement
  /// rules already state the bar a rule has to clear — its syntactic form cannot
  /// be wrong in the common case — and inheritance defeats a syntactic reading,
  /// which is why an `implements` clause is not required here.
  ///
  /// **The `Selectors` mixin declaration itself is not handled, and that is not
  /// an omission.** It carries only the spine — one `SelectX get <field>` per
  /// substate — which is a hop onto a substate's selectors, not a selector.
  /// `addSelector`, the only thing that writes a computed getter, targets a
  /// `Select<Pascal>` extension type. A composite written as `extension … on
  /// Selectors` *is* handled, by the [ExtensionDeclaration] branch, and lands on
  /// the spine exactly as it did when it was written `on Select`.
  static SelectorDecl? of(AstNode node) {
    if (node is ExtensionTypeDeclaration) {
      final name = node.namePart.typeName.lexeme;
      if (!isSelectorType(name)) return null;
      return SelectorDecl(
        name: name,
        owner: name,
        members: _membersOf(node.body),
        declaresOwner: true,
      );
    }
    if (node is ExtensionDeclaration) {
      final on = node.onClause?.extendedType;
      if (on is! NamedType) return null;
      final owner = on.name.lexeme;
      if (!isSelectorType(owner)) return null;
      return SelectorDecl(
        name: node.name?.lexeme,
        owner: owner,
        members: _membersOf(node.body),
        declaresOwner: false,
      );
    }
    return null;
  }

  /// Whether [type] is the facade's own spine rather than a substate's
  /// selectors.
  ///
  /// The mixin belongs here as much as the two extension types: a getter added
  /// to `Selectors` reaches every consumer that mixes it in, which is the
  /// facade's reach and not one substate's.
  /// [facadeType] is still named here, though the template no longer declares
  /// it: a project scaffolded before the spine collapsed still has an
  /// `extension type Select`, and reading one must not file its hops as if they
  /// were a substate's selectors.
  static bool isFacadeSpine(String type) =>
      type == facadeType || type == mixinType;

  /// Whether [type] names a selector type at all.
  ///
  /// The prefix alone is not the test: `Selectable` starts with `Select` and is
  /// an ordinary Dart name. What is required is that the rest start a new word —
  /// or that the name be the spine itself, which carries no word after the
  /// prefix at all.
  static bool isSelectorType(String type) {
    if (isFacadeSpine(type)) return true;
    if (!type.startsWith(facadeType) || type.length == facadeType.length) {
      return false;
    }
    final rest = type.substring(facadeType.length);
    return rest[0].toUpperCase() == rest[0];
  }

  /// How a substate's selector type is written.
  ///
  /// The spelling lives beside [of] so the generator and the recognizer cannot
  /// drift apart — which is the failure this module was extracted to end.
  /// No `implements`: the interface it used to declare against carried one
  /// member, `select`, which let a substate's selectors reach a sibling's. In
  /// the whole template not one of them did — every getter reads its own
  /// substate — so the reach was a door nobody opened, and it made each type a
  /// subtype of something with no other purpose.
  static String declare({required String type, required String body}) =>
      'extension type $type(AppState _state) {\n$body}\n';

  static List<ClassMember> _membersOf(AstNode? body) =>
      body is BlockClassBody ? body.members : const <ClassMember>[];
}
