import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/skills/skill_gen.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// `frx update-skills` — the one derived artifact a generated project could not
/// re-derive, and the ownership manifest that lets it be swept safely.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  Directory skills() => Directory(fx.path('.claude/skills'));

  File skill(String name) => File(fx.path('.claude/skills/$name/SKILL.md'));

  test(
    'writes every skill and the manifest into a project with none',
    () async {
      final r = await runInProcess(fx, ['update-skills', '--no-format']);
      expect(r.exitCode, 0, reason: r.stderr);

      final generated = SkillGen.generate();
      expect(generated, isNotEmpty);
      for (final path in generated.keys) {
        expect(
          File(fx.path(path)).existsSync(),
          isTrue,
          reason: '$path was not written',
        );
      }

      final owned = SkillGen.ownedIn(skills());
      expect(owned.version, SkillGen.version);
      expect(owned.directories, SkillGen.directories());
    },
  );

  test('running it twice writes nothing the second time', () async {
    await runInProcess(fx, ['update-skills', '--no-format']);
    final again = await runInProcess(fx, ['update-skills', '--no-format']);

    expect(again.exitCode, 0, reason: again.stderr);
    expect(again.stdout, contains('Already current'));
  });

  test('rewrites a skill that a newer frx says differently', () async {
    await runInProcess(fx, ['update-skills', '--no-format']);
    final target = skill('frx-doctor')..writeAsStringSync('stale\n');

    final r = await runInProcess(fx, ['update-skills', '--no-format']);

    expect(r.exitCode, 0, reason: r.stderr);
    expect(target.readAsStringSync(), isNot('stale\n'));
    expect(target.readAsStringSync(), contains('name: frx-doctor'));
  });

  group('the manifest decides what may be swept', () {
    test('a skill frx no longer generates is removed', () async {
      await runInProcess(fx, ['update-skills', '--no-format']);

      // The state a renamed or retired command leaves: on disk, and listed as
      // frx's own by the run that wrote it.
      final retired = Directory(fx.path('.claude/skills/frx-gone'))
        ..createSync(recursive: true);
      File(p.join(retired.path, 'SKILL.md')).writeAsStringSync('# gone\n');
      final manifest = File(p.join(skills().path, SkillGen.manifestName));
      manifest.writeAsStringSync('${manifest.readAsStringSync()}frx-gone\n');

      final r = await runInProcess(fx, ['update-skills', '--no-format']);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(retired.existsSync(), isFalse);
    });

    test("a skill the project wrote itself is left alone", () async {
      await runInProcess(fx, ['update-skills', '--no-format']);

      // Not in the manifest, so not frx's to remove — whatever it is called.
      // The prune this replaces matched on a `frx-` prefix, which would have
      // taken this one and left `wiring-artifacts` behind.
      final theirs = Directory(fx.path('.claude/skills/frx-house-style'))
        ..createSync(recursive: true);
      final file = File(p.join(theirs.path, 'SKILL.md'))
        ..writeAsStringSync('# ours\n');

      final r = await runInProcess(fx, ['update-skills', '--no-format']);

      expect(r.exitCode, 0, reason: r.stderr);
      expect(file.readAsStringSync(), '# ours\n');
    });

    test('every generated skill is listed, not only the frx- ones', () {
      // `wiring-artifacts` and `data-driven-widgets` were swept by nothing:
      // the prefix prune knew `frx-` and `asyncredux-`, and by then the tree
      // had four kinds in it.
      expect(
        SkillGen.directories(),
        containsAll(['wiring-artifacts', 'asyncredux-in-this-template']),
      );
      expect(
        SkillGen.manifest().split('\n'),
        containsAll(SkillGen.directories()),
      );
    });
  });

  group('doctor', () {
    Future<String> report() async =>
        (await runInProcess(fx, ['doctor'])).stdout;

    test('says nothing about a project that has never had skills', () async {
      expect(await report(), isNot(contains('.claude/skills')));
    });

    test('reports a hand-edited skill, and names the remedy', () async {
      await runInProcess(fx, ['update-skills', '--no-format']);
      skill('frx-doctor').writeAsStringSync('edited by hand\n');

      final json = (await runInProcess(fx, ['doctor', '--json'])).stdout;

      expect(json, contains('.claude/skills'));
      expect(json, contains('"fix":"skills"'));
    });

    test('--fix brings them back', () async {
      await runInProcess(fx, ['update-skills', '--no-format']);
      skill('frx-doctor').writeAsStringSync('edited by hand\n');

      await runInProcess(fx, ['doctor', '--fix']);

      // Not the exit code: `--fix` also runs build_runner for the missing
      // generated parts a fixture necessarily has, and a fixture has no
      // resolution for it to run against. What is under test is that the
      // remedy reached the skills, which it does last and independently.
      expect(
        skill('frx-doctor').readAsStringSync(),
        contains('name: frx-doctor'),
      );
    });
  });
}
