import 'dart:convert';

import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// A file frx could not parse should say so.
///
/// The reader tier is tolerant of unparseable source on purpose — one broken
/// file must not take a whole read down — and the tolerance was silent, which
/// is worse than the crash it replaced: a node built from a recovered tree
/// answers confidently, and nothing said which answers came from a file that
/// does not compile.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  /// An action whose reducer is missing its closing brace.
  void breakAnAction() {
    fx.file('business/lib/redux/log_in/actions/broken_action.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
class BrokenAction extends Action {
  @override
  AppState reduce() {
    return state;
''');
  }

  group('the index is the one that knows', () {
    test('a recovered file is listed, a clean one is not', () {
      breakAnAction();
      final index = SourceIndex();
      withSourceIndex(index, () {
        index.unitFor(fx.file('business/lib/redux/app_state.dart'));
        expect(index.recovered, isEmpty);
        index.unitFor(
          fx.file('business/lib/redux/log_in/actions/broken_action.dart'),
        );
      });
      expect(index.recovered.map((f) => f.path.split('/').last), [
        'broken_action.dart',
      ]);
    });

    test('a file it never parsed is not listed', () {
      // The bound the audit's finding is scoped to: a file nothing read is a
      // file nothing claimed anything about.
      breakAnAction();
      final index = SourceIndex();
      withSourceIndex(index, () {
        index.sourceOf(
          fx.file('business/lib/redux/log_in/actions/broken_action.dart'),
        );
      });
      expect(index.recovered, isEmpty);
    });
  });

  test('the graph declares it rather than modelling it silently', () async {
    breakAnAction();
    final r = await runInProcess(fx, ['graph', '--json']);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    final gaps = ((jsonDecode(r.stdout) as Map)['unresolved'] as List)
        .cast<Map<String, Object?>>()
        .where((u) => u['kind'] == 'unparsed-file');
    expect(gaps, hasLength(1));
    expect('${gaps.single['why']}', contains('broken_action.dart'));
    // Owned by the file: the gap is in everything read from there, not in one
    // edge, so there is no node to blame it on.
    expect('${gaps.single['owner']}', startsWith('file:'));
  });

  test('a clean workspace gains no entry', () async {
    final r = await runInProcess(fx, ['graph', '--json']);
    expect(
      ((jsonDecode(r.stdout) as Map)['unresolved'] as List)
          .cast<Map<String, Object?>>()
          .where((u) => u['kind'] == 'unparsed-file'),
      isEmpty,
    );
  });

  test('the audit warns about one it read, and never errors', () async {
    // A file the placement sweep's text pre-filter selects, so the audit really
    // does parse it. An action file it never parses is the graph's to report —
    // the bound this finding is deliberately scoped to.
    fx.file('ui/lib/stray.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('extension type SelectStray(AppState _state) {\n');

    final r = await runInProcess(fx, ['doctor', '--json']);
    final about = ((jsonDecode(r.stdout) as Map)['findings'] as List)
        .cast<Map<String, Object?>>()
        .where((f) => '${f['message']}'.contains('does not parse'));
    expect(about, hasLength(1), reason: r.stdout);
    expect('${about.single['message']}', contains('stray.dart'));
    expect(
      about.single['severity'],
      'warn',
      reason:
          "one broken file in a clone is the author's to fix, not a reason "
          'to fail their build',
    );
    expect(about.single['fix'], isNull);
  });
}
