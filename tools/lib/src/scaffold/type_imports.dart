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

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
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
  ///
  /// The file, not the identifier it was found for. Both callers want the
  /// import: one adds it, the other asks [probeFor] whether it is still needed
  /// — and that question is about everything the *file* supplies, not about the
  /// one name that happened to lead there. Carrying the identifiers as well was
  /// how the prune side got its own second answer to "what does this file
  /// hold", and the two disagreed.
  static List<String> forAll(FrxWorkspace repo, Iterable<String?> snippets) {
    final models = repo.modelsLib;
    if (!models.existsSync()) return const [];
    final package = _packageName(models.parent);
    if (package == null) return const [];

    final memo = <String, String?>{};
    final found = <String>{};
    for (final snippet in snippets.nonNulls) {
      for (final match in _identifier.allMatches(snippet)) {
        final file = _fileFor(models, match.group(1)!, memo);
        if (file != null) found.add('package:$package/$file');
      }
    }
    return found.toList()..sort();
  }

  /// What proves the import of model file [basename] is still needed by [body].
  ///
  /// The same resolution read backwards: an identifier in [body] keeps the
  /// import alive when it resolves to *that file*. Not "does `Result` still
  /// appear" — a union's cases are supplied by the file its union names, so
  /// `ResultSuccess` alone keeps `result.dart`, and not "does anything starting
  /// with `Task` appear", which was the guess this replaces and which kept
  /// `task.dart` alive for a surviving `TaskList`.
  static ImportProbe probeFor(FrxWorkspace repo, String basename) {
    final models = repo.modelsLib;
    // One memo for the whole probe: a state file names dozens of identifiers
    // and most of them are not models at all, so a miss must be paid once.
    final memo = <String, String?>{};
    return (body) {
      for (final match in _identifier.allMatches(body)) {
        if (_fileFor(models, match.group(1)!, memo) == basename) return true;
      }
      return false;
    };
  }

  /// The model file basename that supplies [identifier], or null when this
  /// project has none.
  ///
  /// Two questions, in cost order. **By name** — `Task` is in `task.dart` —
  /// which is the convention `add-model` writes and costs one `existsSync`.
  /// **By declaration**, when that misses: a file supplies more names than the
  /// one it is called after, and the case that matters is the sealed union,
  /// where `add-model Result -c success` writes
  ///
  /// ```dart
  /// sealed class Result with _$Result {
  ///   const factory Result.success() = ResultSuccess;
  /// }
  /// ```
  ///
  /// `ResultSuccess` is declared in the generated part and reached through
  /// `result.dart`, so the name-based lookup asked for a `result_success.dart`
  /// that does not exist and `add-field last:ResultSuccess?` wrote a field with
  /// nothing importing its type. The redirect is the statement that ties the
  /// two, and it is in the source file rather than the generated one — so this
  /// answers before `build_runner` has ever run.
  ///
  /// [memo] holds both hits and misses: the second question reads the whole
  /// models directory, and a snippet naming `String`, `IList` and `Default`
  /// would otherwise pay for it once per word.
  static String? _fileFor(
    Directory models,
    String identifier,
    Map<String, String?> memo,
  ) => memo.putIfAbsent(
    identifier,
    () => _byName(models, identifier) ?? _byDeclaration(models, identifier),
  );

  static String? _byName(Directory models, String identifier) {
    final String snake;
    try {
      snake = Casing.parse(identifier).snake;
    } on FormatException {
      return null;
    }
    return File(p.join(models.path, '$snake.dart')).existsSync()
        ? '$snake.dart'
        : null;
  }

  /// The model file that declares [identifier] — or redirects a factory to it,
  /// which is how a freezed union names its cases.
  ///
  /// Text first: [SourceIndex.unitIf] reads each file and parses only the ones
  /// that contain the word at all, so a miss costs reads and no parses.
  /// Generated files are not searched — `result.freezed.dart` declares the case
  /// too, and importing *it* is not how anybody reaches the class.
  static String? _byDeclaration(Directory models, String identifier) {
    for (final file in sourceIndex.filesUnder(models, recursive: false)) {
      final unit = sourceIndex.unitIf(file, (s) => s.contains(identifier));
      if (unit == null) continue;
      if (_declares(unit, identifier)) return p.basename(file.path);
    }
    return null;
  }

  static bool _declares(CompilationUnit unit, String identifier) {
    for (final declaration in unit.declarations) {
      // Each kind carries its own name, and the analyzer 14 spelling differs
      // between them — `namePart.typeName` for the ones that can be augmented,
      // a plain `name` for the rest. There is no shared supertype to ask, so
      // the list is spelled out.
      //
      // A kind missing from it is **not** symmetric between the two directions
      // this resolver serves. Adding: a missed import is a compile error naming
      // the type, which is loud. Pruning: the probe reads "nothing here needs
      // that file" and takes a live import out — silent, and in a state file
      // nobody is allowed to put back by hand. So a new declaration kind
      // belongs here before it belongs anywhere.
      final declared = switch (declaration) {
        ClassDeclaration(:final namePart) ||
        ExtensionTypeDeclaration(:final namePart) ||
        EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
        MixinDeclaration(:final name) || TypeAlias(:final name) => name.lexeme,
        _ => null,
      };
      if (declared == identifier) return true;

      // `const factory Result.success() = ResultSuccess;` — the case class is
      // generated, and this is where the source says its name.
      if (declaration is ClassDeclaration) {
        final body = declaration.body;
        final members = body is BlockClassBody
            ? body.members
            : const <ClassMember>[];
        for (final member in members.whereType<ConstructorDeclaration>()) {
          if (member.redirectedConstructor?.type.name.lexeme == identifier) {
            return true;
          }
        }
      }
    }
    return false;
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
    // Keyed by the file, asked by the file: the identifiers the removed snippet
    // happened to name are not the only ones it supplies, and the probe has to
    // answer for all of them.
    for (final uri in ProjectTypeImports.forAll(repo, snippets)) {
      probes[uri] = ProjectTypeImports.probeFor(repo, p.basename(uri));
    }
    return probes;
  }
}
