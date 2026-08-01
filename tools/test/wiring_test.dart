import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/commands/wiring.dart';
import 'package:tools/src/redux/ast_edit.dart';
import 'package:tools/src/util/console.dart';

/// An [EditOutcome] with no source module behind it. The point of naming the
/// shape is that the derivations do not care which one produced it.
class _Outcome implements EditOutcome {
  const _Outcome({
    required this.source,
    this.changes = const [],
    this.unchanged = false,
  });

  @override
  final String source;
  @override
  final List<String> changes;
  @override
  final bool unchanged;
}

void main() {
  late Directory dir;
  late File file;
  late File other;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('frx_wiring_');
    file = File('${dir.path}/a.dart')..writeAsStringSync('before a\n');
    other = File('${dir.path}/b.dart')..writeAsStringSync('before b\n');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String narrating(void Function() body) {
    final captured = CapturedConsole();
    withConsole(captured, body);
    return captured.output;
  }

  group('the change', () {
    test('an edit carries the file as it is now, and the edited source', () {
      final w = Wiring(
        file,
        const _Outcome(source: 'after a\n', changes: ['a field']),
        heading: 'A:',
      );
      final edit = w.edit!;
      expect(edit.path, file.path);
      expect(edit.before, 'before a\n');
      expect(edit.after, 'after a\n');
    });

    test('an unchanged outcome is no change at all', () {
      final w = Wiring(
        file,
        const _Outcome(source: 'before a\n', unchanged: true),
        heading: 'A:',
        skipped: 'already there.',
      );
      expect(w.edit, isNull);
    });

    test('a caller with no block to print gets the change on its own', () {
      // What the audit's orphan fixer wants: it writes files and says one line
      // about the folder, never a block per file.
      const outcome = _Outcome(source: 'after a\n', changes: ['a getter']);
      expect(outcome.editTo(file)?.after, 'after a\n');
      expect(const _Outcome(source: 'x', unchanged: true).editTo(file), isNull);
    });

    test('the list keeps declared order and drops what was already wired', () {
      final wiring = [
        Wiring(
          file,
          const _Outcome(source: 'x', unchanged: true),
          heading: 'A:',
          skipped: 's',
        ),
        Wiring(other, const _Outcome(source: 'after b\n'), heading: 'B:'),
      ];
      expect(wiring.edits.map((e) => e.path), [other.path]);
    });
  });

  group('the heading', () {
    test('a file named by its path carries the trailing colon', () {
      // The convention three call sites used to spell out, `p.relative` and all.
      final out = narrating(
        () => Wiring.at(
          file,
          const _Outcome(source: 'x', changes: ['one']),
        ).narrate(),
      );
      expect(out.split('\n').first, '${p.relative(file.path)}:');
    });

    test('a file named by what it is carries its path in brackets', () {
      final out = narrating(
        () => Wiring.of(
          'Router',
          file,
          const _Outcome(source: 'x', changes: ['one']),
        ).narrate(),
      );
      expect(out.split('\n').first, 'Router (${p.relative(file.path)}):');
    });
  });

  group('the report', () {
    test('a change prints the heading and one line per change', () {
      final out = narrating(
        () => Wiring(
          file,
          const _Outcome(source: 'x', changes: ['import …;', 'field logIn']),
          heading: 'AppState (a.dart):',
        ).narrate(),
      );
      expect(out, 'AppState (a.dart):\n  + import …;\n  + field logIn\n');
    });

    test('an unwiring lists what went away, not what arrived', () {
      // `remove` had its own copy of this block for one character.
      final out = narrating(
        () => Wiring(
          file,
          const _Outcome(source: 'x', changes: ['field logIn']),
          heading: 'AppState (a.dart):',
          way: WiringWay.unwired,
        ).narrate(),
      );
      expect(out, 'AppState (a.dart):\n  - field logIn\n');
    });

    test('a skip prints the heading and one bullet', () {
      final out = narrating(
        () => Wiring(
          file,
          const _Outcome(source: 'x', unchanged: true),
          heading: 'AppState (a.dart):',
          skipped: 'field "logIn" already present — wiring skipped.',
        ).narrate(),
      );
      expect(
        out,
        'AppState (a.dart):\n'
        '  • field "logIn" already present — wiring skipped.\n',
      );
    });

    test('a skip that names the artifact drops the heading', () {
      // `add-nav` says "LogInPage already has `onTapHome`", which the path above
      // it would not make any clearer.
      final out = narrating(
        () => Wiring(
          file,
          const _Outcome(source: 'x', unchanged: true),
          heading: 'app/lib/connectors/log_in_page_connector.dart:',
          skipped: 'LogInPage already has `onTapHome` — nothing to do.',
          headingWhenSkipped: false,
        ).narrate(),
      );
      expect(out, '  • LogInPage already has `onTapHome` — nothing to do.\n');
    });

    test('no skip line means silence, not an empty heading', () {
      final w = Wiring(
        file,
        const _Outcome(source: 'x', unchanged: true),
        heading: 'A:',
      );
      expect(w.silent, isTrue);
      expect(narrating(w.narrate), isEmpty);
    });

    test('the list puts one blank line after each block', () {
      final out = narrating(
        () => [
          Wiring(
            file,
            const _Outcome(source: 'x', changes: ['one']),
            heading: 'A:',
          ),
          Wiring(
            other,
            const _Outcome(source: 'y', unchanged: true),
            heading: 'B:',
            skipped: 'already there.',
          ),
        ].narrate(),
      );
      expect(out, 'A:\n  + one\n\nB:\n  • already there.\n\n');
    });

    test('a silent block leaves no gap where its report would have been', () {
      // The spacing regression this catches is invisible in a diff of the code
      // and obvious in a terminal: a blank line reported for a file nothing was
      // said about.
      final out = narrating(
        () => [
          Wiring(
            file,
            const _Outcome(source: 'x', changes: ['one']),
            heading: 'A:',
          ),
          Wiring(
            other,
            const _Outcome(source: 'y', unchanged: true),
            heading: 'B:',
          ),
        ].narrate(),
      );
      expect(out, 'A:\n  + one\n\n');
    });
  });
}
