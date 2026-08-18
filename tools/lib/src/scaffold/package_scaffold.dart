import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../engine/changeset.dart';
import '../workspace/frx_workspace.dart';

/// Directories the analyzer should not walk in any package: the build output
/// and the per-platform folders Flutter generates.
///
/// Every kind carries these on top of whatever generated-file globs it needs of
/// its own, so they live here rather than being spelled out three times — the
/// catalogue is checked against the real template file by file, and a list
/// repeated per kind is a list that drifts one kind at a time.
///
/// Appended last, because the check compares the excludes in order: the
/// template writes a package's own globs first and these after them.
const _platformExcludes = [
  'build/**',
  'android/**',
  'ios/**',
  'web/**',
  'windows/**',
  'macos/**',
  'linux/**',
];

/// A workspace member this CLI knows how to create.
///
/// A fixed catalogue rather than an arbitrary `--name`: a package is its
/// pubspec, its builders and its lint baseline, and none of those can be
/// guessed from a name. These four are the ones the template ships, so their
/// contents are transcribed from the real thing rather than invented — the same
/// rule the artifact templates follow.
enum PackageKind {
  /// Shared data shapes — freezed models and JSON converters. `add-model`
  /// writes here.
  models(
    'models',
    'Shared freezed models and converters',
    dependents: {'business', 'http_client'},
    dependencies: {
      'fast_immutable_collections': '^11.2.0',
      'freezed_annotation': '^3.1.0',
      'intl': '^0.20.2',
      'json_annotation': '^4.12.0',
    },
    devDependencies: {
      'build_runner': '^2.15.1',
      'freezed': '^3.2.5',
      'json_serializable': '^6.14.0',
      'pro_lints': '^6.1.0',
      'test': '^1.25.0',
    },
    build: _freezedBuild,
    lintExcludes: [
      '**/*.g.dart',
      '**/*.freezed.dart',
      // Its sources sit in folders (`converters/`), and the single-star globs
      // do not reach a generated file one level down.
      '**/**/*.g.dart',
      '**/**/*.freezed.dart',
      ..._platformExcludes,
    ],
  ),

  /// The HTTP layer — Dio, Retrofit clients and interceptors. `add-retrofit`
  /// writes here.
  httpClient(
    'http_client',
    'Dio + Retrofit API clients and interceptors',
    dependents: {'business'},
    dependencies: {
      'dio': '^5.10.0',
      'fast_immutable_collections': '^11.2.0',
      'freezed_annotation': '^3.1.0',
      'json_annotation': '^4.12.0',
      'logging': '^1.3.0',
      'retrofit': '^4.9.2',
    },
    devDependencies: {
      'build_runner': '^2.15.1',
      'freezed': '^3.2.5',
      'json_serializable': '^6.14.0',
      'pro_lints': '^6.1.0',
      'retrofit_generator': '^10.2.7',
      'test': '^1.25.0',
    },
    build: _retrofitBuild,
    lintExcludes: [
      '**/*.g.dart',
      '**/*.chopper.dart',
      '**/*.freezed.dart',
      ..._platformExcludes,
    ],
  ),

  /// Key-value persistence behind `BaseKeyValueStorage`. `business` holds the
  /// interface; the sembast adapter and the in-memory one live here.
  storage(
    'storage',
    'Key-value persistence behind BaseKeyValueStorage',
    dependents: {'business'},
    dependencies: {
      'crypto': '^3.0.7',
      'encrypt': '^5.0.3',
      'path': '^1.9.1',
      'path_provider': '^2.1.6',
      'sembast': '^3.8.9',
      'sembast_web': '^2.4.5',
    },
    devDependencies: {'pro_lints': '^6.1.0'},
  );

  const PackageKind(
    this.dir,
    this.summary, {
    required this.dependents,
    required this.dependencies,
    required this.devDependencies,
    this.build,
    this.lintExcludes = const [
      '**/*.g.dart',
      '**/*.freezed.dart',
      ..._platformExcludes,
    ],
  });

  /// The directory, which is also the pub package name and the workspace entry.
  final String dir;

  /// One line for `--help` and for the refusal that names this kind.
  final String summary;

  /// The workspace members whose pubspec declares a path dependency on this
  /// package — transcribed from the template, like [dependencies].
  ///
  /// **What `create` declares, in both directions**: adding `http_client` puts
  /// the entry in `business`, and puts `models` inside `http_client`, because
  /// this package sits on both ends of that relation.
  ///
  /// It is not what an *omission* reads — that derives the same fact from the
  /// tree it is about to change, so a workspace this catalogue never heard of
  /// is still left resolvable. A test asserts the two agree for the template;
  /// that is what keeps this current when a pubspec gains a line.
  final Set<String> dependents;

  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;

