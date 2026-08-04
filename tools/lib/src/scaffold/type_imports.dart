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
  static List<String> forAll(FrxWorkspace repo, Iterable<String?> snippets) {
    final models = repo.modelsLib;
    if (!models.existsSync()) return const [];
    final package = _packageName(models.parent);
    if (package == null) return const [];

    final found = <String>{};
    for (final snippet in snippets.nonNulls) {
      for (final match in _identifier.allMatches(snippet)) {
        final String snake;
        try {
          snake = Casing.parse(match.group(1)!).snake;
        } on FormatException {
          continue;
        }
        if (File(p.join(models.path, '$snake.dart')).existsSync()) {
          found.add('package:$package/$snake.dart');
        }
      }
    }
    return found.toList()..sort();
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
