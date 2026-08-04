/// The tail every mutating command shares: print the plan, guard it, apply it,
/// report.
///
/// Lived in `scaffold/` while its neighbours were the flag helper and the
/// new-files-only front that the scaffolders used. Those are gone, and what is
/// left is not scaffolding — it is what happens *after* a [Changeset] exists,
/// which is this layer's business. `WritingCommand` is the only thing above it;
/// `rename` and `batch` reach it directly because neither is one.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../util/console.dart';
import 'build_step.dart';
import 'changeset.dart';
import 'write_report.dart';

/// Reads a flag a command may not declare.
///
/// `results['x']` *throws* for an undeclared option rather than returning null,
/// so `as bool? ?? false` does not save you — the subscript never returns. Not
/// every command that applies a [Changeset] offers every flag: `add-selector`
/// has no `--force`, `add-page` has no `--diff`.
bool _flag(ArgResults results, String name, {bool orElse = false}) =>
    results.options.contains(name)
    ? (results[name] as bool? ?? orElse)
    : orElse;

/// What a destructive command says when it has only shown you the plan.
///
/// `remove` and `rename` preview by default and write on `--apply`, the inverse
/// of the scaffolders' `--dry-run`, so they cannot use the default notice. It
/// was written out four times — three in `remove`, once in `rename` — which is
/// three chances for the flag it names to stop being the flag it takes.
const kPreviewNotice = 'Preview only — re-run with --apply to apply.';

/// Whether a destructive command was told to go through with it.
///
/// Two spellings, because `--force` is the retired one and still answers.
/// `remove` and `rename` each derived this inline, each under its own comment
/// explaining the same history.
///
/// **Gated on the command declaring `--apply`, and that is the whole safety of
/// it.** `--force` means two different things in this CLI: "actually do it" on
/// the two destructive commands, and "overwrite what is already there" on every
/// scaffolder — the collision guard below reads the same flag on the same
/// [ArgResults] to mean the second. Without this gate the first scaffolder to
/// reach for the shared helper, which is the obvious thing to do since it is the
/// shared write path, would silently make `frx add-page Home --force` mean
/// "apply" instead of "overwrite". A command with no `--apply` cannot get `true`
/// out of this, so the mistake is not available to make.
bool applying(ArgResults results) =>
    results.options.contains('apply') &&
    (_flag(results, 'apply') || _flag(results, 'force'));

/// Builds the build_runner step from what was actually written.
///
/// A function rather than a value because the package is sometimes only known
/// afterwards (the generic scaffolders read it off the first written file)
/// and because `remove --kind page` needs a `clean` before its `build`, which
/// no fixed set of fields would have expressed.
typedef DeferredBuild = BuildStep Function(List<String> written);