  /// `build.yaml`, for the packages that run a builder. Null writes no file —
  /// `storage` has no codegen.
  final String? build;

  final List<String> lintExcludes;

  static PackageKind? byName(String name) {
    for (final kind in values) {
      if (kind.dir == name) return kind;
    }
    return null;
  }

  /// Is this package already a resolved member of [repo]?
  ///
  /// Keyed on the pubspec, not on the directory: `add-model` in a workspace
  /// without `models` used to create `models/lib/user.dart` and stop, leaving a
  /// directory that is not a package and a file that compiles into nothing.
  /// Existence of the folder is exactly the thing that was not enough.
  bool existsIn(FrxWorkspace repo) =>
      File(p.join(repo.root.path, dir, 'pubspec.yaml')).existsSync();
}

const _freezedBuild = '''
global_options:
  freezed:
    runs_before:
      - json_serializable

targets:
  \$default:
    builders:
      json_serializable:
        options:
          include_if_null: false
      freezed:
        options:
          map: false
          when:
            when: false
            maybe_when: false
            when_or_null: false
''';

const _retrofitBuild = '''
global_options:
  freezed:
    runs_before:
      - json_serializable
  json_serializable:
    runs_before:
      - retrofit_generator

targets:
  \$default:
    builders:
      json_serializable:
        options:
          include_if_null: false
      freezed:
        options:
          map: false
          when:
            when: false
            maybe_when: false
            when_or_null: false
''';

/// Everything that makes `<kind>/` a resolved workspace member.
abstract final class PackageScaffold {
  /// The changes that create [kind] in [repo], or none when it is already
  /// there.
  ///
  /// Returned as a list so a caller can splice it ahead of its own writes in
  /// one [Changeset] — which is the point. Creating a package is five changes
  /// across two directories, and four of them alone leave a workspace that does
  /// not resolve; the shared applier makes the whole set atomic, so there is no
  /// half-created package to clean up by hand.
  static List<Change> create(FrxWorkspace repo, PackageKind kind) {
    if (kind.existsIn(repo)) return const [];

    final dir = p.join(repo.root.path, kind.dir);
    final root = p.join(repo.root.path, 'pubspec.yaml');
    final rootBefore = File(root).readAsStringSync();

    return [
      WriteFile(p.join(dir, 'pubspec.yaml'), _pubspec(kind, repo)),
      WriteFile(p.join(dir, 'analysis_options.yaml'), _lints(kind)),
      if (kind.build case final build?)
        WriteFile(p.join(dir, 'build.yaml'), build),
      WriteFile(p.join(dir, '.gitignore'), _gitignore),
      // `.gitkeep` and not a starter source file: what goes in `lib/` is the
      // next command's business, and a placeholder Dart file would be one more
      // thing to delete.
      WriteFile(p.join(dir, 'lib', '.gitkeep'), ''),
      EditFile(
        root,
        before: rootBefore,
        after: addToWorkspace(rootBefore, kind.dir),
      ),
      // A member nobody may depend on is a directory `pub get` resolves and no
      // `import` can reach. This used to be the user's to write, and the skill
      // said so; what it could not say is which pubspec — the answer is on the
      // kind.
      ..._declarations(repo, kind),
    ];
  }

  /// The changes that unmake [kind] a member of the tree at [root]: every
  /// declaration of it, its `workspace:` entry, and the directory. None when it
  /// is not there.
  ///
  /// The inverse of [create], and what `frx create --without` applies. Kept
  /// beside it rather than in the command, because the pair is the point: an
  /// omission that forgot a declaration would leave a pubspec pointing at
  /// `../models` and a project that does not resolve.
  static List<Change> omit(String root, PackageKind kind) {
    final dir = p.join(root, kind.dir);
    if (!Directory(dir).existsSync()) return const [];

    final rootPubspec = p.join(root, 'pubspec.yaml');
    final before = File(rootPubspec).readAsStringSync();

    return [
      ..._withdrawals(root, kind),
      EditFile(
        rootPubspec,
        before: before,
        after: removeFromWorkspace(before, kind.dir),
      ),
      // Last, so an edit to a pubspec *inside* another omitted package (only
      // `http_client`, which declares `models`) is not written back into a
      // directory a delete has already taken away. Omissions are applied one
      // kind at a time for the same reason.
      DeleteDirectory(dir),
    ];
  }

