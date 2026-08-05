import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/scaffold/package_scaffold.dart';

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
