import 'package:analyzer/dart/ast/ast.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/casing.dart';
import 'artifact_name.dart';

/// The naming conventions of one page, derived from its name.
///
/// The single source of truth for "how a page is spelled" — its route type,
/// page and connector class names, file paths, connector import and default
/// route path. Every command that reasons about a page (add / remove / rename /
/// doctor) reads these here instead of re-deriving them by string interpolation.
class PageArtifact {
  /// The annotation auto_route keys a page connector on.
  static const routePageAnnotation = 'RoutePage';

  /// Whether [unit] declares a class carrying `@RoutePage()`.
  ///
  /// Read off the parse tree, never out of the text: `app_router.dart`'s own doc
  /// comment says the word, and a check that cannot tell prose from code reports
  /// the file that is most certainly in the right place. One home, because the
  /// audit's route check and the placement rules both ask — and two syntactic
  /// tests for one question is the failure this repository has already paid for.
  static bool carriesRoutePage(CompilationUnit unit) =>
      unit.declarations.whereType<ClassDeclaration>().any(isRoutePage);

  /// Whether [decl] is an `@RoutePage()` class.
  static bool isRoutePage(ClassDeclaration decl) =>
      decl.metadata.any((m) => m.name.name == routePageAnnotation);

  /// A page named by a **user**: `Home` and `HomePage` are the same page.
  ///
  /// The stemming belongs on this constructor and not inside each command,
  /// because every direction has to agree — `add-page`, `remove --kind page`,
  /// `rename` and `add-nav` all take a name someone typed, and only two of them
  /// were normalising it. `add-page HomePage` wrote `home_page_page.dart` while
  /// `remove HomePage --kind page` looked for a `HomePageRoute` that did not
  /// exist and quietly removed nothing.
  factory PageArtifact(Casing name) =>
      PageArtifact._(ArtifactName.pageStem(name));

  /// A page named by what is **on disk**, taken exactly as read.
  ///
  /// Deliberately does not stem, and the split is the point: a project
  /// scaffolded before the fix above really does contain
  /// `HomePagePageConnector` behind `HomePageRoute`, and stemming what was read
  /// back would make those pages unresolvable. Normalise input; never normalise
  /// a fact.
  const PageArtifact._(this.name);

  factory PageArtifact.parse(String input) => PageArtifact(Casing.parse(input));

  /// Recovers the artifact from a generated route type (`LogInRoute` → the
  /// `logIn` page), or null when [routeType] is not a `<Pascal>Route`.
  static PageArtifact? fromRouteType(String routeType) {
    if (!routeType.endsWith('Route')) return null;
    final base = routeType.substring(0, routeType.length - 'Route'.length);
    return PageArtifact._(Casing.parse(Casing.parse(base).snake));
  }

  final Casing name;

  /// The generated auto_route class, e.g. `LogInRoute`.
  String get routeType => '${name.pascal}Route';

  /// The dumb page class in `ui`, e.g. `LogInPage`.
  String get pageClass => '${name.pascal}Page';

  /// The `@RoutePage()` connector class in `app`, e.g. `LogInPageConnector`.
  String get connectorClass => '${name.pascal}PageConnector';

  /// The connector import as written in `app_router.dart`.
  String get connectorImport =>
      '../connectors/${name.snake}_page_connector.dart';

  /// The default route path, `/dash-separated-words` (no params).
  String get defaultPath => '/${name.words.join('-')}';

  /// The dumb page file, absolute, under [pagesDir].
  File pageFile(Directory pagesDir) =>
      File(p.join(pagesDir.path, '${name.snake}_page.dart'));

  /// The connector file, absolute, under [connectorsDir].
  File connectorFile(Directory connectorsDir) =>
      File(p.join(connectorsDir.path, '${name.snake}_page_connector.dart'));
}
