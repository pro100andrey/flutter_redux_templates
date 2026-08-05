import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import '../engine/changeset.dart';
import '../workspace/frx_workspace.dart';

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
  ),

  /// The HTTP layer — Dio, Retrofit clients and interceptors. `add-retrofit`
  /// writes here.
  httpClient(
    'http_client',
    'Dio + Retrofit API clients and interceptors',
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
    lintExcludes: ['**/*.g.dart', '**/*.chopper.dart', '**/*.freezed.dart'],
  ),

  /// Key-value persistence behind `BaseKeyValueStorage`. `business` holds the
  /// interface; the sembast adapter and the in-memory one live here.
  storage(
    'storage',
    'Key-value persistence behind BaseKeyValueStorage',
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
    required this.dependencies,
    required this.devDependencies,
    this.build,
    this.lintExcludes = const ['**/*.g.dart', '**/*.freezed.dart'],
  });

  /// The directory, which is also the pub package name and the workspace entry.
  final String dir;

  /// One line for `--help` and for the refusal that names this kind.
  final String summary;

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

    return [
      WriteFile(p.join(dir, 'pubspec.yaml'), _pubspec(kind)),
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
        before: File(root).readAsStringSync(),
        after: addToWorkspace(File(root).readAsStringSync(), kind.dir),
      ),
    ];
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

  static String _pubspec(PackageKind kind) {
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
    kind.dependencies.forEach((k, v) => buffer.writeln('  $k: $v'));
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
