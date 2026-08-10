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
///     frx add-field session tags:IList<String> --default 'IListConst([])' --action
///
/// wrote `final IList<String> tags;` into a file with nothing importing
/// `IList`. `add-selector --type 'IList<String>'` had the same hole.
///
/// Deliberately syntactic: this matches type *names* in a source snippet, it
/// does not resolve them. That is the same trade the rest of frx makes, and it
/// is safe in the one direction that matters — a missed import fails the build
/// loudly, and there is no shape here that produces a wrong one.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../redux/ast_edit.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';

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
  /// trailing `\b` excludes and which stop compiling the moment the import goes.
  /// Erring wide leaves an import nothing uses — a lint; erring narrow takes one
  /// out from under live code — a build.
  ///
  /// One registry, shared with the facade's own pruning: the same
  /// `selectors.dart` must not get opposite answers depending on whether a field
  /// or a whole substate was removed.
  static final _probes = <String, RegExp>{
    fastImmutableCollections: RegExp(r'\b(?:IList|IMap|ISet)'),
  };

  /// The probe for [uri], or null when this module does not supply it.
  static ImportProbe? probeFor(String uri) {
    final pattern = _probes[uri];
    return pattern == null ? null : pattern.hasMatch;
  }
}

/// Imports for types *this project* defines, resolved from the filesystem.
///
/// Separate from [TypeImports] and not a table, because a project's own model
/// names cannot be known in advance — only looked up. Kept out of the pure
/// module above so that one stays testable without a repository.
///
/// Why it exists at all: `add-field --force` retypes a field, and the type it
/// retypes *to* is almost always one of these. `IMap<int, Object>` becoming
/// `IMap<int, Task>` without `package:models/task.dart` is a file that does not
/// compile — and the guard that made `--force` necessary also refuses the hand
/// edit that would add the import.
abstract final class ProjectTypeImports {
  const ProjectTypeImports._();

  /// A capitalised identifier is a candidate type name; `IMap<int, Task>` and
  /// `IMapConst<int, Task>({})` both yield `IMap`/`IMapConst` and `Task`, and
  /// only the ones with a file behind them survive the lookup.
  static final _identifier = RegExp(r'\b([A-Z][A-Za-z0-9_]*)\b');

  /// The imports [snippets] need from this repository's own packages.
  static List<String> forAll(FrxWorkspace repo, Iterable<String?> snippets) =>
      resolve(repo, snippets).keys.toList()..sort();

  /// The same lookup, keeping the identifier each import was found *for*.
  ///
  /// The identifier is what a caller pruning the import needs, and deriving it
  /// back from the URI is lossy in a way that matters: `IOSSettings` writes
  /// `iossettings.dart`, and `Casing.parse('iossettings').pascal` is
  /// `Iossettings` — a symbol nothing spells, so the import reads as unused and
  /// is taken out from under live code. Carried forward, it cannot drift.
  static Map<String, Set<String>> resolve(
    FrxWorkspace repo,
    Iterable<String?> snippets,
  ) {
    final models = repo.modelsLib;
    if (!models.existsSync()) return const {};
    final package = _packageName(models.parent);
    if (package == null) return const {};

    final found = <String, Set<String>>{};
    for (final snippet in snippets.nonNulls) {
      for (final match in _identifier.allMatches(snippet)) {
        final identifier = match.group(1)!;
        final file = _fileFor(models, identifier);
        if (file == null) continue;
        found.putIfAbsent('package:$package/$file', () => {}).add(identifier);
      }
    }
    return found;
  }

  /// What proves one of these imports is still needed by [body].
  ///
  /// Not "does `Task` still appear". A model file holds the type it is named
  /// after **and every case of it** when that type is a sealed union — `frx
  /// add-model Result -c loading -c success` writes `Result`, `ResultLoading`
  /// and `ResultSuccess` into `result.dart` — and a probe that only knew the
  /// union's own name pruned the import out from under a surviving case.
  ///
  /// So a name that *starts with* one of [identifiers] counts too, unless it has
  /// a model file of its own: `TaskList` lives in `task_list.dart` and keeps
  /// that import alive, not `task.dart`'s.
  static ImportProbe probeFor(FrxWorkspace repo, Set<String> identifiers) {
    final models = repo.modelsLib;
    return (body) {
      for (final match in _identifier.allMatches(body)) {
        final id = match.group(1)!;
        for (final name in identifiers) {
          if (id == name) return true;
          if (id.startsWith(name) && _fileFor(models, id) == null) return true;
        }
      }
      return false;
    };
  }

  /// The model file basename [identifier] would be declared in, or null when
  /// this project has no such file (or the name is not one [Casing] reads).
  static String? _fileFor(Directory models, String identifier) {
    final String snake;
    try {
      snake = Casing.parse(identifier).snake;
    } on FormatException {
      return null;
    }
    final file = File(p.join(models.path, '$snake.dart'));
    return file.existsSync() ? '$snake.dart' : null;
  }

  /// The `name:` of the pubspec in [dir], or null when there is none to read.
  /// Read rather than assumed: `models` is what the template calls it, and a
  /// project that renamed the package is not wrong.
  static String? _packageName(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final match = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    return match?.group(1);
  }
}

/// The imports a *removed* snippet may have been the last user of, each with
/// the pattern that proves it is still needed by what remains.
///
/// The exact inverse of what `add-field` asks the two modules above for, and
/// deliberately no wider than that: the candidates are computed from the
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
      if (probe != null) probes[uri] = probe;
    }
    for (final entry in ProjectTypeImports.resolve(repo, snippets).entries) {
      probes[entry.key] = ProjectTypeImports.probeFor(repo, entry.value);
    }
    return probes;
  }
}