  /// The pubspec edits that declare [kind] where the template declares it, plus
  /// the ones the new package itself owes.
  ///
  /// Both directions of [PackageKind.dependents], because a package is on both
  /// ends of that relation: creating `http_client` has to declare it in
  /// `business`, *and* declare `models` inside `http_client`. Reading only the
  /// first direction is what left a re-added `http_client` unable to import the
  /// models `add-retrofit` writes against — and `models` had to be re-added
  /// first for it to happen, which is why the round trip did not catch it.
  static List<Change> _declarations(FrxWorkspace repo, PackageKind kind) {
    final edits = <Change>[];
    for (final dependent in kind.dependents) {
      // Skips a dependent that is not there: `models` is declared by
      // `http_client`, which is itself optional, so "who depends on this" and
      // "who is present" are two questions and only the first is a fixed fact.
      final file = File(p.join(repo.root.path, dependent, 'pubspec.yaml'));
      if (!file.existsSync()) continue;

      final before = file.readAsStringSync();
      final after = addDependency(before, kind.dir);
      if (after == before) continue;

      edits.add(EditFile(file.path, before: before, after: after));
    }
    return edits;
  }

  /// Every pubspec under [root] that declares [kind], with the declaration gone.
  ///
  /// **Found rather than looked up.** [PackageKind.dependents] is what [create]
  /// declares, because it has nothing to read; an omission has the tree in front
  /// of it, and a declaration it failed to withdraw is a pubspec pointing at a
  /// directory that is no longer there — `pub get` fails and the project cannot
  /// be opened. Deriving it means the guard holds for a workspace whose members
  /// this catalogue never heard of; that the two agree for the template is a
  /// test rather than an assumption.
  static List<Change> _withdrawals(String root, PackageKind kind) {
    final edits = <Change>[];
    for (final entity in Directory(root).listSync()) {
      if (entity is! Directory || p.basename(entity.path) == kind.dir) continue;

      final file = File(p.join(entity.path, 'pubspec.yaml'));
      if (!file.existsSync()) continue;

      final before = file.readAsStringSync();
      final after = removeDependency(before, kind.dir);
      if (after == before) continue;

      edits.add(EditFile(file.path, before: before, after: after));
    }
    return edits;
  }

  /// [source] with [name] added to the root pubspec's `workspace:` list.
  ///
  /// A surgical splice through `yaml_edit`, not a parse-and-re-serialise: the
  /// root pubspec carries a paragraph of prose about Pub workspaces that a
  /// round-trip would reflow or drop. Returns [source] unchanged when the entry
  /// is already there, so the caller's idempotency needs no second rule.
  static String addToWorkspace(String source, String name) {
    final editor = YamlEditor(source);
    final members = editor.parseAt([
      'workspace',
    ], orElse: () => wrapAsYamlNode(null)).value;

    if (members is! List) {
      throw StateError(
        'The root pubspec has no `workspace:` list — this does not look like '
        'the monorepo (looked in the pubspec beside the frx marker).',
      );
    }
    if (members.contains(name)) return source;

    editor.appendToList(['workspace'], name);
    return editor.toString();
  }

  /// [source] with [name] removed from the `workspace:` list, for the symmetry
  /// `remove` will want. Unchanged when it is not a member.
  static String removeFromWorkspace(String source, String name) {
    final editor = YamlEditor(source);
    final members = editor.parseAt([
      'workspace',
    ], orElse: () => wrapAsYamlNode(null)).value;
    if (members is! List) return source;

    final at = members.indexOf(name);
    if (at < 0) return source;

    editor.remove(['workspace', at]);
    return editor.toString();
  }

