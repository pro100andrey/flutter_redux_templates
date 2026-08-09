import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/scaffold/package_scaffold.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// The root pubspec's `workspace:` block, as the template writes it — prose
/// comment and all. The comment is the point: a parse-and-re-serialise would
/// drop it, and this file is not ours to reformat.
const _rootPubspec = '''
name: flutter_redux_templates
publish_to: none

environment:
  sdk: ^3.12.0

# Pub workspaces (monorepo support). Each listed directory must contain a
# pubspec.yaml with `resolution: workspace`.
workspace:
  - localization
  - ui
  - business
  - app
''';

/// A dependency block with the shapes that make placement non-trivial: a
/// one-line entry, a two-line `sdk:` entry, a two-line `path:` entry, and a
/// `dev_dependencies:` block right after the one being edited.
const _businessPubspec = '''
name: business
publish_to: none

dependencies:
  async_redux: ^28.0.0
  flutter:
    sdk: flutter
  logging: ^1.3.0
  storage:
    path: ../storage

dev_dependencies:
  pro_lints: ^6.1.0
''';

void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  /// Removes an optional package from the fixture, which ships the full set.
  ///
  /// The condition under test is a workspace that was created without it — the
  /// state `frx create --without` or a hand-pruned clone leaves behind — and
  /// the fixture has to be put into it rather than assumed to be in it.
  void prune(String pkg) {
    Directory(fx.path(pkg)).deleteSync(recursive: true);
    fx
        .file('pubspec.yaml')
        .writeAsStringSync(
          PackageScaffold.removeFromWorkspace(fx.read('pubspec.yaml'), pkg),
        );
  }

  group('addToWorkspace', () {
    test('appends the member and keeps the comment above the list', () {
      final out = PackageScaffold.addToWorkspace(_rootPubspec, 'models');

      expect(out, contains('- models'));
      expect(
        out,
        contains('# Pub workspaces (monorepo support).'),
        reason: 'the prose has to survive — it is why this is a splice',
      );
      expect(out, contains('- app'), reason: 'existing members stay');
    });

    test('is idempotent — a member already there changes nothing', () {
      final once = PackageScaffold.addToWorkspace(_rootPubspec, 'models');
      expect(PackageScaffold.addToWorkspace(once, 'models'), once);
    });

    test('refuses a pubspec with no workspace list', () {
      expect(
        () => PackageScaffold.addToWorkspace('name: x\n', 'models'),
        throwsStateError,
      );
    });

    test('removeFromWorkspace is the inverse', () {
      final added = PackageScaffold.addToWorkspace(_rootPubspec, 'models');
      expect(
        PackageScaffold.removeFromWorkspace(added, 'models'),
        _rootPubspec,
      );
    });

    test('removing a non-member changes nothing', () {
      expect(
        PackageScaffold.removeFromWorkspace(_rootPubspec, 'nope'),
        _rootPubspec,
      );
    });
  });

  /// The catalogue transcribes each optional package from the real thing, and
  /// nothing re-derived it: bump a constraint in `models/pubspec.yaml` and
  /// `add-package models` goes on writing the old one, in a package the round
  /// trip does not compare because `--without` never wrote it either.
  ///
  /// A test rather than a `doctor` check, for the reason the skills and the
  /// template use one: a project made by `frx create` carries neither the
  /// catalogue nor the packages to compare it against.
  group('the catalogue matches the template', () {
    final repoRoot = p.dirname(Directory.current.absolute.path);

    YamlMap? load(PackageKind kind, String file) {
      final f = File(p.join(repoRoot, kind.dir, file));
      if (!f.existsSync()) return null;
      return loadYaml(f.readAsStringSync()) as YamlMap;
    }

    for (final kind in PackageKind.values) {
      test('${kind.dir} — the lint excludes', () {
        final options = load(kind, 'analysis_options.yaml');
        if (options == null) return; // pruned from this checkout
        expect(
          (options['analyzer'] as YamlMap)['exclude'],
          orderedEquals(kind.lintExcludes),
          reason: 'PackageKind.${kind.name}.lintExcludes has drifted',
        );
      });

      test('${kind.dir} — the version constraints', () {
        final pubspec = load(kind, 'pubspec.yaml');
        if (pubspec == null) return;
        // Path dependencies are `dependents` read from the other end, and the
        // create/add round trip is what holds those.
        Map<String, String> versioned(String block) => {
          for (final e in (pubspec[block] as YamlMap).entries)
            if (e.value is String) '${e.key}': '${e.value}',
        };

        expect(versioned('dependencies'), kind.dependencies);
        expect(versioned('dev_dependencies'), kind.devDependencies);
      });
    }
  });

  group('importersOf — what may be left out', () {
    Map<String, List<int>> tree(Map<String, String> sources) => {
      for (final e in sources.entries) e.key: utf8.encode(e.value),
    };

    test('names the files outside the package that import it', () {
      final found = PackageScaffold.importersOf(
        tree({
          'business/lib/persistor.dart':
              "import 'package:storage/storage.dart';",
          'ui/lib/pages/home_page.dart':
              "import 'package:flutter/material.dart';",
        }),
        [PackageKind.storage],
      );

      expect(found[PackageKind.storage], ['business/lib/persistor.dart']);
    });

    test("a package's own files are not importers of itself", () {
      final found = PackageScaffold.importersOf(
        tree({
          'storage/test/x_test.dart': "import 'package:storage/storage.dart';",
        }),
        [PackageKind.storage],
      );

      expect(found, isEmpty);
    });

    test('nor are the other packages going out in the same run', () {
      // `http_client` declares `models` and `add-retrofit` writes
      // `package:models/…` into it. Counting that refused
      // `--without models,http_client` — the pairing the option exists for —
      // naming files inside a directory the same run deletes.
      final sources = tree({
        'http_client/lib/api/auth.dart': "import 'package:models/user.dart';",
      });

      expect(
        PackageScaffold.importersOf(sources, [
          PackageKind.models,
          PackageKind.httpClient,
        ]),
        isEmpty,
      );
      expect(
        PackageScaffold.importersOf(sources, [PackageKind.models]),
        {
          PackageKind.models: ['http_client/lib/api/auth.dart'],
        },
        reason: 'dropping models alone really would break http_client',
      );
    });

    test('a file that does not decode is scanned, not skipped', () {
      // The planned-file shape this used to read carries no content for an
      // entry mold copies verbatim, so a Dart file in that class was invisible
      // to the one check standing between `--without` and a broken project.
      final found = PackageScaffold.importersOf(
        {
          'business/lib/odd.dart': [
            0xFF,
            0xFE,
            ...utf8.encode("import 'package:storage/storage.dart';"),
          ],
        },
        [PackageKind.storage],
      );

      expect(found[PackageKind.storage], ['business/lib/odd.dart']);
    });

    test('non-Dart files are not read for imports', () {
      final found = PackageScaffold.importersOf(
        tree({
          'README.md': 'Uses `package:storage/storage.dart` for persistence.',
        }),
        [PackageKind.storage],
      );

      expect(found, isEmpty);
    });
  });

  group('addDependency', () {
    test('inserts in sorted position, not at the end', () {
      final out = PackageScaffold.addDependency(_businessPubspec, 'models');

      expect(out, contains('  models:\n    path: ../models\n'));
      expect(
        out.indexOf('models:'),
        allOf(
          greaterThan(out.indexOf('logging:')),
          lessThan(out.indexOf('storage:')),
        ),
        reason:
            '`pro_lints` turns on sort_pub_dependencies — an appended entry '
            'is a warning in a file the command has just written',
      );
    });

    test('sorts before every existing entry', () {
      final out = PackageScaffold.addDependency(_businessPubspec, 'aaa');

      expect(out.indexOf('aaa:'), lessThan(out.indexOf('async_redux:')));
    });

    test('sorts after every existing entry, above dev_dependencies', () {
      final out = PackageScaffold.addDependency(_businessPubspec, 'zzz');

      expect(
        out.indexOf('zzz:'),
        allOf(
          greaterThan(out.indexOf('storage:')),
          lessThan(out.indexOf('dev_dependencies:')),
        ),
        reason: 'the last entry is a two-line one — its span ends a line up',
      );
    });

    test('a pubspec with no dependencies block gets one', () {
      final out = PackageScaffold.addDependency('name: business\n', 'models');

      expect(out, contains('dependencies:'));
      expect(out, contains('../models'));
    });

    test('a source with no trailing newline still gets whole lines', () {
      // `_afterLine` answers `source.length` for the last line of such a file,
      // and a splice there ran the new entry onto the end of the old one.
      const noNewline = 'name: b\n\ndependencies:\n  logging: ^1.3.0';
      final out = PackageScaffold.addDependency(noNewline, 'zzz');

      expect(out, contains('  logging: ^1.3.0\n  zzz:\n'));
      expect(
        () => loadYaml(out),
        returnsNormally,
        reason: 'the result has to still be YAML',
      );
    });

    test('leaves a comment with the key it annotates', () {
      // The splice exists so prose survives; inserting *before* the next key
      // put the new entry between that key and the comment above it.
      const commented =
          'name: b\n'
          'dependencies:\n'
          '  async_redux: ^28.0.0\n'
          '  # keep this pinned\n'
          '  zzz: ^1.0.0\n';
      final out = PackageScaffold.addDependency(commented, 'models');

      expect(out, contains('# keep this pinned\n  zzz: ^1.0.0'));
    });

    test('an entry that sorts first goes above the block comment', () {
      const commented =
          'name: b\n'
          'dependencies:\n'
          '  # the whole block is pinned\n'
          '  zzz: ^1.0.0\n';
      final out = PackageScaffold.addDependency(commented, 'aaa');

      expect(out, contains('# the whole block is pinned\n  zzz: ^1.0.0'));
      expect(out.indexOf('aaa:'), lessThan(out.indexOf('# the whole')));
    });

    test('refuses a dependencies block that is not a map of names', () {
      // `addToWorkspace` refuses the same class of surprise. Overwriting would
      // take a list of dependencies away and exit 0.
      expect(
        () => PackageScaffold.addDependency(
          'name: b\ndependencies:\n  - a\n  - b\n',
          'models',
        ),
        throwsStateError,
      );
    });

    test('the sole dependency can be removed and re-added', () {
      const one =
          'name: b\n'
          'dependencies:\n'
          '  models:\n'
          '    path: ../models\n'
          '\n'
          'dev_dependencies:\n'
          '  x: ^1.0.0\n';
      final empty = PackageScaffold.removeDependency(one, 'models');

      expect(
        empty,
        isNot(contains('{}')),
        reason: 'an emptied block used to be re-serialised as a flow map',
      );
      expect(
        PackageScaffold.addDependency(empty, 'models'),
        one,
        reason: 'and then threw "No element" on the way back',
      );
    });

    test('removing the last entry keeps the blank line after the block', () {
      // Both entries are path dependencies, because that is the only shape
      // `addDependency` writes — the inverse is only claimed for what it wrote.
      const two =
          'name: b\n'
          'dependencies:\n'
          '  models:\n'
          '    path: ../models\n'
          '  zzz:\n'
          '    path: ../zzz\n'
          '\n'
          'dev_dependencies:\n'
          '  x: ^1.0.0\n';
      final out = PackageScaffold.removeDependency(two, 'zzz');

      expect(out, contains('path: ../models\n\ndev_dependencies:'));
      expect(
        PackageScaffold.addDependency(out, 'zzz'),
        two,
        reason: 'inverse in the last position too, not only mid-block',
      );
    });

    test('is idempotent — one already declared changes nothing', () {
      final once = PackageScaffold.addDependency(_businessPubspec, 'models');
      expect(PackageScaffold.addDependency(once, 'models'), once);
    });

    test('removeDependency is the inverse', () {
      final added = PackageScaffold.addDependency(_businessPubspec, 'models');
      expect(
        PackageScaffold.removeDependency(added, 'models'),
        _businessPubspec,
      );
    });

    test('removing one that is not declared changes nothing', () {
      expect(
        PackageScaffold.removeDependency(_businessPubspec, 'nope'),
        _businessPubspec,
      );
      expect(
        PackageScaffold.removeDependency('name: business\n', 'models'),
        'name: business\n',
      );
    });
  });

  group('add-package', () {
    test('writes a resolvable member and registers it', () async {
      prune('models');
      final r = await runInProcess(fx, [
        'add-package',
        'models',
        '--no-format',
      ]);
      expect(r.exitCode, 0, reason: r.stderr);

      for (final f in [
        'models/pubspec.yaml',
        'models/analysis_options.yaml',
        'models/build.yaml',
        'models/.gitignore',
      ]) {
        expect(
          File(fx.path(f)).existsSync(),
          isTrue,
          reason: '$f missing\n${r.stdout}',
        );
      }

      // The line that makes it a member rather than a directory that happens
      // to hold a pubspec.
      expect(fx.read('models/pubspec.yaml'), contains('resolution: workspace'));
      expect(fx.read('pubspec.yaml'), contains('- models'));

      // And the entry that makes it importable. Both of its dependents, not
      // just the obvious one: `http_client` declares `models` as well.
      expect(fx.read('business/pubspec.yaml'), contains('path: ../models'));
      expect(fx.read('http_client/pubspec.yaml'), contains('path: ../models'));
    });

    test('a package declares the optional ones it depends on', () async {
      // `models` first, so `http_client` is absent when models is added and
      // gets no edit — the order in which the second package has to declare the
      // first itself. The other order happened to work, which is why the
      // create/add round trip did not catch this.
      prune('models');
      prune('http_client');
      expect(
        (await runInProcess(fx, [
          'add-package',
          'models',
          '--no-format',
        ])).exitCode,
        0,
      );
      final r = await runInProcess(fx, [
        'add-package',
        'http_client',
        '--no-format',
      ]);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(
        fx.read('http_client/pubspec.yaml'),
        contains('path: ../models'),
        reason: 'add-retrofit writes `package:models/…` imports into it',
      );
    });

    test('and leaves out one that is not in the workspace', () async {
      // The inverse: `models` really is absent, so declaring it would point at
      // a directory that is not there and fail `pub get`.
      prune('models');
      prune('http_client');
      final r = await runInProcess(fx, [
        'add-package',
        'http_client',
        '--no-format',
      ]);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(fx.read('http_client/pubspec.yaml'), isNot(contains('../models')));
    });

    test('storage writes no build.yaml, because it runs no builder', () async {
      await runInProcess(fx, ['add-package', 'storage', '--no-format']);

      expect(File(fx.path('storage/pubspec.yaml')).existsSync(), isTrue);
      expect(File(fx.path('storage/build.yaml')).existsSync(), isFalse);
    });

    test('asking twice is not an error and writes nothing', () async {
      prune('models');
      await runInProcess(fx, ['add-package', 'models', '--no-format']);
      final again = await runInProcess(fx, [
        'add-package',
        'models',
        '--no-format',
      ]);

      expect(again.exitCode, 0, reason: again.stderr);
      expect(again.stdout, contains('already a workspace member'));
    });

    test('an unknown kind names the ones that exist', () async {
      final r = await runInProcess(fx, ['add-package', 'nope']);

      expect(r.exitCode, 70);
      expect(r.stderr, contains('models'));
      expect(r.stderr, contains('http_client'));
      expect(r.stderr, contains('storage'));
    });

    test('--dry-run leaves the workspace untouched', () async {
      prune('models');
      final before = fx.read('pubspec.yaml');
      final r = await runInProcess(fx, ['add-package', 'models', '--dry-run']);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(Directory(fx.path('models')).existsSync(), isFalse);
      expect(fx.read('pubspec.yaml'), before);
    });
  });

  group('the commands that write into an optional package', () {
    test(
      'add-model refuses when models is absent, and names the fix',
      () async {
        prune('models');
        final r = await runInProcess(fx, ['add-model', 'user', '--no-format']);

        expect(r.exitCode, 70);
        expect(r.stderr, contains('frx add-package models'));
        expect(
          Directory(fx.path('models')).existsSync(),
          isFalse,
          reason:
              'it used to write lib/user.dart into a directory that was '
              'not a package',
        );
      },
    );

    test('add-retrofit refuses when http_client is absent', () async {
      prune('http_client');
      final r = await runInProcess(fx, ['add-retrofit', 'auth', '--no-format']);

      expect(r.exitCode, 70);
      expect(r.stderr, contains('frx add-package http_client'));
      expect(Directory(fx.path('http_client')).existsSync(), isFalse);
    });

    test('add-model works once the package is there', () async {
      prune('models');
      expect(
        (await runInProcess(fx, [
          'add-package',
          'models',
          '--no-format',
        ])).exitCode,
        0,
      );
      final r = await runInProcess(fx, ['add-model', 'user', '--no-format']);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(File(fx.path('models/lib/user.dart')).existsSync(), isTrue);
    });
  });
}
