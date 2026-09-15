/// The package imports a piece of generated Dart needs in order to *name* the
/// types it mentions.
///
/// One module because a single `add-field` writes the same type into three
/// files — the freezed state, `selectors.dart`, and the setter action — and
/// each of them has to import it independently. Before this the question was
/// answered twice by a regex in `add-field` and not at all by the third caller:
/// `ArtifactTemplates.fieldSetter` took the type as an opaque string and
/// hardcoded its two relative imports, so
///
///     frx add-field session tags:IList<String> --default 'IListConst([])'
///     --action
///
/// wrote `final IList<String> tags;` into a file with nothing importing
/// `IList`. `add-selector --type 'IList<String>'` had the same hole.
///
/// Deliberately syntactic: this matches type *names* in a source snippet, it
/// does not resolve them. That is the same trade the rest of frx makes, and it
/// is safe in the one direction that matters — a missed import fails the build
/// loudly, and there is no shape here that produces a wrong one.
///
/// Two answers under one door. [TypeImports] is the table — the packages a
/// generated file may need that can be known in advance. [ProjectTypeImports]
/// is the lookup — the project's own types, which can only be found on disk —
/// and lives in `project_type_imports.dart` so the table stays testable
/// without a repository. [ImportProbes] is the pair read backwards.
library;

import '../redux/ast_edit.dart';
import '../workspace/frx_workspace.dart';
import 'project_type_imports.dart';

export 'project_type_imports.dart' show ProjectTypeImports;

/// Maps a type a caller can ask for to the import that supplies it.
abstract final class TypeImports {
  const TypeImports._();

  /// `fast_immutable_collections` — the immutable collections a freezed state
  /// field uses instead of `List`/`Map`/`Set`.
  static const fastImmutableCollections =
      'package:fast_immutable_collections/fast_immutable_collections.dart';

  /// `(pattern, import)` pairs, checked against every snippet.
  ///
  /// `(Const)?` catches the `const` constructors a `--default` names
  /// (`IListConst([])`) as well as the types themselves; the trailing `\b`
  /// keeps an unrelated `IListView` from pulling the package in.
  static final List<(RegExp, String)> _rules = [
    (RegExp(r'\b(?:IList|IMap|ISet)(?:Const)?\b'), fastImmutableCollections),
  ];

  /// The imports [snippets] need between them, in [_rules] order and
  /// de-duplicated. Nulls are skipped so a caller can pass an optional
  /// `--default` without a branch.
  static List<String> forAll(Iterable<String?> snippets) {
    final present = snippets.nonNulls.toList();
    return [
      for (final (pattern, import) in _rules)
        if (present.any(pattern.hasMatch)) import,
    ];
  }

  /// The imports a single type expression needs.
  static List<String> forType(String type) => forAll([type]);

  /// What proves an import this module supplies is still needed, for the edit
  /// that takes a type *away*.
  ///
  /// **Deliberately looser than the rule that adds it.** [_rules] answers "is
  /// this snippet a sufficient reason to add the import", and a sufficient
  /// condition for adding is not a necessary one for keeping: the package also
  /// exports `IListView`, `IMapOfSets` and the rest, which the add rule's
  /// trailing `\b` excludes and which stop compiling the moment the import
  /// goes. Erring wide leaves an import nothing uses — a lint; erring narrow
  /// takes one out from under live code — a build.
  ///
  /// One registry, shared with the facade's own pruning: the same
  /// `selectors.dart` must not get opposite answers depending on whether a
  /// field or a whole substate was removed.
  static final _probes = <String, RegExp>{
    fastImmutableCollections: RegExp(r'\b(?:IList|IMap|ISet)'),
  };

  /// The probe for [uri], or null when this module does not supply it.
  static ImportProbe? probeFor(String uri) {
    final pattern = _probes[uri];
    return pattern?.hasMatch;
  }
}

/// The imports a *removed* snippet may have been the last user of, each with
/// the pattern that proves it is still needed by what remains.
///
/// The exact inverse of what `add-field` asks [TypeImports] and
/// [ProjectTypeImports] for, and deliberately no wider than that: the
/// candidates are computed from the
/// declaration being taken out, so a prune can only ever reach an import that
/// this same declaration could have brought in. Everything else in the file —
/// `freezed_annotation`, a hand-written import — is not a candidate and is
/// never examined.
abstract final class ImportProbes {
  const ImportProbes._();

  /// The prune candidates for [snippets], for [pruneImports].
  ///
  /// Nulls are skipped, so a caller can pass a declaration and its optional
  /// `@Default(...)` the way `add-field` passes them to `forAll`.
  static Map<String, ImportProbe> forRemoved(
    FrxWorkspace repo,
    Iterable<String?> snippets,
  ) {
    final probes = <String, ImportProbe>{};
    for (final uri in TypeImports.forAll(snippets)) {
      final probe = TypeImports.probeFor(uri);
      if (probe != null) {
        probes[uri] = probe;
      }
    }
    // Keyed by the file, asked by the file: the identifiers the removed snippet
    // happened to name are not the only ones it supplies, and the probe has to
    // answer for all of them.
    for (final uri in ProjectTypeImports.forAll(repo, snippets)) {
      probes[uri] = ProjectTypeImports.probeFor(repo, uri);
    }
    return probes;
  }
}
