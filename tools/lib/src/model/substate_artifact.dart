import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/casing.dart';
import 'selector_shape.dart';

/// The naming conventions of one AsyncRedux substate, derived from its name.
///
/// The single source of truth for "how a substate is spelled" — its field,
/// state type, selector type, folder, file paths and action class names. Every
/// command that reasons about a substate (add / remove / rename / doctor /
/// list) reads these here instead of re-deriving them by string interpolation.
class SubstateArtifact {
  const SubstateArtifact(this.name);

  factory SubstateArtifact.parse(String input) =>
      SubstateArtifact(Casing.parse(input));

  final Casing name;

  /// The `AppState` field, e.g. `logIn`.
  String get field => name.camel;

  /// The state class / `AppState` field type, e.g. `LogInState`.
  String get stateType => '${name.pascal}State';

  /// The `Select<Pascal>` extension type in the selectors facade.
  String get selectorType => SelectorShape.typeFor(name.pascal);

  /// The [field] a `Select<Pascal>` extension type belongs to, or null when
  /// [type] is not one — the inverse of [selectorType].
  ///
  /// The facade is where a selector's owner is *stated*: which substates its
  /// body reads is a different question (a composite reads several), so a
  /// reader that needs the owner asks the type name, not the edges.
  ///
  /// What counts as a selector type is [SelectorShape]'s question, asked rather
  /// than restated: the facade's own spine is one, and it belongs to no
  /// substate — without that the `Selectors` mixin reads as a substate named
  /// `ors`.
  static String? substateOfSelectorType(String type) {
    if (!SelectorShape.isSelectorType(type)) return null;
    if (SelectorShape.isFacadeSpine(type)) return null;
    try {
      return Casing.parse(
        type.substring(SelectorShape.facadeType.length),
      ).camel;
    } on FormatException {
      return null;
    }
  }

  /// The waiting enum a `table`-kind substate generates.
  String get waitingEnum => '${name.pascal}Waiting';

  /// The domain action named after the substate (e.g. `ForgotPasswordAction`).
  String get actionClass => '${name.pascal}Action';

  /// The `table`-kind action pair.
  String get addActionClass => 'Add${name.pascal}Action';
  String get retrieveActionClass => 'Retrieve${name.pascal}Action';

  /// The substate folder name under `business/lib/redux`.
  String get folder => name.snake;

  /// The state-model import path, relative to the redux directory
  /// (`<snake>/models/<snake>_state.dart`) — how `AppState` imports it.
  String get stateImportPath => '$folder/models/${name.snake}_state.dart';

  /// The substate folder, absolute, under [reduxDir].
  Directory dir(Directory reduxDir) => Directory(p.join(reduxDir.path, folder));

  /// The state-model file, absolute, under [reduxDir].
  File stateFile(Directory reduxDir) =>
      File(p.join(reduxDir.path, folder, 'models', '${name.snake}_state.dart'));

  /// The frx-generated action file basenames this substate can carry, mapped to
  /// their equivalents under [to] — used by `rename` to move `<old>_state.dart`
  /// → `<new>_state.dart` etc. while leaving hand-written files untouched (their
  /// classes match no rename pattern, so file and class stay in step).
  Map<String, String> renamableBasenames(SubstateArtifact to) => {
    '${name.snake}_state.dart': '${to.name.snake}_state.dart',
    '${name.snake}_action.dart': '${to.name.snake}_action.dart',
    'add_${name.snake}_action.dart': 'add_${to.name.snake}_action.dart',
    'retrieve_${name.snake}_action.dart':
        'retrieve_${to.name.snake}_action.dart',
  };
}
