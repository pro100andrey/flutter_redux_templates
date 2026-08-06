import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';

/// One place that reads and parses Dart, so the same file is not opened four
/// times in one command — and so "does this have to parse cleanly?" is answered
/// by a rule rather than by whichever call site was written first.
void main() {
  late Directory root;
  late SourceIndex index;

  setUp(() {
    root = Directory.systemTemp.createTempSync('frx_index_');
    index = SourceIndex();
  });
  tearDown(() => root.deleteSync(recursive: true));

  File put(String rel, String content) => File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  group('parsing', () {
    test('reads and parses a file once, however often it is asked for', () {
      final f = put('a.dart', 'class A {}\n');
      for (var i = 0; i < 4; i++) {
        expect(index.unitFor(f).declarations, hasLength(1));
      }
      expect(index.parses, 1);
    });

    test('two files are two parses', () {
      index
        ..unitFor(put('a.dart', 'class A {}\n'))
        ..unitFor(put('b.dart', 'class B {}\n'));
      expect(index.parses, 2);
    });

    test('the same file by a different path spelling is one parse', () {
      put('sub/a.dart', 'class A {}\n');
      index
        ..unitFor(File(p.join(root.path, 'sub', 'a.dart')))
        ..unitFor(File(p.join(root.path, 'sub', '..', 'sub', 'a.dart')));
      expect(index.parses, 1);
    });
  });

  group('strictness', () {
    // The rule the tier had no rule for: a file about to be edited must parse
    // cleanly, because an edit here is a character offset computed against the
    // tree; a file only being reported on must not, because one unparseable
    // file in someone's repo must not take the whole audit down.
    final broken = 'class A { void f( }\n';

    test('a file that does not parse still yields a tree to report on', () {
      expect(index.unitFor(put('a.dart', broken)), isNotNull);
    });

    test('but is refused to a caller computing edit offsets', () {
      // StateError is the convention the runner renders as `✗ msg`, exit 70 —
      // an ArgumentError here escaped as a stack trace for the most user-facing
      // failure there is.
      expect(
        () => index.unitToEdit(put('a.dart', broken)),
        throwsA(isA<StateError>()),
      );
    });

    test('a clean file is handed to either', () {
      final f = put('a.dart', 'class A {}\n');
      expect(index.unitToEdit(f), same(index.unitFor(f)));
    });
  });

  group('the text pre-filter', () {
    test('does not parse on a miss — the whole point of it', () {
      final f = put('a.dart', 'class A {}\n');
      expect(index.unitIf(f, (s) => s.contains('Select')), isNull);
      expect(index.parses, 0);
    });

    test('parses on a hit', () {
      final f = put('a.dart', 'extension type SelectA(int _s) {}\n');
      expect(index.unitIf(f, (s) => s.contains('Select')), isNotNull);
      expect(index.parses, 1);
    });

    test('a predicate, so a filter can be an and, an or, or either', () {
      // What the placement rules actually ask: `extension` AND `Select`, or
      // `@RoutePage`. A list of needles could express neither.
      final f = put('a.dart', 'extension type SelectA(int _s) {}\n');
      expect(
        index.unitIf(f, (s) => s.contains('extension') && s.contains('Select')),
        isNotNull,
      );
      expect(
        index.unitIf(f, (s) => s.contains('extension') && s.contains('Route')),
        isNull,
      );
    });

    test('a miss then a hit on the same file is one parse', () {
      final f = put('a.dart', 'extension type SelectA(int _s) {}\n');
      index
        ..unitIf(f, (s) => s.contains('nope'))
        ..unitIf(f, (s) => s.contains('Select'))
        ..unitFor(f);
      expect(index.parses, 1);
    });
  });

  group('listing', () {
    test('finds hand-written Dart and skips generated output', () {
      put('lib/a.dart', '');
      put('lib/deep/b.dart', '');
      put('lib/a.freezed.dart', '');
      put('lib/a.g.dart', '');
      put('lib/a.gr.dart', '');
      put('lib/a.g.theme.dart', '');
      put('lib/notes.md', '');
      expect(
        index
            .filesUnder(Directory(p.join(root.path, 'lib')))
            .map((f) => p.basename(f.path)),
        unorderedEquals(['a.dart', 'b.dart']),
      );
    });

    test('hands back generated output when asked — the carcass check', () {
      put('lib/a.dart', '');
      put('lib/a.freezed.dart', '');
      expect(
        index
            .filesUnder(
              Directory(p.join(root.path, 'lib')),
              includeGenerated: true,
            )
            .map((f) => p.basename(f.path)),
        unorderedEquals(['a.dart', 'a.freezed.dart']),
      );
    });

    test('lists immediate subdirectories', () {
      put('redux/log_in/models/x.dart', '');
      put('redux/session/x.dart', '');
      put('redux/loose.dart', '');
      expect(
        index
            .directoriesIn(Directory(p.join(root.path, 'redux')))
            .map((d) => p.basename(d.path)),
        unorderedEquals(['log_in', 'session']),
      );
    });

    test('a directory created after a miss is still found', () {
      final dir = Directory(p.join(root.path, 'flows'));
      expect(index.filesUnder(dir), isEmpty);
      put('flows/a.dart', '');
      expect(index.filesUnder(dir), hasLength(1));
    });

    test('a directory that is not there is empty, not an error', () {
      expect(index.filesUnder(Directory(p.join(root.path, 'nope'))), isEmpty);
    });
  });

  group('a rewritten file', () {
    test('is re-parsed when it grew', () {
      final f = put('a.dart', 'class A {}\n');
      expect(index.unitFor(f).declarations, hasLength(1));
      f.writeAsStringSync('class A {}\nclass B {}\n');
      expect(index.unitFor(f).declarations, hasLength(2));
    });

    test('is re-parsed when it did not, however fast the rewrite', () {
      // The case that killed keying on modification time and length: a
      // same-length rewrite inside one timestamp tick served the stale tree
      // about half the time. This is the read-compute-write-reread shape a
      // batch has.
      final f = put('a.dart', 'class A {}\n');
      for (var i = 0; i < 200; i++) {
        f.writeAsStringSync(i.isEven ? 'class B {}\n' : 'class A {}\n');
        expect(
          index.unitFor(f).declarations.single.toSource(),
          contains(i.isEven ? 'B' : 'A'),
          reason: 'rewrite #\$i',
        );
      }
    });

    test('that did not change at all is not re-parsed', () {
      final f = put('a.dart', 'class A {}\n');
      index.unitFor(f);
      f.writeAsStringSync('class A {}\n');
      index.unitFor(f);
      expect(index.parses, 1);
    });
  });
}
