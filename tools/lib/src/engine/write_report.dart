/// The machine-readable result of a write — **one format in two states**.
///
/// Eight reading commands emitted machine output and no writing command did,
/// which is backwards for an agent: reading source is something an agent already
/// does well, while writing five wired edits across two packages is what it does
/// badly.
///
/// There is no second format for results. The `--json` flag emits the changeset;
/// with `--dry-run` it is marked not applied, without it, applied. That only
/// works because [apply] is atomic — the result *is* the plan plus a marker, so
/// a partial state has no shape to describe. Terraform needs two objects because
/// its applies go partial; this one will not.
///
/// **Compatibility is additive-only, with no version number.** Fields are never
/// removed or repurposed, and a consumer must ignore fields it does not
/// recognise. The rule is the binding part — a version number with no stated
/// rule is decoration, as the Dart analyzer's own undocumented format version
/// demonstrates.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'changeset.dart';
import 'diff.dart';

/// What a `build_runner` step did, for the result of the command that triggered
/// it.
///
/// [handedToWatch] is the field that had to live here rather than in the audit.
/// Around a live watch a command stands down and hands the build over, and an
/// agent needs to know that at the moment it acts rather than when it audits
/// later. It is the rule *machine output describes the file tree* deciding a
/// case: the tree is what the format is about, so a process fact belongs to the
/// result of the command it affected, not to a later report about the project.
typedef BuildReport = ({
  /// Package root the build would run in.
  String package,

  /// The shell command that does it, for a consumer that has to run it itself.
  String command,

  /// Whether frx ran it here.
  bool ran,

  /// Whether a running watch was left to do it instead.
  bool handedToWatch,

  /// The watch's pid, when one was found by process scan.
  int? watchPid,
});

/// A changeset frozen into the machine write format.
///
/// Snapshotted **before** the changeset is applied, which is not an
/// optimisation: a [WriteFile]'s operation is `create` or `overwrite` depending
/// on what the disk holds, and its diff is computed against that same content.
/// Read afterwards, every creation would report itself as an overwrite of itself
/// with an empty diff — and the claim that the planned and applied states share
/// one shape would be false.
class WriteReport {
  WriteReport._(this._command, this._changes);

  /// Freezes [plan] as the result [command] will emit, applied or not.
  ///
  /// [relativeTo] is the repo root, used only for the diff headers — a unified
  /// diff names its file the way the tool that produced it always has, while a
  /// change's `path` is the absolute address every other `--json` producer in
  /// this CLI hands the editor.
  factory WriteReport.of(
    Changeset plan, {
    required String command,
    String? relativeTo,
  }) {
    String rel(String path) => relativeTo == null
        ? p.relative(path)
        : p.relative(path, from: relativeTo);
    return WriteReport._(command, [
      for (final c in plan.changes) _describe(c, rel),
    ]);
  }

  /// Merges [parts] into one result, in written order — what a batch emits.
  ///
  /// A batch is one changeset as far as a consumer is concerned: it applied
  /// completely or not at all, so describing it as several results would suggest
  /// a partial state the transaction has made impossible.
  factory WriteReport.batch(String command, Iterable<WriteReport> parts) =>
      WriteReport._(command, [for (final p in parts) ...p._changes]);

  final String _command;
  final List<Map<String, Object?>> _changes;

  /// The JSON line to print. [applied] is the whole difference between the
  /// planned and the carried-out result.
  String render({required bool applied, BuildReport? build}) => jsonEncode({
    'command': _command,
    'applied': applied,
    'changes': _changes,
    if (build != null)
      'build': {
        'package': build.package,
        'command': build.command,
        // The three that describe an **event**. A plan has had no event, so it
        // reports them as not-yet-happened rather than predicting them — do not
        // read a planned `handedToWatch: false` as "no watch is running".
        'ran': build.ran,
        'handedToWatch': build.handedToWatch,
        // Always present, null when no watch was found. Emitting it only when a
        // watch existed made the *field set* depend on what was running, which
        // breaks the one thing this format promises: the same shape in both
        // states.
        'watchPid': build.watchPid,
      },
  });

  /// One change: its address, its operation, and — where there is text to show —
  /// a unified diff.
  ///
  /// A diff rather than file contents, which would make the payload two source
  /// files large per file touched. A delete and a move carry none: the operation
  /// and the path already say the whole of what happens, and rendering a removal
  /// as an all-minus diff is the whole-file payload under another name.
  static Map<String, Object?> _describe(
    Change c,
    String Function(String) rel,
  ) => switch (c) {
    WriteFile() => {
      'op': File(c.path).existsSync() ? 'overwrite' : 'create',
      'path': c.path,
      'diff': unifiedDiff(
        File(c.path).existsSync() ? File(c.path).readAsStringSync() : '',
        c.content,
        path: rel(c.path),
      ),
    },
    EditFile() => {
      'op': 'edit',
      'path': c.path,
      'diff': unifiedDiff(c.before, c.after, path: rel(c.path)),
    },
    DeleteFile() => {'op': 'delete', 'path': c.path},
    DeleteDirectory() => {'op': 'delete-directory', 'path': c.path},
    MoveFile() => {'op': 'move', 'path': c.path, 'from': c.from},
  };
}
