import 'dart:io';

import 'package:path/path.dart' as p;

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

/// A workspace member this CLI knows how to createPackage.
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
  /// **What `createPackage` declares, in both directions**: adding
  /// `http_client` puts the entry in `business`, and puts `models` inside
  /// `http_client`, because this package sits on both ends of that relation.
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
      if (kind.dir == name) {
        return kind;
      }
    }
    return null;
  }

  /// Is this package already a resolved member of [repo]?
  ///
  /// Keyed on the pubspec, not on the directory: `add-model` in a workspace
  /// without `models` used to createPackage `models/lib/user.dart` and stop,
  /// leaving a directory that is not a package and a file that compiles into
  /// nothing. Existence of the folder is exactly the thing that was not enough.
  bool existsIn(FrxWorkspace repo) =>
      File(p.join(repo.root.path, dir, 'pubspec.yaml')).existsSync();

  /// The optional packages this one itself depends on — [dependents] read from
  /// the other end.
  Iterable<PackageKind> get _dependsOnOptional =>
      values.where((other) => other.dependents.contains(dir));

  /// The `pubspec.yaml` that makes `<dir>/` a member of [repo].
  String pubspec(FrxWorkspace repo) {
    // Version constraints and path dependencies in one sorted block, because
    // `sort_pub_dependencies` does not care which sort of entry it is looking
    // at. A path dependency on a package that is not in this workspace is left
    // out: it would resolve to a directory that is not there.
    final entries = <String, String>{
      for (final dep in dependencies.entries) dep.key: ' ${dep.value}',
      for (final other in _dependsOnOptional)
        if (other.existsIn(repo)) other.dir: '\n    path: ../${other.dir}',
    };
    final names = entries.keys.toList()..sort();

    final buffer = StringBuffer()
      ..writeln('name: $dir')
      ..writeln('description: The $dir package.')
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
    devDependencies.forEach((k, v) => buffer.writeln('  $k: $v'));
    return buffer.toString();
  }

  /// The `analysis_options.yaml`: the shared lint baseline, minus
  /// [lintExcludes].
  String get analysisOptions {
    final buffer = StringBuffer()
      ..writeln('include: package:pro_lints/recommended.yaml')
      ..writeln()
      ..writeln('analyzer:')
      ..writeln('  exclude:');
    for (final glob in lintExcludes) {
      buffer.writeln('    - "$glob"');
    }
    return buffer.toString();
  }

  /// The `.gitignore` every package kind shares.
  static const gitignore = '''
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

/// The `global_options` head of every `build.yaml` here: freezed runs before
/// json_serializable, so the generated `fromJson` sees the union it is for.
const _freezedFirst = '''
global_options:
  freezed:
    runs_before:
      - json_serializable
''';

/// The extra ordering a Retrofit package adds under the same head: the client
/// generator runs after the serializers it calls.
const _thenRetrofit = '''
  json_serializable:
    runs_before:
      - retrofit_generator
''';

/// The builder options both kinds share.
const _builderTargets = r'''

targets:
  $default:
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

const _freezedBuild = '$_freezedFirst$_builderTargets';

const _retrofitBuild = '$_freezedFirst$_thenRetrofit$_builderTargets';