/// Prints [plan], guards it, applies it, and reports — the tail every mutating
/// command shares.
///
/// Handles in one place what the forked copies each handled themselves: the
/// overwrite guard (exit 70), `--dry-run`, `--diff` when the command declares
/// it, `dart format`, the `docs/flows` refresh, the written count and the
/// build_runner step. A command's own narration (`+ field: …`, `• already
/// present — skipped`) stays with the command and is emitted by [narrate],
/// which runs between the plan and the dry-run check so the output reads in the
/// order it always did.
///
/// [repoRoot] enables the `docs/flows` refresh. Pass it whenever the command
/// has a workspace in hand — it is a no-op unless the repo opted in, and
/// leaving it to each command to decide whether its edit *could* have moved a
/// route is what let `remove` refresh the docs while `add-substate` did not.
Future<int> runChangeset(
  ArgResults results, {
  required Changeset plan,
  required String header,
  void Function()? narrate,
  Directory? repoRoot,
  DeferredBuild? build,
  String? relativeTo,
  String? closing,
  bool? previewOnly,
  String previewNotice = 'Dry run — nothing written.',
}) async {
  // `remove` and `rename` are destructive, so they preview by default and write
  // on `--apply` — the inverse of the scaffolders' `--dry-run`. They say so
  // here rather than having this guess from a flag name.
  final dryRun = previewOnly ?? _flag(results, 'dry-run');
  final force = _flag(results, 'force');
  final asJson = machineMode(results);
  // A batch stages every intent into one transaction; inside one, this command's
  // narration, its `--json` line and its codegen all belong to the batch.
  final transaction = currentTransaction;

  // Frozen before anything is applied: a creation's operation and diff are both
  // read off the disk as it stands, so the same snapshot taken afterwards would
  // report every new file as an overwrite of itself. See [WriteReport].
  final report = asJson || transaction != null
      ? WriteReport.of(
          plan,
          command: results.name ?? '',
          relativeTo: relativeTo ?? repoRoot?.path,
        )
      : null;
  if (transaction != null && report != null) transaction.reports.add(report);

  if (!asJson) {
    console.out
      ..writeln(header)
      ..writeln();
  }

  // Errors go to stderr in both modes, so a `--json` consumer's stdout stays
  // parseable and the non-zero exit carries the whole truth.
  final collisions = plan.collisions;
  if (!dryRun && collisions.isNotEmpty && !force) {
    for (final f in collisions) {
      console.err.writeln('✗ ${p.relative(f)} already exists.');
    }
    console.err.writeln('Use --force to overwrite.');
    return 70;
  }

  if (!asJson) {
    if (plan.isNotEmpty) {
      console.out
        ..writeln('Files:')
        ..write(plan.describe(from: relativeTo))
        ..writeln();
    }

    narrate?.call();

    if (_flag(results, 'diff')) {
      final diff = plan.diff(from: relativeTo);
      if (diff.isNotEmpty)
        console.out
          ..write(diff)
          ..writeln();
    }
  }

  if (dryRun) {
    // The planned state carries the build step too, so the two states really are
    // one shape. Its outcome fields are facts, not predictions: nothing ran and
    // nothing was handed over, because nothing was applied.
    console.out.writeln(
      report?.render(
            applied: false,
            build: build == null || plan.formattable.isEmpty
                ? null
                : plannedBuild(build(plan.formattable)),
          ) ??
          previewNotice,
    );
    return 0;
  }

  final done = await apply(
    plan,
    format: _flag(results, 'format', orElse: true),
    repoRoot: repoRoot,
  );

  // [closing] replaces the count when the command has something more useful to
  // say — `add-nav` ends by naming the callback the developer still has to
  // hook up, which a file count would bury.
  if (!asJson) {
    console.out.writeln(closing ?? '✓ Wrote ${done.written.length} file(s).');
  }

  if (build != null && done.written.isNotEmpty) {
    final step = build(done.written);
    if (transaction != null) {
      // Handed over, not run: codegen is outside the transaction and runs once
      // after it, not once per intent.
      transaction.buildSteps.add(step);
      return 0;
    }
    final built = await runBuild(
      step,
      enabled: _flag(results, 'build-runner'),
      report: !asJson,
    );
    if (report != null) {
      console.out.writeln(
        report.render(applied: true, build: appliedBuild(step, built)),
      );
    }
    return built.code;
  }
  if (report != null) console.out.writeln(report.render(applied: true));
  return 0;
}

/// The build step as a carried-out result: what it was, and what became of it.
///
/// Public for the same reason [plannedBuild] is — `rename` and `batch` build their
/// own changesets and owe the same object.
BuildReport appliedBuild(BuildStep step, Built built) => (
  package: step.packageRoot,
  command: buildCommandLine(step),
  ran: built.ran,
  handedToWatch: built.handedToWatch,
  watchPid: built.watchPid,
);

/// The build step as a planned result: named, with nothing done to it yet.
///
/// Public because `rename` builds its own changeset and needs the same value —
/// the two states are one shape on every writing command, not only on the ones
/// that go through [runChangeset].
BuildReport plannedBuild(BuildStep step) => (
  package: step.packageRoot,
  command: buildCommandLine(step),
  ran: false,
  handedToWatch: false,
  watchPid: null,
);

/// Whether [results] asked for machine output.
///
/// A function rather than `results.flag('json')` at each call site because one
/// command got there first: `add-model --json` has always meant "also generate
/// `fromJson`/`toJson`". That spelling moved to `--serializable` so `--json`
/// means the same thing on every command — the surface criterion applied to a
/// flag name — and this is where a command with no `--json` at all still reads
/// as "no".
bool machineMode(ArgResults results) => _flag(results, 'json');
