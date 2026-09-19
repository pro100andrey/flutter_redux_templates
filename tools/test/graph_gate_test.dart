import 'dart:convert';

import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// `frx graph --fail-on-orphans` — the "nothing reaches" list as a gate.
///
/// The list itself is advice, and stays out of `doctor`: frx's own
/// `add-action -k waiting` writes an `isWaiting` nothing reads yet, so a check
/// that fired on it would fire on the tool's own output. CI wants a yes or no
/// all the same, and reading it out of a report is how a gate rots.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  test('exits 1 when something is unreached', () async {
    // The fixture's connectors are stubs, so no selector is read by anything.
    final r = await runInProcess(fx, ['graph', '--fail-on-orphans']);
    expect(r.exitCode, 1, reason: r.stdout);
    expect(r.stdout, contains('nothing reaches'));
  });

  test('without the flag the same graph exits 0', () async {
    final r = await runInProcess(fx, ['graph']);
    expect(r.exitCode, 0, reason: r.stderr);
    expect(r.stdout, contains('nothing reaches'));
  });

  test('--json still prints the graph on the failing exit', () async {
    // A gate that swallowed the output would leave CI with a code and no list.
    final r = await runInProcess(fx, ['graph', '--fail-on-orphans', '--json']);
    expect(r.exitCode, 1);
    final parsed = jsonDecode(r.stdout) as Map<String, dynamic>;
    expect(parsed['orphans'], isNotEmpty);
  });

  test('exits 0 once nothing is unreached', () async {
    // A facade with no getters has no selector to be unread.
    fx.file('business/lib/redux/selectors.dart').writeAsStringSync('''
import 'app_state.dart';

mixin Selectors {
  AppState get state;
}
''');
    // And something has to read the slices, or their fields are unread — a
    // file handing each one on reads every field of it.
    fx.file('app/lib/probe.dart').writeAsStringSync('''
class Probe {
  void run(Store<AppState> store) {
    _use(store.state.connectivity);
    _use(store.state.logIn);
  }
}
''');
    final r = await runInProcess(fx, ['graph', '--fail-on-orphans']);
    expect(r.exitCode, 0, reason: r.stdout);
  });

  test('a field nothing reads is unreached too', () async {
    // The e2e fixture's slices each carry a `value` nothing reads; with the
    // facade emptied, the field is what is left on the list.
    fx.file('business/lib/redux/selectors.dart').writeAsStringSync('''
import 'app_state.dart';

mixin Selectors {
  AppState get state;
}
''');
    final r = await runInProcess(fx, ['graph', '--fail-on-orphans']);
    expect(r.exitCode, 1, reason: r.stdout);
    expect(r.stdout, contains('field:logIn.value'));
  });
}
