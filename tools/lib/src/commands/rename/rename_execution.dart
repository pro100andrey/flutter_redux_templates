import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../../engine/build_step.dart';
import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../engine/write_report.dart';
import '../../redux/ast_edit.dart';
import '../../util/console.dart';
import '../../workspace/frx_workspace.dart';
import 'rename_plan.dart';

/// One rewritten file: what it said, what it will say, and how many edits
/// that took.
typedef _Rewrite = ({String before, String after, int count});

/// Previews (or with `--apply` applies) [plan]: its moves, plus its rewrite
/// applied to every non-generated `.dart` under the `business`/`app`/`ui` lib
/// trees.
///
/// [command] is the name the machine report carries.
Future<int> executeRename(
  RenamePlan plan,
  ArgResults results, {
  required String command,
}) async {
  final goingThrough = applying(results);
  final asJson = machineMode(results);
  final repoRoot = plan.repoRoot;

  if (!asJson) {
    console.out
      ..writeln('Rename ${plan.what}')
      ..writeln();
  }

  // Which files change, and how many edits in each. Off the parse tree —
  // see [RenameEdits] for what that replaced and why.
  //
  // Each file is read once, here: the text the edits were computed against is
  // the `before` the changeset carries, so reading it again for the plan
  // would only offer a chance for the two to differ.
  final edits = <String, _Rewrite>{};
  for (final dir in ['business', 'app', 'ui']) {
    final lib = Directory(p.join(repoRoot, dir, 'lib'));
    if (!lib.existsSync()) {
      continue;
    }
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || FrxWorkspace.isGenerated(f.path)) {
        continue;
      }
      final original = f.readAsStringSync();
      final planned = plan.rename.of(
        parseString(content: original, throwIfDiagnostics: false).unit,
      );
      var content = applyEdits(original, planned);
      var count = planned.length;
      // What neither the tree nor a textual sweep can do, done by something
      // that knows what the text is *for*. A string literal must survive a
      // rename — a persistence key does — and the persistor's change log is a
      // string that *names a substate*, so the general rule is right and
      // wrong at the same time.
      if (plan.afterEdits case final afterEdits?) {
        final fixed = afterEdits(f.path, content);
        if (fixed != content) {
          content = fixed;
          count++;
        }
      }
      if (content != original) {
        edits[f.path] = (before: original, after: content, count: count);
      }
    }
  }

  // Only the ones that are really there: a plan that lists a delete which
  // cannot happen describes something other than what it will do.
  final stale = [
    for (final g in plan.staleGenerated)
      if (File(g).existsSync()) g,
  ];

  // Content edits are declared before the moves so they land while the paths
  // are still the old ones; [apply] preserves that order (and runs the
  // deletes first, which is harmless here — a stale generated file is never
  // also an edit target).
  //
  // Built here rather than after the preview gate, because the machine format
  // is one shape in two states and the planned state needs the same value the
  // applied one does.
  final changes = Changeset([
    for (final e in edits.entries)
      EditFile(e.key, before: e.value.before, after: e.value.after),
    for (final m in plan.moves) MoveFile(from: m.from, path: m.to),
    for (final g in stale) DeleteFile(g),
  ]);
  final report = asJson
      ? WriteReport.of(changes, command: command, relativeTo: repoRoot)
      : null;
  final step = plan.build;

  if (!asJson) {
    console.out.writeln('Files:');
    for (final m in plan.moves) {
      console.out.writeln(
        '  move  ${p.relative(m.from)} → ${p.relative(m.to)}',
      );
    }
    for (final g in stale) {
      console.out.writeln('  delete  ${p.relative(g)} (stale generated)');
    }
    console.out
      ..writeln()
      ..writeln('References (${edits.length} file(s)):');
    for (final e in edits.entries) {
      console.out.writeln('  ~ ${p.relative(e.key)}  (${e.value.count})');
    }
    console.out.writeln();

    if (results['diff'] as bool) {
      // `Changeset.diff` renders an `EditFile` as
      // `unifiedDiff(before, after)` — which is what this computed by hand
      // from the same two strings, the `before` being the very thing the plan
      // already carries. Paths are now relative to the repo root rather than
      // the working directory, which is the right anchor for a command that
      // takes `--root`.
      console.out
        ..write(changes.diff(from: repoRoot))
        ..writeln();
    }
  }

  if (!goingThrough) {
    console.out.writeln(
      report?.render(applied: false, build: plannedBuild(step)) ??
          kPreviewNotice,
    );
    return 0;
  }

  // Pre-flight before touching anything: every source must exist and no
  // destination may — renameSync would otherwise silently overwrite an
  // unwired file at the target path, or throw mid-apply after the reference
  // edits were already written.
  for (final m in plan.moves) {
    if (!File(m.from).existsSync()) {
      console.err.writeln('✗ ${p.relative(m.from)} does not exist — aborting.');
      return 70;
    }
    if (File(m.to).existsSync()) {
      console.err.writeln(
        '✗ ${p.relative(m.to)} already exists — aborting (move it away or '
        'remove it first).',
      );
      return 70;
    }
  }

  await apply(
    changes,
    format: results['format'] as bool,
    repoRoot: Directory(repoRoot),
  );

  // Pruning an emptied directory stays here: whether a folder left behind by
  // a move is *meaningfully* empty is rename's question, not one a generic
  // applier can answer.
  for (final d in plan.emptiedDirs) {
    final dir = Directory(d);
    if (dir.existsSync() &&
        dir.listSync(recursive: true).whereType<File>().isEmpty) {
      dir.deleteSync(recursive: true);
    }
  }

  // A renamed import token can fall out of alphabetical order — re-sort the
  // directives in every package the sweep touched (scoped to that one lint).
  final touchedPackages = {
    for (final f in [...edits.keys, ...plan.moves.map((m) => m.to)])
      p.join(repoRoot, p.split(p.relative(f, from: repoRoot)).first),
  };
  for (final pkg in touchedPackages) {
    await Process.run('dart', [
      'fix',
      '--apply',
      '--code=directives_ordering',
    ], workingDirectory: pkg);
  }

  if (!asJson) {
    console.out.writeln(
      '✓ Renamed. Run `dart analyze` to confirm nothing dangles.',
    );
  }

  final built = await runBuild(
    step,
    enabled: results['build-runner'] as bool,
    report: !asJson,
  );
  if (report != null) {
    console.out.writeln(
      report.render(applied: true, build: appliedBuild(step, built)),
    );
  }
  return built.code;
}
