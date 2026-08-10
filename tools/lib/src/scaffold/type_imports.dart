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
import 'package:yaml/yaml.dart';

import '../ast/source_index.dart';
import '../redux/ast_edit.dart';
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
    final packages = _ImportablePackages.of(repo);
    if (packages.isEmpty) return const [];

    final memo = <String, String?>{};
    final found = <String>{};
    for (final snippet in snippets.nonNulls) {
      for (final match in _identifier.allMatches(snippet)) {
        final uri = _uriFor(packages, match.group(1)!, memo);
        if (uri != null) found.add(uri);
      }
    }
    return found.toList()..sort();
  }

  /// The import URI that supplies [identifier], or null when no package here
  /// does — or when more than one does.
  ///
  /// **Ambiguity resolves to nothing.** Two packages can declare the same
  /// `Clock`, and this module's safety argument is that it never produces a
  /// *wrong* import: a missed one is a compile error naming the type, a wrong
  /// one is a compile error naming something else, or worse, a silent bind to
  /// the other package's class. So a name that resolves twice is treated as a
  /// name that did not resolve, and the caller falls back to `--import`.
  static String? _uriFor(
    List<_ImportablePackage> packages,
    String identifier,
    Map<String, String?> memo,
  ) => memo.putIfAbsent(identifier, () {
    final hits = <String>{};
    for (final package in packages) {
      final uri = package.uriFor(identifier);
      if (uri != null) hits.add(uri);
    }
    return hits.length == 1 ? hits.single : null;
  });

  /// What proves the import [uri] is still needed by [body].
  ///
  /// The same resolution read backwards: an identifier in [body] keeps the
  /// import alive when it resolves to *that URI*. Not "does `Result` still
  /// appear" — a union's cases are supplied by the file its union names, so
  /// `ResultSuccess` alone keeps `result.dart`, and not "does anything starting
  /// with `Task` appear", which was the guess this replaces and which kept
  /// `task.dart` alive for a surviving `TaskList`.
  ///
  /// Keyed by the URI rather than the file basename it used to take: once more
  /// than one package can supply an import, `digest.dart` no longer identifies
  /// one, and two packages with a same-named file would have shared a probe.
  static ImportProbe probeFor(FrxWorkspace repo, String uri) {
    final packages = _ImportablePackages.of(repo);
    // One memo for the whole probe: a state file names dozens of identifiers
    // and most of them are not models at all, so a miss must be paid once.
    final memo = <String, String?>{};
    return (body) {
      for (final match in _identifier.allMatches(body)) {
        if (_uriFor(packages, match.group(1)!, memo) == uri) return true;
      }
      return false;
    };
  }
}

/// The packages a file generated into `business` may name a type from.
///
/// `models` and no more was the whole answer until this: the resolver joined
/// `<root>/models/lib/<snake>.dart` and stopped, so a type living in any other
/// package of the workspace — or in a sibling checkout brought in by a path
/// dependency — could not be resolved and `add-field` wrote a field whose type
/// nothing imported. The gap was not "domain types are unknown", which is how
/// it reads from outside: `models`-resident domain types resolved fine. It was
/// that the search space was one directory.
///
/// The set is read from `business/pubspec.yaml` rather than the workspace list,
/// because those are different sets and only one of them is the right one. A
/// path dependency need not be a workspace member (a sibling checkout under
/// active development is the case that matters), and a workspace member need
/// not be a dependency — and what a generated file may import is exactly what
/// its own package declares.
abstract final class _ImportablePackages {
  const _ImportablePackages._();

