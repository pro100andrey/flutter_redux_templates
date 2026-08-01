import 'package:test/test.dart';
import 'package:tools/src/engine/diff.dart';

void main() {
  group('unifiedDiff', () {
    test('identical text yields no diff', () {
      expect(unifiedDiff('a\nb\n', 'a\nb\n', path: 'x'), isEmpty);
    });

    test('a single inserted line shows one +, with context and a header', () {
      const a = 'one\ntwo\nthree\n';
      const b = 'one\ntwo\ninserted\nthree\n';
      final d = unifiedDiff(a, b, path: 'lib/x.dart');
      expect(d, contains('--- a/lib/x.dart'));
      expect(d, contains('+++ b/lib/x.dart'));
      expect(d, contains('+inserted'));
      // Unchanged lines appear as context (space-prefixed).
      expect(d, contains(' two'));
      expect(d, contains(' three'));
      // The hunk header counts: 3 old lines, 4 new lines from line 1.
      expect(d, contains('@@ -1,3 +1,4 @@'));
    });

    test('a replaced line shows a - and a +', () {
      const a = 'alpha\nbeta\ngamma\n';
      const b = 'alpha\nBETA\ngamma\n';
      final d = unifiedDiff(a, b, path: 'x');
      expect(d, contains('-beta'));
      expect(d, contains('+BETA'));
      expect(d, contains(' alpha'));
      expect(d, contains(' gamma'));
    });

    test('distant edits split into separate hunks', () {
      final a = List.generate(30, (i) => 'line$i').join('\n');
      final b = a
          .replaceFirst('line1', 'line1-edited')
          .replaceFirst('line28', 'line28-edited');
      final d = unifiedDiff('$a\n', '$b\n', path: 'x');
      // Two hunk headers → two hunks (the edits are far apart).
      expect(RegExp(r'^@@ ', multiLine: true).allMatches(d).length, 2);
      expect(d, contains('+line1-edited'));
      expect(d, contains('+line28-edited'));
    });

    test('added lines against empty old text', () {
      final d = unifiedDiff('', 'new1\nnew2\n', path: 'x');
      expect(d, contains('@@ -1,0 +1,2 @@'));
      expect(d, contains('+new1'));
      expect(d, contains('+new2'));
    });
  });
}