  /// For each package in [omitted], the Dart files in [files] — an archive or a
  /// tree, keyed by `/`-separated relative path — that import it.
  ///
  /// **The safety rule of leaving a package out**, and derived rather than
  /// declared: a package can go when nothing outside it names it. `storage` is
  /// optional in the same sense `models` is — its own pubspec, its own
  /// `add-package` — and `business` imports it in four places, so dropping it
  /// produces a project that does not compile. A list of what may be dropped
  /// would be a second copy of that fact and would go stale the first time
  /// somebody wires `http_client` up.
  ///
  /// **A package being omitted is not an importer**, however much it imports.
  /// `http_client` declares `models` and `add-retrofit` writes
  /// `package:models/…` into it; counting that would refuse
  /// `--without models,http_client` — the combination the option exists for —
  /// naming files inside a directory the same run is deleting.
  ///
  /// Bytes rather than strings, and content rather than a parse: the planned
  /// shape this used to read carries no content at all for an entry mold copies
  /// verbatim, so a Dart file in that class was invisible to the one check
  /// standing between `--without` and a project that does not compile.
  static Map<PackageKind, List<String>> importersOf(
    Map<String, List<int>> files,
    List<PackageKind> omitted,
  ) {
    if (omitted.isEmpty) return const {};

    final found = {for (final kind in omitted) kind: <String>[]};
    for (final entry in files.entries) {
      if (!entry.key.endsWith('.dart')) continue;
      if (omitted.any((kind) => isUnder(kind.dir, entry.key))) continue;

      // Malformed input is replaced rather than thrown on: a file that does not
      // decode is not one an import can be read out of, and the audit is what
      // reports it.
      final source = utf8.decode(entry.value, allowMalformed: true);
      for (final kind in omitted) {
        if (source.contains('package:${kind.dir}/')) {
          found[kind]!.add(entry.key);
        }
      }
    }

    for (final importers in found.values) {
      importers.sort();
    }
    return found..removeWhere((_, importers) => importers.isEmpty);
  }

  /// Whether the relative [path] sits under the package directory [dir].
  /// Archive paths are `/`-separated whatever the host is.
  static bool isUnder(String dir, String path) => path.startsWith('$dir/');

  /// [source] with a path dependency on [name] under `dependencies:`.
  /// Unchanged when it is already declared.
  ///
  /// **Inserted in sorted position, not appended**, which is why this is not
  /// `editor.update(['dependencies', name], …)`: that appends, `pro_lints`
  /// turns on `sort_pub_dependencies`, and a project would open with an
  /// analyzer warning in the file this command had just edited.
  ///
  /// So the position is read off the YAML — the keys and their spans — and the
  /// two lines are spliced into the text. A parse-and-re-serialise would place
  /// them correctly and reflow everything else, and a pubspec is not ours to
  /// reformat; it is the reason [addToWorkspace] is a splice too.
  static String addDependency(String source, String name) {
    final editor = YamlEditor(source);
    final deps = editor.parseAt([
      'dependencies',
    ], orElse: () => wrapAsYamlNode(null));

    if (deps is YamlMap && deps.isNotEmpty) {
      if (deps.containsKey(name)) return source;
      return _splice(source, _placeFor(source, deps, name), _entry(name));
    }
    if (deps is YamlMap || deps.value == null) {
      // An empty block, a `dependencies:` with nothing under it, or no key at
      // all — nothing to sort against, so `yaml_edit` writes the whole block.
      editor.update(
        ['dependencies'],
        {
          name: {'path': '../$name'},
        },
      );
      return editor.toString();
    }
    // Anything else is a shape this does not understand, and overwriting it
    // would take a list of dependencies away without saying so. [addToWorkspace]
    // refuses the same class of surprise rather than guessing.
    throw StateError(
      'The `dependencies:` of this pubspec is not a map of package names, so '
      '"$name" cannot be added to it without discarding what is there.',
    );
  }

  /// [source] with the dependency on [name] gone. Unchanged when it declares
  /// none — the idempotency the callers would otherwise each need a rule for.
  ///
  /// A splice, and for a sharper reason than [addDependency]'s: `editor.remove`
  /// takes the blank line after the block with it when the entry removed is the
  /// last one, so it was not the inverse of an insert in that one position.
  /// Cutting exactly the lines the entry spans is inverse by construction.
  static String removeDependency(String source, String name) {
    final deps = YamlEditor(
      source,
    ).parseAt(['dependencies'], orElse: () => wrapAsYamlNode(null));
    if (deps is! YamlMap) return source;

    for (final entry in deps.nodes.entries) {
      if ((entry.key as YamlScalar).value != name) continue;
      final from = _startOfLine(
        source,
        (entry.key as YamlScalar).span.start.offset,
      );
      final to = _afterLine(source, entry.value.span.end.offset);
      return source.substring(0, from) + source.substring(to);
    }
    return source;
  }

  /// The two lines a path dependency on [name] is written as.
  static String _entry(String name) => '  $name:\n    path: ../$name\n';

