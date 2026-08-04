import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/audit/checks.dart';
import 'package:tools/src/audit/finding.dart';
import 'package:tools/src/audit/text_bytes.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

import 'support/fixture.dart';

/// Every tracked source file in this repository can be searched.
///
/// A test and not only a `doctor` check, for two reasons. The audit walks a
/// *project*, and `tools/` — the CLI's own source, where this failed — is in no
/// project: it is excluded from the template on purpose. And the audit cannot
/// see `.claude/`, the `.ts` of the extension, or the shell hook, and a NUL
/// hides any of those exactly as well.
///
/// What it guards, measured: `frx_workspace.dart` carried one NUL byte, written
/// as a memo-key separator. Legal Dart, invisible in an editor, survived `dart
/// format`. But `grep`, `git grep` and ripgrep classify a file holding a NUL as
/// binary and skip it, so `notSubstateDirs`, `isSubstateDir`, `packageRootOf`
/// and `_marker` returned no hits anywhere in the repository — the module that
/// owns the monorepo's layout was absent from every search. `dart analyze` was
/// clean, 690 tests passed, and the only symptom was an architecture review
/// undercounting because its own greps came back empty.
void main() {
  final repoRoot = p.dirname(Directory.current.absolute.path);

  /// Extensions whose files are meant to be read by a human and searched by a
  /// tool. An allowlist and not a binary-file denylist: the template ships
  /// fonts, icons and platform blobs, and a new one of those must not be able
  /// to turn this test red.
  const searchable = {
    '.dart', '.ts', '.js', '.json', '.yaml', '.yml', '.md', //
    '.sh', '.html', '.css', '.xml', '.kt', '.swift', '.gradle', '.podspec',
  };

  List<String> trackedFiles() {
    // `--others --exclude-standard` as well as the index: a file that has not
    // been committed yet is exactly when this is worth knowing. Proven the
    // first time it ran — the guard's own test file was written with a literal
    // NUL, and tracked-only would have shipped it.
    final res = Process.runSync('git', [
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ], workingDirectory: repoRoot);
    expect(res.exitCode, 0, reason: 'git ls-files failed: ${res.stderr}');
    return (res.stdout as String)
        .split('\u0000')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  test('no tracked source file is invisible to search', () {
    final offenders = <String>[];
    for (final rel in trackedFiles()) {
      if (!searchable.contains(p.extension(rel))) continue;
      final file = File(p.join(repoRoot, rel));
      // Tracked but absent happens mid-rebase and is not this test's subject.
      if (!file.existsSync()) continue;
      final bad = unsearchableIn(file.readAsBytesSync());
      if (bad != null) {
        offenders.add('$rel ${describeUnsearchable(bad.kind, bad.offset)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These files compile and are skipped by every search:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the rule names the byte and where it is', () {
    // The report has to be actionable on a file no editor will show you the
    // problem in, so the offset is the whole value of the finding.
    final withNul = [...utf8.encode('abc'), 0, ...utf8.encode('def')];
    expect(unsearchableIn(withNul)?.kind, Unsearchable.nulByte);
    expect(unsearchableIn(withNul)?.offset, 3);
    expect(describeUnsearchable(Unsearchable.nulByte, 3), contains('offset 3'));

    // Invalid UTF-8: a lone continuation byte.
    expect(
      unsearchableIn([...utf8.encode('ok'), 0x80])?.kind,
      Unsearchable.notUtf8,
    );

    expect(unsearchableIn(utf8.encode('plain ascii')), isNull);
    // Deliberately allowed: text this repository is full of. A rule that fired
    // on an em dash or a Cyrillic comment would be worse than no rule — and
    // `utf8.encode`, not `codeUnits`, because the subject is bytes on disk.
    expect(unsearchableIn(utf8.encode('em — dash, кириллица, 🎉')), isNull);
    // Tabs and newlines are control bytes and are not the subject.
    expect(unsearchableIn(utf8.encode('a\tb\r\nc')), isNull);
  });

  group('the audit half — what a created project gets', () {
    late Fixture fx;

    setUp(() => fx = Fixture.create());
    tearDown(() => fx.dispose());

    List<Finding> run() {
      final found = <Finding>[];
      checkSourceText(FrxWorkspace(fx.root), found);
      return found;
    }

    test('a clean project says nothing', () => expect(run(), isEmpty));

    test('a file that cannot be decoded does not take the audit down', () {
      // The failure this closes, measured: two stray bytes in one source made
      // `readAsStringSync` throw inside `checkGeneratedParts`, and `frx doctor`
      // died with an unhandled `FileSystemException` — losing every finding
      // collected so far, including this check's report of that exact file.
      //
      // Running `source-text` first did not help, and the comment that said it
      // did was wrong: `audit()` returns one list after the loop, so an
      // exception discards it whole. The guard is per-check, not positional.
      fx.file('business/lib/undecodable.dart')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xfe, ...utf8.encode('\nclass X {}\n')]);

      final found = audit(FrxWorkspace(fx.root));

      expect(
        found.where((f) => f.message.contains('undecodable.dart')),
        isNotEmpty,
        reason: 'the file has to be named, not merely survived',
      );
      expect(
        found.where((f) => f.message.contains('could not run')),
        isNotEmpty,
        reason:
            'and the check that hit it has to say so — a check that died is '
            'not a clean tree',
      );
    });

    test('an unsearchable source is reported, with its offset', () {
      final file = fx.file('business/lib/redux/thing.dart')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([...utf8.encode('class Thing {}\n'), 0]);

      final found = run();
      expect(found, hasLength(1));
      expect(found.single.message, contains('offset 15'));
      expect(found.single.file, file.path);
      expect(
        found.single.severity,
        Severity.warn,
        reason:
            'the file compiles and the project runs — this is about finding '
            'it, so it does not fail a build',
      );
    });
  });
}
