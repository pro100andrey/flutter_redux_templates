import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/in_process.dart';

/// frx read against the **real monorepo**, not a fixture.
///
/// Every other suite builds its own model of the repo — `Fixture`, plus bespoke
/// `_workspace()` builders in `graph_test`, `flow_test` and `route_map_test` —
/// and those four disagree with each other and with `../`. `e2e_test`'s
/// strongest property is byte-clean round-trip, which is *invariant under any
/// systematic error in the writer* as long as the reader is symmetric: if frx
/// wrote `LogInPageConnectorRoute` everywhere, every round-trip test would
/// still be green. Nothing in the suite could disagree with frx about reality.
///
/// This can. It asserts invariants rather than snapshots, so adding a page or a
/// substate upstream does not break it — only an architectural change does, and
/// then failing is the right answer.
///
/// Skipped when `../app` is absent (a standalone `dart install --source path
/// tools` checkout), because a test that cannot see the repo has learned
/// nothing.
void main() {
  final root = _repoRoot();
  if (root == null) {
    test('the real monorepo', () {
      markTestSkipped('no ../app — not running inside the monorepo');
    }, skip: false);
    return;
  }

  late Map<String, Object?> graph;

  setUpAll(() async {
    final res = await runInProcessAt(root, ['graph', '--json']);
    expect(res.exitCode, 0, reason: res.stderr);
    graph = jsonDecode(res.stdout) as Map<String, Object?>;
  });

  List<Map<String, Object?>> nodesOfKind(String kind) => [
    for (final n in graph['nodes'] as List)
      if ((n as Map<String, Object?>)['kind'] == kind) n,
  ];

  test('every AppState substate is a graph node with a file that exists', () {
    // The first version of this asserted a file on *every* substate and failed
    // on `wait` — async_redux's own `Wait`, declared in AppState but defined in
    // the package, so there is no file in this repo to point at. Reality
    // correcting the assertion is the entire reason this tier exists.
    final substates = nodesOfKind('substate');
    expect(
      substates,
      isNotEmpty,
      reason: 'the real AppState has substates; the reader found none',
    );
    final owned = [
      for (final n in substates)
        if (!_frameworkSubstateTypes.contains(n['type'])) n,
    ];
    expect(
      owned,
      isNotEmpty,
      reason: 'every substate read as framework-provided — the filter is wrong',
    );
    for (final n in owned) {
      final file = n['file'] as String?;
      expect(file, isNotNull, reason: '${n['id']} has no file');
      expect(
        File(file!).existsSync(),
        isTrue,
        reason: '${n['id']} points at $file, which is not there',
      );
    }
  });

  test('every generated route class appears as a page node', () {
    // The test that would have caught the fixture's blind spot. `Fixture`
    // declared a bare `@AutoRouterConfig()` while the real router carries
    // `replaceInRouteName: 'PageConnector|Page,Route'` — so the fixture
    // asserted route names its own router would not have produced, and nothing
    // noticed because the suite never runs build_runner.
    //
    // Read off the *generated* file, which is committed: it is auto_route's
    // answer, not frx's.
    final gr = File(
      p.join(root, 'app', 'lib', 'navigation', 'app_router.gr.dart'),
    );
    if (!gr.existsSync()) {
      markTestSkipped('app_router.gr.dart not generated in this checkout');
      return;
    }
    final generated = RegExp(
      r'class\s+(\w+Route)\s+extends\s+PageRouteInfo',
    ).allMatches(gr.readAsStringSync()).map((m) => m.group(1)!).toSet();
    expect(generated, isNotEmpty, reason: 'no route classes found to compare');

    final known = {
      for (final n in nodesOfKind('page')) n['route'],
    }.whereType<String>().toSet();
    expect(known, isNotEmpty, reason: 'no page node carries a route name');

    expect(
      generated.difference(known),
      isEmpty,
      reason:
          'auto_route generates a route frx\'s page nodes do not mention — '
          'the router reader and the generator disagree about naming',
    );
    expect(
      known.difference(generated),
      isEmpty,
      reason:
          'frx names a route auto_route does not generate — the reader is '
          'inventing one',
    );
  });

  test('the blind spots are the ones we know about', () {
    // An allowlist, not an assertion of zero: frx is parse-only, and `pop` with
    // no single pusher is genuinely unresolvable that way. The point is that a
    // *new* blind spot fails here instead of quietly widening.
    final unresolved = [
      for (final u in graph['unresolved'] as List)
        (u as Map<String, Object?>)['kind'] as String,
    ];
    expect(
      unresolved.toSet().difference(_knownUnresolvedKinds),
      isEmpty,
      reason:
          'frx stopped following something new: $unresolved. Either fix the '
          'reader or add the kind to _knownUnresolvedKinds with the reason.',
    );
  });

  test('doctor is clean on the repo it ships with', () async {
    // CI already runs this and checks only the exit code; here the findings
    // themselves are the message when it breaks.
    final res = await runInProcessAt(root, ['doctor', '--json']);
    final findings =
        (jsonDecode(res.stdout) as Map<String, Object?>)['findings'] as List;
    expect(
      [for (final f in findings) (f as Map)['message']],
      isEmpty,
      reason: 'frx doctor reports drift in its own monorepo',
    );
  });

  test('the flow export is not drifting', () async {
    if (!Directory(p.join(root, 'docs', 'flows')).existsSync()) {
      markTestSkipped('docs/flows is opt-in and not enabled here');
      return;
    }
    final res = await runInProcessAt(root, ['flow', '--md', '--check']);
    expect(
      res.exitCode,
      0,
      reason: 'docs/flows differs from what the sources render: ${res.stdout}',
    );
  });

  // The skill that used to carry this routing alongside CLAUDE.md is gone, so
  // these instructions are now the only place an agent is told to reach for frx
  // before writing files by hand. That was always the unconditional half of the
  // pair: a skill fires only when its description matches the task, and one
  // editing an existing connector may never trigger it.
  test('the agent instructions carry the rule unconditionally', () {
    final instructions = File(p.join(root, 'CLAUDE.md')).readAsStringSync();
    expect(instructions, contains('frx --help'));
    expect(instructions, contains('by hand'));
  });
}

/// Substate types the app declares but does not define — async_redux ships
/// them, so no file in this repo holds one.
const _frameworkSubstateTypes = {'Wait'};

/// Blind spots frx is known to have, with the reason each is unfixable
/// parse-only. A kind not listed here is a regression.
const _knownUnresolvedKinds = {
  // `GoAction.pop()` names no destination; frx infers one only when exactly
  // one page pushes this one. Resolution would not help — the answer depends
  // on the navigation stack at runtime.
  'pop-destination',
};

/// The monorepo root, or null when the tests are not running inside one.
String? _repoRoot() {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    if (Directory(p.join(dir.path, 'app', 'lib')).existsSync() &&
        Directory(p.join(dir.path, 'business', 'lib')).existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) return null;
  }
}
