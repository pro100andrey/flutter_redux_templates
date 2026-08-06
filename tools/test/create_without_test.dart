import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/scaffold/package_scaffold.dart';
import 'package:tools/src/util/console.dart';
import 'package:yaml/yaml.dart';

import 'support/in_process.dart';

/// `frx create --without <kind>`, and its agreement with `add-package`.
///
/// The command these exercise unpacks the whole embedded template, so each
/// creation is ~500 files into a temp directory. That is why they live in their
/// own suite and why there are six of them rather than sixteen: what is under
/// test is the *omission*, and the unpack it rides on is covered by
/// `template_freshness_test.dart`.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('frx_create_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs `frx create <name>` into a fresh directory under [tmp] and returns
  /// its root.
  ///
  /// The runner is called directly rather than through `runInProcessAt`, which
  /// appends `--root`: `create` is the one command that takes none, because it
  /// makes the repository the others act on.
  Future<({int exitCode, String stdout, String stderr, String root})> create(
    String name,
    List<String> args, {
    String? at,
  }) async {
    final target = p.join(tmp.path, at ?? name);
    final captured = CapturedConsole();
    final code = await withConsole(
      captured,
      () => FrxRunner().runFrx(['create', name, '--target', target, ...args]),
    );
    return (
      exitCode: code,
      stdout: captured.output,
      stderr: captured.errors,
      root: target,
    );
  }

  String read(String root, String relative) =>
      File(p.join(root, relative)).readAsStringSync();

  group('--without', () {
    test('the package is gone, and so is every reference to it', () async {
      final r = await create('demo_a', ['--without', 'http_client']);
      expect(r.exitCode, 0, reason: r.stderr);

      expect(Directory(p.join(r.root, 'http_client')).existsSync(), isFalse);
      expect(
        read(r.root, 'pubspec.yaml'),
        isNot(contains('- http_client')),
        reason: 'a workspace entry pointing at nothing fails `pub get`',
      );
      expect(
        read(r.root, 'business/pubspec.yaml'),
        isNot(contains('http_client')),
        reason: 'a path dependency on a directory that is not there does too',
      );

      // The other members are untouched — omission is not a synonym for
      // "the optional ones".
      expect(Directory(p.join(r.root, 'models')).existsSync(), isTrue);
      expect(read(r.root, 'pubspec.yaml'), contains('- models'));
    });

    test('two at once, including one the other depends on', () async {
      final r = await create('demo_b', ['--without', 'models,http_client']);
      expect(r.exitCode, 0, reason: r.stderr);

      expect(Directory(p.join(r.root, 'models')).existsSync(), isFalse);
      expect(Directory(p.join(r.root, 'http_client')).existsSync(), isFalse);

      final root = read(r.root, 'pubspec.yaml');
      expect(root, isNot(contains('- models')));
      expect(root, isNot(contains('- http_client')));

      final business = read(r.root, 'business/pubspec.yaml');
      expect(business, isNot(contains('models')));
      expect(business, isNot(contains('http_client')));

      // `http_client/pubspec.yaml` declares `models`, and dropping `models`
      // edits it. That edit must not resurrect the directory the other
      // omission deleted.
      expect(
        Directory(p.join(r.root, 'http_client')).existsSync(),
        isFalse,
        reason: 'the dependency edit was written back into a deleted package',
      );
    });

    test('refuses a package something imports, and names the files', () async {
      final r = await create('demo_c', ['--without', 'storage']);

      expect(r.exitCode, 70);
      expect(r.stderr, contains('storage'));
      expect(r.stderr, contains('business/lib/redux/store.dart'));
      expect(
        Directory(r.root).existsSync(),
        isFalse,
        reason: 'the refusal comes before the unpack — nothing is written',
      );
    });

    test('an unknown package names the ones that exist', () async {
      final r = await create('demo_d', ['--without', 'nope']);

      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('http_client'));
    });

    test('--dry-run counts what would be kept and writes nothing', () async {
      final full = await create('demo_e', ['--dry-run']);
      final pruned = await create('demo_f', [
        '--dry-run',
        '--without',
        'http_client',
      ]);

      expect(full.exitCode, 0, reason: full.stderr);
      expect(pruned.exitCode, 0, reason: pruned.stderr);
      expect(Directory(pruned.root).existsSync(), isFalse);
      expect(pruned.stdout, contains('without http_client'));

      expect(
        _fileCount(pruned.stdout),
        lessThan(_fileCount(full.stdout)),
        reason:
            'the report counted the files it was about to leave out\n'
            '${pruned.stdout}',
      );
    });
  });

  test('add-package puts back the dependencies --without took away', () async {
    // The round trip that keeps `PackageKind.dependents` honest: one side
    // withdraws the dependency, the other declares it, and nothing but a test
    // makes them agree on which pubspec — or on where in it, which is why
    // `addDependency` sorts rather than appends.
    //
    // Same project name into two directories, so the two trees differ in
    // nothing but the omission.
    final reference = await create('demo', const [], at: 'reference');
    final roundTrip = await create('demo', [
      '--without',
      'models',
    ], at: 'round_trip');
    expect(reference.exitCode, 0, reason: reference.stderr);
    expect(roundTrip.exitCode, 0, reason: roundTrip.stderr);

    final added = await runInProcessAt(roundTrip.root, [
      'add-package',
      'models',
      '--no-format',
    ]);
    expect(added.exitCode, 0, reason: added.stderr);

    // Byte-identical, including the position in the sorted `dependencies:`
    // block. Every dependent, not just the one a reader would think of:
    // `http_client` declares `models` too.
    for (final dependent in const [
      'business/pubspec.yaml',
      'http_client/pubspec.yaml',
    ]) {
      expect(
        read(roundTrip.root, dependent),
        read(reference.root, dependent),
        reason: '$dependent did not come back the way it left',
      );
    }

    // What `--without` withdraws is derived from the tree; what `add-package`
    // declares is the catalogue. They are two answers to one question, and only
    // this keeps them from drifting apart — a package the catalogue has not
    // heard of would be left pointing at a directory `--without` deleted.
    for (final kind in PackageKind.values) {
      expect(
        _declarersOf(kind.dir, reference.root),
        kind.dependents,
        reason:
            'PackageKind.${kind.name}.dependents is not what the template '
            'declares — `add-package ${kind.dir}` would not restore it',
      );
    }

    // The root pubspec regains the member, but not its **place** in the list:
    // that list is in dependency order — models, storage, localization,
    // http_client, … — which is a fact about the template and not one
    // `add-package` can re-derive. It appends, and pub does not care.
    expect(read(roundTrip.root, 'pubspec.yaml'), contains('- models'));
  });
}

/// The workspace members under [root] whose pubspec declares `path: ../[dir]`.
Set<String> _declarersOf(String dir, String root) {
  final found = <String>{};
  for (final entity in Directory(root).listSync()) {
    if (entity is! Directory) continue;
    final pubspec = File(p.join(entity.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;

    final deps =
        (loadYaml(pubspec.readAsStringSync()) as YamlMap)['dependencies'];
    if (deps is! YamlMap) continue;
    if (deps[dir] case final YamlMap entry when entry['path'] == '../$dir') {
      found.add(p.basename(entity.path));
    }
  }
  return found;
}

/// The `N files · …` count out of a `create` report.
int _fileCount(String stdout) {
  final match = RegExp(r'(\d+) files').firstMatch(stdout);
  if (match == null) throw StateError('no file count in:\n$stdout');
  return int.parse(match.group(1)!);
}
