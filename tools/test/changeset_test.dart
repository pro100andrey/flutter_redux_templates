import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/engine/changeset.dart';

/// The planned-edits value every mutating command hands to [apply], and the
/// properties the nine hand-rolled write paths each had to get right alone.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('frx_changeset_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String at(String rel) => p.join(dir.path, rel);
  File file(String rel) => File(at(rel));
  Changeset applied(Changeset plan) => plan;

  group('describe', () {
    test('tells create from overwrite by looking at the disk', () {
      file('there.dart').writeAsStringSync('old');
      final plan = Changeset([
        WriteFile(at('fresh.dart'), 'a'),
        WriteFile(at('there.dart'), 'b'),
      ]);
      final out = plan.describe(from: dir.path);
      expect(out, contains('create  fresh.dart'));
      expect(out, contains('overwrite  there.dart'));
    });

    test('names every kind of change', () {
      final plan = Changeset([
        WriteFile(at('a.dart'), 'a'),
        EditFile(at('b.dart'), before: 'x', after: 'y'),
        DeleteFile(at('c.dart')),
        DeleteDirectory(at('sub')),
        MoveFile(from: at('d.dart'), path: at('e.dart')),
      ]);
      final out = plan.describe(from: dir.path);
      expect(out, contains('create  a.dart'));
      expect(out, contains('edit  b.dart'));
      expect(out, contains('delete  c.dart'));
      expect(out, contains('delete  sub${p.separator}'));
      expect(out, contains('move  d.dart → e.dart'));
    });
  });

  group('diff', () {
    test('a new file diffs against nothing', () {
      final plan = Changeset([WriteFile(at('a.dart'), 'hello\n')]);
      final out = plan.diff(from: dir.path);
      expect(out, contains('+++ b/a.dart'));
      expect(out, contains('+hello'));
    });

    test('an edit diffs against the before it carries, not the disk', () {
      // The file on disk is deliberately a third value: a command computes the
      // edit up front, and a later change in the same set may already have
      // rewritten the file by the time the diff is printed.
      file('a.dart').writeAsStringSync('on disk\n');
      final plan = Changeset([
        EditFile(at('a.dart'), before: 'was\n', after: 'now\n'),
      ]);
      final out = plan.diff(from: dir.path);
      expect(out, contains('-was'));
      expect(out, contains('+now'));
      expect(out, isNot(contains('on disk')));
    });

    test('deletes and moves contribute no text', () {
      final plan = Changeset([
        DeleteFile(at('a.dart')),
        DeleteDirectory(at('sub')),
        MoveFile(from: at('b.dart'), path: at('c.dart')),
      ]);
      expect(plan.diff(from: dir.path), isEmpty);
    });
  });

  group('collisions', () {
    test('an existing write target collides', () {
      file('there.dart').writeAsStringSync('old');
      final plan = Changeset([
        WriteFile(at('there.dart'), 'new'),
        WriteFile(at('fresh.dart'), 'new'),
      ]);
      expect(plan.collisions, [at('there.dart')]);
    });

    test('an edit of an existing file does not', () {
      // Editing something that exists is the whole point of an edit; counting
      // it as a collision would make every `add-field` demand --force.
      file('there.dart').writeAsStringSync('old');
      final plan = Changeset([
        EditFile(at('there.dart'), before: 'old', after: 'new'),
      ]);
      expect(plan.collisions, isEmpty);
    });
  });

  group('apply', () {
    test('writes, creating parent directories', () async {
      final plan = Changeset([WriteFile(at('deep/nested/a.dart'), 'x')]);
      final out = await apply(plan, format: false);
      expect(file('deep/nested/a.dart').readAsStringSync(), 'x');
      expect(out.written, [at('deep/nested/a.dart')]);
    });

    test('deletes run before writes', () async {
      // `add-substate --force` clears the folder it is about to repopulate.
      // Applying in declaration order would throw the new files away.
      file('sub/stale.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old');
      final plan = Changeset([
        WriteFile(at('sub/fresh.dart'), 'new'),
        DeleteDirectory(at('sub')),
      ]);
      await apply(plan, format: false);
      expect(file('sub/fresh.dart').readAsStringSync(), 'new');
      expect(file('sub/stale.dart').existsSync(), isFalse);
    });

    test('an edit replaces contents in place', () async {
      file('a.dart').writeAsStringSync('was');
      await apply(
        Changeset([EditFile(at('a.dart'), before: 'was', after: 'now')]),
        format: false,
      );
      expect(file('a.dart').readAsStringSync(), 'now');
    });

    test('a move relocates and reports the destination', () async {
      file('a.dart').writeAsStringSync('body');
      final out = await apply(
        Changeset([MoveFile(from: at('a.dart'), path: at('deep/b.dart'))]),
        format: false,
      );
      expect(file('a.dart').existsSync(), isFalse);
      expect(file('deep/b.dart').readAsStringSync(), 'body');
      expect(out.written, [at('deep/b.dart')]);
    });

    test('deleting what is not there is not an error', () async {
      final out = await apply(
        Changeset([DeleteFile(at('gone.dart')), DeleteDirectory(at('gone'))]),
        format: false,
      );
      expect(out.removed, isEmpty);
    });

    test('an empty plan does nothing and reports nothing', () async {
      final out = await apply(Changeset(), format: false);
      expect(out.written, isEmpty);
      expect(out.removed, isEmpty);
      expect(dir.listSync(), isEmpty);
    });
  });

  group('apply is atomic', () {
    // A write into a read-only *directory* is the injectable failure: it fails
    // where the applier has already done work, which is the only interesting
    // moment. Read-only is restored in `addTearDown` so the temp dir can be
    // removed even when an expectation fails mid-test.
    String sealed(String rel) {
      final dir = Directory(at(rel))..createSync(recursive: true);
      Process.runSync('chmod', ['a-w', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['u+w', dir.path]));
      return p.join(dir.path, 'blocked.dart');
    }

    /// The tree as `relative path → contents`, with directories as null.
    Map<String, List<int>?> snapshot() {
      final out = <String, List<int>?>{};
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        out[p.relative(e.path, from: dir.path)] = e is File
            ? e.readAsBytesSync()
            : null;
      }
      return out;
    }

    test(
      'a failed write leaves nothing created, edited, moved or deleted',
      () async {
        file('edited.dart').writeAsStringSync('original\n');
        file('moved.dart').writeAsStringSync('body\n');
        file('doomed/keep.dart')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('still here\n');
        file('gone.dart').writeAsStringSync('also here\n');
        final blocked = sealed('locked');

        final before = snapshot();

        final plan = Changeset([
          DeleteFile(at('gone.dart')),
          DeleteDirectory(at('doomed')),
          EditFile(at('edited.dart'), before: 'original\n', after: 'changed\n'),
          MoveFile(from: at('moved.dart'), path: at('deep/moved.dart')),
          WriteFile(at('deep/fresh.dart'), 'new\n'),
          // Fails here, with every other change already carried out.
          WriteFile(blocked, 'never\n'),
        ]);

        await expectLater(
          apply(plan, format: false),
          throwsA(
            isA<ApplyFailure>().having(
              (e) => e.rolledBack,
              'rolledBack',
              isTrue,
            ),
          ),
        );

        expect(snapshot(), before, reason: 'the tree is byte-identical');
      },
    );

    test('a directory the write created is taken away with it', () async {
      final blocked = sealed('locked');
      final plan = Changeset([
        WriteFile(at('brand/new/tree/a.dart'), 'x'),
        WriteFile(blocked, 'never'),
      ]);
      await expectLater(
        apply(plan, format: false),
        throwsA(isA<ApplyFailure>()),
      );
      expect(
        Directory(at('brand')).existsSync(),
        isFalse,
        reason: 'the whole created branch goes, not just the leaf file',
      );
    });

    test('an overwrite is restored, not merely removed', () async {
      file('there.dart').writeAsStringSync('mine\n');
      final blocked = sealed('locked');
      await expectLater(
        apply(
          Changeset([
            WriteFile(at('there.dart'), 'theirs\n'),
            WriteFile(blocked, 'never'),
          ]),
          format: false,
        ),
        throwsA(isA<ApplyFailure>()),
      );
      expect(file('there.dart').readAsStringSync(), 'mine\n');
    });

    test(
      'a forced re-creation that clears and repopulates still works',
      () async {
        // The order deletes-before-writes exists for this case, and atomicity
        // must not have quietly reordered it.
        file('sub/stale.dart')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('old');
        file('sub/empty/.keep').parent.createSync(recursive: true);
        await apply(
          Changeset([
            WriteFile(at('sub/fresh.dart'), 'new'),
            DeleteDirectory(at('sub')),
          ]),
          format: false,
        );
        expect(file('sub/fresh.dart').readAsStringSync(), 'new');
        expect(file('sub/stale.dart').existsSync(), isFalse);
      },
    );

    test(
      'a cleared folder comes back whole, empty subdirectories included',
      () async {
        file('sub/stale.dart')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('old\n');
        Directory(at('sub/nothing/inside')).createSync(recursive: true);
        final blocked = sealed('locked');
        final before = snapshot();

        await expectLater(
          apply(
            Changeset([
              DeleteDirectory(at('sub')),
              WriteFile(at('sub/fresh.dart'), 'new\n'),
              WriteFile(blocked, 'never'),
            ]),
            format: false,
          ),
          throwsA(isA<ApplyFailure>()),
        );

        expect(snapshot(), before);
      },
    );

    test('a failure at the very first step is still a failure', () async {
      // Nothing had been done yet, so there is nothing to unwind — the report
      // must still say the write did not happen rather than succeed silently.
      Process.runSync('chmod', ['a-w', dir.path]);
      addTearDown(() => Process.runSync('chmod', ['u+w', dir.path]));
      await expectLater(
        apply(Changeset([WriteFile(at('a.dart'), 'x')]), format: false),
        throwsA(
          isA<ApplyFailure>().having((e) => e.rolledBack, 'rolledBack', isTrue),
        ),
      );
    });

    test('a rollback that could not finish is named, not swallowed', () {
      // The one state that is neither applied nor untouched. Provoking it needs
      // the filesystem to change between a step and its undo, which no test can
      // arrange without racing the applier — so the reporting is pinned here
      // and the unwinding is pinned by the cases above.
      final partial = ApplyFailure(
        const FileSystemException('write failed'),
        StackTrace.empty,
        restoreErrors: const ['could not restore /repo/a.dart: read-only'],
      );
      expect(partial.rolledBack, isFalse);
      expect(partial.message, contains('rollback did not fully succeed'));
      expect(partial.message, contains('/repo/a.dart'));

      final clean = ApplyFailure(
        const FileSystemException('write failed'),
        StackTrace.empty,
      );
      expect(clean.rolledBack, isTrue);
      expect(clean.message, contains('nothing was written'));
    });
  });

  group('building a set', () {
    test('addIf skips a no-op, which is how "already wired" is expressed', () {
      final plan = applied(
        Changeset()
          ..add(WriteFile(at('a.dart'), 'x'))
          ..addIf(null)
          ..addIf(EditFile(at('b.dart'), before: 'p', after: 'q')),
      );
      expect(plan.changes, hasLength(2));
      expect(plan.isNotEmpty, isTrue);
    });

    test('formattable excludes what will not exist afterwards', () {
      final plan = Changeset([
        WriteFile(at('a.dart'), 'x'),
        EditFile(at('b.dart'), before: 'p', after: 'q'),
        DeleteFile(at('c.dart')),
        DeleteDirectory(at('sub')),
        MoveFile(from: at('d.dart'), path: at('e.dart')),
      ]);
      expect(plan.formattable, [at('a.dart'), at('b.dart'), at('e.dart')]);
    });
  });
}
