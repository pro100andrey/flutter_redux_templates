import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// A reader that already holds a workspace must stay inside it.
///
/// `FrxWorkspace` keys on `app/lib/navigation/app_router.dart` and
/// `AppStateSource.locate` keys on `business/lib/redux/app_state.dart`, so a
/// project with a router and no `AppState` is exactly where the second walk
/// answers differently — by climbing *out*. Measured before this was closed:
/// `frx doctor` run inside such a project reported an orphan belonging to the
/// repository above it, and `--fix` deleted it.
void main() {
  late Fixture outer;
  late Directory inner;

  setUp(() {
    outer = Fixture.create();
    // An orphan in the outer repo: a substate folder with a state file, never
    // composed into its `AppState`. This is what `--fix` used to reach for.
    File(
        p.join(
          outer.root.path,
          'business/lib/redux/ghost/models/ghost_state.dart',
        ),
      )
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class GhostState {}\n');

    // An inner project: a router, and no business tree at all.
    inner = Directory(p.join(outer.root.path, 'example'))..createSync();
    File(p.join(inner.path, 'app/lib/navigation/app_router.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(outer.read('app/lib/navigation/app_router.dart'));
  });

  tearDown(() => outer.dispose());

  Future<List<Map<String, Object?>>> findings() async {
    final r = await runInProcess(outer, [
      'doctor',
      '--json',
      '--root',
      inner.path,
    ]);
    return ((jsonDecode(r.stdout) as Map)['findings'] as List)
        .cast<Map<String, Object?>>();
  }

  test('the audit reports nothing about the repository above it', () async {
    final messages = [for (final f in await findings()) '${f['message']}'];
    expect(
      messages.where((m) => m.contains('ghost')),
      isEmpty,
      reason: 'it reported an orphan that lives outside the root it printed',
    );
    expect(
      messages,
      contains(contains('AppState not found')),
      reason: 'the absence itself is what it should say',
    );
  });

  test('--fix deletes nothing outside the root it was given', () async {
    await runInProcess(outer, ['doctor', '--fix', '--root', inner.path]);
    expect(
      Directory(
        p.join(outer.root.path, 'business/lib/redux/ghost'),
      ).existsSync(),
      isTrue,
      reason: 'a repair reached out of the project it was pointed at',
    );
  });

  test('the graph refuses rather than modelling the tree above', () async {
    final r = await runInProcess(outer, [
      'graph',
      '--json',
      '--root',
      inner.path,
    ]);
    expect(r.exitCode, 70);
    expect(r.stderr, contains('no AppState'));
    expect(r.stdout, isNot(contains('ghost')));
  });
}
