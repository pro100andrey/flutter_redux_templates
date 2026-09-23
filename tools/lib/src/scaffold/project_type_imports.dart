import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../ast/source_index.dart';
import '../redux/ast_edit.dart';
import '../workspace/frx_workspace.dart';
import 'importable_package.dart';

/// Imports for types *this project* defines, resolved from the filesystem.
///
/// Separate from `TypeImports` and not a table, because a project's own model
/// names cannot be known in advance — only looked up. Kept out of the pure
/// module so that one stays testable without a repository.
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
    final packages = ImportablePackages.of(repo);
    if (packages.isEmpty) {
      return const [];
    }

    final found = <String>{};
    for (final snippet in snippets.nonNulls) {
      for (final match in _identifier.allMatches(snippet)) {
        final uri = packages.uriFor(match.group(1)!);
        if (uri != null) {
          found.add(uri);
        }
      }
    }

    return found.toList()..sort();
  }

  /// What proves the import [uri] is still needed by `body`.
  ///
  /// The same resolution read backwards: an identifier in `body` keeps the
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
    final packages = ImportablePackages.of(repo);
    return (body) {
      for (final match in _identifier.allMatches(body)) {
        if (packages.uriFor(match.group(1)!) == uri) {
          return true;
        }
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
final class ImportablePackages {
  /// Every package `business` may import from, that this repository can read.
  ///
  /// Resolved once per index scope. What this reads — `business/pubspec.yaml`,
  /// each dependency's `name:` — is the same kind of fact as the listings the
  /// index caches: a snapshot of the tree that is good for as long as the
  /// index is, and no longer. Keyed on the index for exactly that reason, and
  /// outside a scope every lookup gets a throwaway index and therefore, as
  /// with every other cache, nothing.
  ///
  /// `models` is included whether or not it is declared: the template's own
  /// `business` depends on it, and a fixture that omits the dependency block
  /// still has to resolve the models it writes.
  factory ImportablePackages.of(FrxWorkspace repo) {
    final index = sourceIndex;
    final byRoot = _perIndex[index] ??= {};
    return byRoot.putIfAbsent(
      p.canonicalize(repo.root.path),
      () => ImportablePackages._(_resolve(repo)),
    );
  }

  ImportablePackages._(this._packages);

  static final _perIndex = Expando<Map<String, ImportablePackages>>();

  /// Sorted by name, so two packages that both resolve a name are detected as
  /// an ambiguity in the same order every run, rather than in listing order.
  final List<ImportablePackage> _packages;

  /// One memo for every question asked in this scope: a state file names
  /// dozens of identifiers and most of them are not models at all, so a miss
  /// — a read of every package's tree — must be paid once, not once per
  /// probe and once more per file the same type is written into.
  final _resolved = <String, String?>{};

  bool get isEmpty => _packages.isEmpty;

  /// The import URI that supplies [identifier], or null when no package here
  /// does — or when more than one does.
  ///
  /// **Ambiguity resolves to nothing.** Two packages can declare the same
  /// `Clock`, and this module's safety argument is that it never produces a
  /// *wrong* import: a missed one is a compile error naming the type, a wrong
  /// one is a compile error naming something else, or worse, a silent bind to
  /// the other package's class. So a name that resolves twice is treated as a
  /// name that did not resolve, and the caller falls back to `--import`.
  String? uriFor(String identifier) => _resolved.putIfAbsent(identifier, () {
    final hits = <String>{};
    for (final package in _packages) {
      final uri = package.uriFor(identifier);
      if (uri != null) {
        hits.add(uri);
      }
    }
    return hits.length == 1 ? hits.single : null;
  });

  static List<ImportablePackage> _resolve(FrxWorkspace repo) {
    final dirs = <String, Directory>{};

    final models = repo.modelsLib;
    if (models.existsSync()) {
      dirs[p.canonicalize(models.path)] = models;
    }

    final business = repo.businessLib.parent;
    for (final dep in _pathDeps(business)) {
      final lib = Directory(p.join(dep.path, 'lib'));
      if (lib.existsSync()) {
        dirs.putIfAbsent(p.canonicalize(lib.path), () => lib);
      }
    }

    final packages = <ImportablePackage>[];
    for (final lib in dirs.values) {
      final name = FrxWorkspace.packageNameIn(lib.parent);
      if (name != null) {
        packages.add(ImportablePackage(name, lib));
      }
    }
    return packages..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The directories of the `path:` dependencies declared in [dir]'s pubspec.
  ///
  /// Direct only, and deliberately: Dart lets a file import the packages its
  /// own package declares and no others, so a transitive walk would resolve
  /// names to imports that do not compile — the one failure mode this module
  /// promises not to have.
  static List<Directory> _pathDeps(Directory dir) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      return const [];
    }
    final Object? doc;
    try {
      doc = loadYaml(pubspec.readAsStringSync());
    } on YamlException {
      // A pubspec frx cannot parse is the user's problem to fix, and not one
      // worth failing `add-field` over: the resolution degrades to `models`.
      return const [];
    }
    if (doc is! YamlMap) {
      return const [];
    }

    final deps = <Directory>[];
    for (final section in const ['dependencies', 'dependency_overrides']) {
      final entries = doc[section];
      if (entries is! YamlMap) {
        continue;
      }
      for (final spec in entries.values) {
        if (spec is! YamlMap) {
          continue;
        }
        final path = spec['path'];
        if (path is String) {
          deps.add(Directory(p.normalize(p.join(dir.path, path))));
        }
      }
    }
    return deps;
  }
}