  /// Where in [source] an entry named [name] belongs, given the existing
  /// (non-empty) [deps].
  ///
  /// **After the last entry that sorts before it**, rather than before the first
  /// that sorts after. The two differ by exactly one thing: a comment sits above
  /// the key it annotates, so inserting *before* a key inserts between that key
  /// and its comment — silently re-parenting prose onto the new entry, in a
  /// splice whose whole purpose is to leave prose alone.
  static int _placeFor(String source, YamlMap deps, String name) {
    YamlNode? previous;
    for (final entry in deps.nodes.entries) {
      if (((entry.key as YamlScalar).value as String).compareTo(name) > 0)
        break;
      previous = entry.value;
    }
    if (previous != null) return _afterLine(source, previous.span.end.offset);

    // It sorts before everything: the top of the block, above the first entry
    // *and* above the comment lines that belong to it.
    var at = _startOfLine(source, deps.span.start.offset);
    while (at > 0) {
      final previousStart = at == 1 ? 0 : _startOfLine(source, at - 2);
      final line = source.substring(previousStart, at - 1).trim();
      if (line.isNotEmpty && !line.startsWith('#')) break;
      at = previousStart;
    }
    return at;
  }

  /// [source] with [entry] inserted at [at].
  ///
  /// A source that does not end in a newline is given one first: [_afterLine]
  /// answers `source.length` for the last line of such a file, and splicing
  /// there would run the new entry onto the end of the last one.
  static String _splice(String source, int at, String entry) =>
      at == source.length && !source.endsWith('\n')
      ? '$source\n$entry'
      : source.substring(0, at) + entry + source.substring(at);

  /// The offset of the first character on the line holding [offset].
  static int _startOfLine(String source, int offset) {
    final newline = source.lastIndexOf('\n', offset);
    return newline < 0 ? 0 : newline + 1;
  }

  /// The offset just past the end of the line holding [offset], newline
  /// included — where a following line can be spliced in.
  ///
  /// Trailing whitespace is walked back over first, because a block node's span
  /// may end past its last character: taken literally, the next newline would
  /// then be the one *after* the line meant, and the splice would land a line
  /// too low.
  static int _afterLine(String source, int offset) {
    var at = offset;
    while (at > 0 && _isSpace(source.codeUnitAt(at - 1))) {
      at--;
    }
    final newline = source.indexOf('\n', at);
    return newline < 0 ? source.length : newline + 1;
  }

  static bool _isSpace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;

  /// The optional packages [kind] itself depends on — [PackageKind.dependents]
  /// read from the other end.
  static Iterable<PackageKind> _dependsOnOptional(PackageKind kind) =>
      PackageKind.values.where((other) => other.dependents.contains(kind.dir));

  static String _pubspec(PackageKind kind, FrxWorkspace repo) {
    // Version constraints and path dependencies in one sorted block, because
    // `sort_pub_dependencies` does not care which sort of entry it is looking
    // at. A path dependency on a package that is not in this workspace is left
    // out: it would resolve to a directory that is not there.
    final entries = <String, String>{
      for (final dep in kind.dependencies.entries) dep.key: ' ${dep.value}',
      for (final other in _dependsOnOptional(kind))
        if (other.existsIn(repo)) other.dir: '\n    path: ../${other.dir}',
    };
    final names = entries.keys.toList()..sort();

    final buffer = StringBuffer()
      ..writeln('name: ${kind.dir}')
      ..writeln('description: The ${kind.dir} package.')
      ..writeln('publish_to: none')
      ..writeln('version: 1.0.0')
      ..writeln()
      ..writeln('environment:')
      ..writeln('  sdk: ^3.12.0')
      ..writeln()
      // The line that makes it a member rather than a package that happens to
      // sit in the tree. Without it `pub get` from the root ignores this
      // directory and the workspace entry points at nothing.
      ..writeln('resolution: workspace')
      ..writeln()
      ..writeln('dependencies:');
    for (final dep in names) {
      buffer.writeln('  $dep:${entries[dep]}');
    }
    buffer
      ..writeln()
      ..writeln('dev_dependencies:');
    kind.devDependencies.forEach((k, v) => buffer.writeln('  $k: $v'));
    return buffer.toString();
  }

  static String _lints(PackageKind kind) {
    final buffer = StringBuffer()
      ..writeln('include: package:pro_lints/recommended.yaml')
      ..writeln()
      ..writeln('analyzer:')
      ..writeln('  exclude:');
    for (final glob in kind.lintExcludes) {
      buffer.writeln('    - "$glob"');
    }
    return buffer.toString();
  }

  static const _gitignore = '''
# Miscellaneous
*.class
*.log
*.pyc
*.swp
.DS_Store
.atom/
.buildlog/
.history
.svn/
migrate_working_dir/

# IntelliJ related
*.iml
*.ipr
*.iws
.idea/

# Flutter/Dart/Pub related
# Libraries should not include pubspec.lock, per https://dart.dev/guides/libraries/private-files#pubspeclock.
/pubspec.lock
**/doc/api/
.dart_tool/
.packages
build/
''';
}