  /// Every package `business` may import from, that this repository can read.
  ///
  /// `models` is included whether or not it is declared: the template's own
  /// `business` depends on it, and a fixture that omits the dependency block
  /// still has to resolve the models it writes.
  static List<_ImportablePackage> of(FrxWorkspace repo) {
    final dirs = <String, Directory>{};

    final models = repo.modelsLib;
    if (models.existsSync()) dirs[p.canonicalize(models.path)] = models;

    final business = repo.businessLib.parent;
    for (final dep in _pathDeps(business)) {
      final lib = Directory(p.join(dep.path, 'lib'));
      if (lib.existsSync())
        dirs.putIfAbsent(p.canonicalize(lib.path), () => lib);
    }

    final packages = <_ImportablePackage>[];
    for (final lib in dirs.values) {
      final name = _packageName(lib.parent);
      if (name != null) packages.add(_ImportablePackage(name, lib));
    }
    // Sorted so two packages that both resolve a name are detected as an
    // ambiguity in the same order every run, rather than in listing order.
    return packages..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The directories of the `path:` dependencies declared in [dir]'s pubspec.
  ///
  /// Direct only, and deliberately: Dart lets a file import the packages its own
  /// package declares and no others, so a transitive walk would resolve names to
  /// imports that do not compile — the one failure mode this module promises not
  /// to have.
  static List<Directory> _pathDeps(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const [];
    final Object? doc;
    try {
      doc = loadYaml(pubspec.readAsStringSync());
    } on YamlException {
      // A pubspec frx cannot parse is the user's problem to fix, and not one
      // worth failing `add-field` over: the resolution degrades to `models`.
      return const [];
    }
    if (doc is! YamlMap) return const [];

    final deps = <Directory>[];
    for (final section in const ['dependencies', 'dependency_overrides']) {
      final entries = doc[section];
      if (entries is! YamlMap) continue;
      for (final spec in entries.values) {
        if (spec is! YamlMap) continue;
        final path = spec['path'];
        if (path is String) {
          deps.add(Directory(p.normalize(p.join(dir.path, path))));
        }
      }
    }
    return deps;
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

/// One package, asked "what would a file have to import to name this type?".
class _ImportablePackage {
  _ImportablePackage(this.name, this.lib);

  final String name;
  final Directory lib;

  final _entries = <String, String?>{};

  /// The import URI of this package that supplies [identifier], or null.
  ///
  /// Two questions. **Which file declares it**, and then **which entry point
  /// exports that file**, when the declaration turns out to live under
  /// `lib/src/` — private by pub's convention, and importing it directly is not
  /// how anybody reaches the class.
  ///
  /// There used to be a third, asked first and cheapest: `Task` is in
  /// `task.dart`, the convention `add-model` writes, one `existsSync`. It is
  /// gone because it answered from the *file name* and never opened the file.
  /// A `models/lib/task.dart` holding `class TaskList` and a `Task` next door in
  /// `other.dart` made it answer `package:models/task.dart` for `Task` — an
  /// import that resolves and does not supply the name, which is the one failure
  /// this module's doc promises it cannot have. The convention it encoded is not
  /// lost: when `task.dart` does declare `Task`, the declaration search finds it
  /// there, having checked.
  String? uriFor(String identifier) {
    final file = _byDeclaration(identifier);
    return file == null ? null : _entryFor(file, identifier, {});
  }

  /// The file that declares [identifier] — or redirects a factory to it, which
  /// is how a freezed union names its cases.
  ///
  /// Text first: [SourceIndex.unitIf] reads each file and parses only the ones
  /// that contain the word at all, so a miss costs reads and no parses. That
  /// pre-filter is what makes the widened search space affordable — the six path
  /// dependencies of one real app are 228 files and 1.3 MB, of which a given
  /// identifier matches a handful.
  ///
  /// Recursive, unlike the `models`-only lookup this replaces: `lib/src/` is
  /// where a package with a barrel keeps everything, and `models/lib/converters/`
  /// was invisible to the old walk for the same reason.
  ///
  /// Generated files are not searched — `result.freezed.dart` declares the case
  /// too, and importing *it* is not how anybody reaches the class.
  File? _byDeclaration(String identifier) {
    final wanted = _declarationText(identifier);
    for (final file in sourceIndex.filesUnder(lib)) {
      final unit = sourceIndex.unitIf(file, wanted.hasMatch);
      if (unit == null) continue;
      if (_declares(unit, identifier)) return file;
    }
    return null;
  }

  /// The text a file must contain before it is worth parsing for [identifier].
  ///
  /// A plain `contains` is not a pre-filter here, it is a full scan wearing one:
  /// `String` occurs in essentially every Dart file, so `add-field x note:String?`
  /// parsed all 161 files of one real app's dependency closure to conclude that
  /// none of them declares it — 400 ms and 161 parses to answer "no". Matching
  /// the *declaration* instead costs the same read and almost never the parse.
  ///
  /// Kept deliberately in step with [_declares], which is the authority: this
  /// only has to be no *narrower*, and `type_imports` asserts exactly that over
  /// every declaration form Dart has. A branch missing here is not a slow
  /// answer, it is a wrong one — the file is never parsed, so the declaration
  /// in it is never seen and the import never written.
  ///
  /// The branches, in the order they appear:
  ///
  /// - the keyword forms. `abstract final class X`, `sealed class X` and
  ///   `mixin class X` all contain `class X`; `extension type const X(int i)`
  ///   is why `const` is optional there.
  /// - `typedef`, which has two syntaxes and puts the name in a different place
  ///   in each — `typedef X = void Function()` and the legacy
  ///   `typedef void X()`. Bounded to one statement so it cannot run away.
  /// - the redirect a freezed union writes, `= ResultSuccess;`, which is how a
  ///   case class is named in source before `build_runner` generates it.
  static RegExp _declarationText(String identifier) {
    final name = RegExp.escape(identifier);
    return RegExp(
      r'(?:class|mixin|enum|extension\s+type(?:\s+const)?)\s+'
      '$name'
      r'\b'
      r'|typedef[^;\n]*\b'
      '$name'
      r'\b'
      r'|=\s*'
      '$name'
      r'\s*[;(<]',
    );
  }

  /// The importable URI for [file] — itself when it is public, otherwise the
  /// entry point that exports it.
  ///
  /// Walked upwards from the declaration rather than downwards from every entry
  /// point, because the two directions cost differently: a package's export
  /// closure is its whole source tree (`tm_core` is 163 files), while the files
  /// that mention one basename are a handful the text pre-filter finds. [seen]
  /// bounds a cyclic re-export.
  String? _entryFor(File file, String identifier, Set<String> seen) {
    final key = p.canonicalize(file.path);
    if (!seen.add(key)) return null;

    final relative = p.url.joinAll(
      p.split(p.relative(file.path, from: lib.path)),
    );
    if (!relative.startsWith('src/')) return 'package:$name/$relative';

    // Keyed by the identifier as well as the file: `show`/`hide` mean two names
    // declared side by side in one private file can come out of different entry
    // points, or one of them out of none.
    return _entries.putIfAbsent('$identifier|$key', () {
      final basename = p.basename(file.path);
      for (final candidate in sourceIndex.filesUnder(lib)) {
        if (p.canonicalize(candidate.path) == key) continue;
        final unit = sourceIndex.unitIf(candidate, (s) => s.contains(basename));
        if (unit == null) continue;
        if (!_exports(unit, candidate, key, identifier)) continue;
        final uri = _entryFor(candidate, identifier, seen);
        if (uri != null) return uri;
      }
      return null;
    });
  }

  /// Whether [unit] re-exports [identifier] from the file at [target].
  ///
  /// Only relative exports are followed. `export 'package:other/other.dart'` is
  /// a different package's entry point, and this package is not what supplies
  /// the name — the other one is, and it is resolved on its own if it is a
  /// dependency and correctly not resolved if it is not.
  ///
  /// The combinators are honoured, and that is not pedantry: this module's whole
  /// safety argument is that it can miss an import but never invent a wrong one,
  /// and `export 'src/store.dart' show SqliteEventStore` is a real barrel in a
  /// real dependency here. Answering `package:tm_store_sqlite/tm_store_sqlite.dart`
  /// for the *other* class in that file would be an import that resolves and
  /// does not supply the name — the exact failure the doc above promises away.
  static bool _exports(
    CompilationUnit unit,
    File from,
    String target,
    String identifier,
  ) {
    for (final directive in unit.directives.whereType<ExportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || uri.contains(':')) continue;
      final resolved = p.canonicalize(
        p.normalize(p.join(p.dirname(from.path), p.fromUri(uri))),
      );
      if (resolved != target) continue;
      if (_combinatorsAdmit(directive, identifier, File(target))) return true;
    }
    return false;
  }

  /// Whether [directive]'s `show`/`hide` list lets [identifier] out of [target].
  ///
  /// A union case is admitted by its union's name too — `show Result` exports
  /// `ResultSuccess`, because the case is a constructor redirect on the class
  /// the combinator names, not a separate top-level name to list. Established by
  /// reading that redirect in [target], **not** by `ResultSuccess.startsWith`:
  /// the prefix guess admits `MemoryDigestInternals` for a `show MemoryDigest`,
  /// which is the same guess this module's `probeFor` doc records having thrown
  /// out for keeping `task.dart` alive for a surviving `TaskList`.
  static bool _combinatorsAdmit(
    ExportDirective directive,
    String identifier,
    File target,
  ) {
    for (final combinator in directive.combinators) {
      switch (combinator) {
        case ShowCombinator(:final shownNames):
          final shown = shownNames.map((n) => n.name).toSet();
          if (shown.contains(identifier)) continue;
          final unit = sourceIndex.unitIf(
            target,
            (s) => s.contains(identifier),
          );
          final owners = unit == null
              ? const <String>{}
              : _redirectOwners(unit, identifier);
          if (owners.any(shown.contains)) continue;
          return false;
        case HideCombinator(:final hiddenNames):
          if (hiddenNames.any((n) => n.name == identifier)) return false;
      }
    }
    return true;
  }

  /// Whether [unit] supplies [identifier] — declares it outright, or names it as
  /// the case of a union it declares.
  static bool _declares(CompilationUnit unit, String identifier) =>
      _declaredNames(unit).contains(identifier) ||
      _redirectOwners(unit, identifier).isNotEmpty;

  /// The top-level type names [unit] declares.
  static Set<String> _declaredNames(CompilationUnit unit) => {
    for (final declaration in unit.declarations)
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
      if (switch (declaration) {
            ClassDeclaration(:final namePart) ||
            ExtensionTypeDeclaration(:final namePart) ||
            EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
            MixinDeclaration(:final name) ||
            TypeAlias(:final name) => name.lexeme,
            _ => null,
          }
          case final String declared)
        declared,
  };

  /// The classes in [unit] that redirect a factory to [identifier] — the shape
  /// `const factory Result.success() = ResultSuccess;` has, where the case class
  /// itself is generated and this is where the source says its name.
  ///
  /// One reading of the redirect, asked two ways. "Does this file supply
  /// `ResultSuccess`?" is `isNotEmpty`; "does `show Result` carry it?" is
  /// `contains('Result')`. They were two functions walking the same members for
  /// the same statement, which is how a resolver ends up agreeing with itself
  /// only by coincidence.
  static Set<String> _redirectOwners(
    CompilationUnit unit,
    String identifier,
  ) => {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>())
      if (switch (declaration.body) {
        BlockClassBody(:final members) => members,
        _ => const <ClassMember>[],
      }.whereType<ConstructorDeclaration>().any(
        (m) => m.redirectedConstructor?.type.name.lexeme == identifier,
      ))
        declaration.namePart.typeName.lexeme,
  };
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
      probes[uri] = ProjectTypeImports.probeFor(repo, uri);
    }
    return probes;
  }
}
