/// What a mutating command *plans to do* to the repo, as a value — and the one
/// place that carries it out.
///
/// Every `add-*`/`remove`/`rename` command used to end the same way: print a
/// plan, print a diff, bail on `--dry-run`, write, format, sometimes refresh
/// `docs/flows`, report a count, sometimes run build_runner. A since-deleted
/// helper owned that flow for the commands whose whole output was *new* files,
/// because its `files` parameter was a `Map<String, String>` — a shape with
/// nowhere to put a before/after, a move, or a delete. So every command that
/// edits something existing forked it, and the copies drifted:
///
///   * `--dry-run` was implemented seven times, and twice more spelled as an
///     inverted `--force`, which is why `add-page --force` means *overwrite*
///     while `remove --force` means *write anything at all*;
///   * `remove` refreshed `docs/flows` when deleting a substate and
///     `add-substate` did not, so adding and removing the same artifact had
///     different side effects;
///   * `doctor --fix` skipped [formatFiles] entirely and re-implemented it as a
///     bare `dart format` call, dropping the `.dart` filter and the failure
///     warning.
///
/// A [Changeset] is the missing shape. Commands build one and hand it to
/// [apply]; none of them decides what applying means.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'build_step.dart';
import 'diff.dart';
import 'write_report.dart';

/// One planned operation. Sealed so [apply] and [Changeset.describe] cannot
/// silently ignore a kind added later.
sealed class Change {
  const Change();

  /// The path the operation is *about* — its destination for a [MoveFile],
  /// so that formatting and reporting name the file that ends up on disk.
  String get path;
}

/// Write [content] to [path], creating parent directories. Used both for a new
/// file and for a deliberate overwrite; [Changeset.describe] tells them apart
/// by looking at the disk, so the plan says `create` or `overwrite` truthfully.
final class WriteFile extends Change {
  const WriteFile(this.path, this.content);

  @override
  final String path;
  final String content;
}

/// Replace the contents of an existing [path], which currently holds [before].
///
/// Distinct from [WriteFile] only because it carries [before]: that is what
/// makes `--diff` possible without re-reading a file that may already have been
/// written by an earlier change in the same set.
final class EditFile extends Change {
  const EditFile(this.path, {required this.before, required this.after});

  @override
  final String path;
  final String before;
  final String after;
}

/// Delete a single file.
final class DeleteFile extends Change {
  const DeleteFile(this.path);

  @override
  final String path;
}

/// Delete a directory and everything under it.
///
/// `add-substate --force` uses this to regenerate a substate folder cleanly, so
/// a `set_value_action.dart` from a previous `--kind` does not linger.
final class DeleteDirectory extends Change {
  const DeleteDirectory(this.path);

  @override
  final String path;
}

/// Move [from] to [path]. Parent directories of the destination are created;
/// emptied parents of the source are *not* pruned — `rename` does that itself,
/// because "is this directory now meaningfully empty" is its question, not one
/// a generic applier can answer.
final class MoveFile extends Change {
  const MoveFile({required this.from, required this.path});

  final String from;

  @override
  final String path;
}

/// A planned set of [Change]s, in the order they will be applied.
class Changeset {
  Changeset([Iterable<Change> changes = const []]) : _changes = [...changes];

  final List<Change> _changes;

  List<Change> get changes => List.unmodifiable(_changes);

  bool get isEmpty => _changes.isEmpty;
  bool get isNotEmpty => _changes.isNotEmpty;

  /// Appends [change]. Returns this, so a command can build a set inline.
  Changeset add(Change change) => this.._changes.add(change);

  /// Appends [change] only when it is not null — the common shape, since most
  /// commands compute an edit that may turn out to be a no-op (an
  /// [EditOutcome] that reports itself `unchanged`).
  Changeset addIf(Change? change) => change == null ? this : add(change);

  /// The files that will exist afterwards, for `dart format`. Deletions are
  /// excluded (there is nothing left to format) and a move contributes its
  /// destination.
  List<String> get formattable => [
    for (final c in _changes)
      if (c is! DeleteFile && c is! DeleteDirectory) c.path,
  ];

  /// The plan, one line per change, paths relative to [from].
  ///
  /// `create` vs `overwrite` is decided against the disk at call time, so a
  /// plan printed before applying tells the truth about what it is about to
  /// replace.
  String describe({String? from}) {
    String rel(String path) =>
        from == null ? p.relative(path) : p.relative(path, from: from);
    final out = StringBuffer();
    for (final c in _changes) {
      // `<verb>  <path>`, two spaces, unaligned — the shape the scaffolders
      // have always printed. Aligning the column would be tidier and would
      // change every existing plan.
      out.writeln(switch (c) {
        WriteFile() =>
          '  ${File(c.path).existsSync() ? 'overwrite' : 'create'}  ${rel(c.path)}',
        EditFile() => '  edit  ${rel(c.path)}',
        DeleteFile() => '  delete  ${rel(c.path)}',
        DeleteDirectory() => '  delete  ${rel(c.path)}${p.separator}',
        MoveFile() => '  move  ${rel(c.from)} → ${rel(c.path)}',
      });
    }
    return out.toString();
  }

  /// A unified diff of every textual change, paths relative to [from].
  ///
  /// A [WriteFile] diffs against what is on disk (empty for a new file), an
  /// [EditFile] against the `before` it carries. Deletes and moves contribute
  /// nothing — there is no textual change to show.
  String diff({String? from}) {
    String rel(String path) =>
        from == null ? p.relative(path) : p.relative(path, from: from);
    final out = StringBuffer();
    for (final c in _changes) {
      switch (c) {
        case WriteFile():
          final file = File(c.path);
          final before = file.existsSync() ? file.readAsStringSync() : '';
          out.write(unifiedDiff(before, c.content, path: rel(c.path)));
        case EditFile():
          out.write(unifiedDiff(c.before, c.after, path: rel(c.path)));
        case DeleteFile():
        case DeleteDirectory():
        case MoveFile():
          break;
      }
    }
    return out.toString();
  }

  /// The [WriteFile] targets that already exist — what the overwrite guard
  /// refuses without `--force`. An [EditFile] is not included: editing an
  /// existing file is the point, not a collision.
  List<String> get collisions => [
    for (final c in _changes)
      if (c is WriteFile && File(c.path).existsSync()) c.path,
  ];
}

/// The outcome of [apply], so a caller can report without re-deriving it.
typedef Applied = ({List<String> written, List<String> removed});

/// A changeset that did not apply — thrown by [apply] *after* it has put the
/// tree back.
///
/// So a caller has nothing to clean up and one thing to report. The tree is
/// either wholly changed or wholly untouched, and [restoreErrors] is the single
/// exception: a rollback step that itself failed is the one case where neither
/// is true, so it is named rather than swallowed.
class ApplyFailure implements Exception {
  ApplyFailure(this.cause, this.stackTrace, {this.restoreErrors = const []});

  /// What went wrong while applying — normally a [FileSystemException].
  final Object cause;

  final StackTrace stackTrace;

  /// Rollback steps that failed, already formatted for a reader. Empty in the
  /// ordinary case, which is what makes the tree's state knowable.
  final List<String> restoreErrors;

  /// Whether the tree was fully restored.
  bool get rolledBack => restoreErrors.isEmpty;

  String get message => rolledBack
      ? 'could not apply the change — nothing was written: $cause'
      : 'could not apply the change, and the rollback did not fully '
            'succeed: $cause\n'
            '${restoreErrors.map((e) => '  ! $e').join('\n')}';

  @override
  String toString() => message;
}

/// Carries out [plan]: delete, move, write, then format and refresh the
/// derived docs.
///
/// [format] and [repoRoot] are the two cross-cutting steps every mutating
/// command owed and not all of them paid. Refreshing `docs/flows` is
/// unconditional here — it is a silent no-op when the repo has not opted in,
/// and idempotent when nothing changed, so the alternative (each command
/// deciding whether its edit could have moved a route) is the arrangement that
/// let add and remove disagree.
///
/// **Applies completely or not at all.** Wiring a navigation hop is five edits
/// across two packages, four of which alone leave code that does not compile,
/// so a partial application is this engine's defining risk rather than a corner
/// case. Every step records how to undo itself in a [_Journal] first; a failure
/// unwinds that journal and throws [ApplyFailure], leaving a failed write
/// indistinguishable from a write never attempted.
///
/// **The transaction covers the filesystem changeset only.** [formatFiles], the
/// `docs/flows` refresh and (in the caller) codegen run afterwards and roll
/// nothing back — undoing a correct edit because a formatter failed is the worse
/// outcome. They report their own failures instead.
///
/// **A transaction in effect widens the boundary rather than nesting one.** When
/// [currentTransaction] is set, the changeset is staged into it: the post steps
/// are the batch's to run once at the end, and a failure unwinds *the whole
/// batch* rather than this one changeset. See [WriteTransaction].
Future<Applied> apply(
  Changeset plan, {
  required bool format,
  Directory? repoRoot,
}) async {
  if (currentTransaction case final joined?) {
    final before = joined.written.length;
    final removedBefore = joined.removed.length;
    // No catch: the batch owns the unwind, and swallowing the failure here would
    // leave it with a half-applied transaction it was told nothing about.
    joined.stage(plan);
    return (
      written: joined.written.sublist(before),
      removed: joined.removed.sublist(removedBefore),
    );
  }

  final transaction = WriteTransaction();
  try {
    transaction.stage(plan);
  } on Object catch (error, stack) {
    throw ApplyFailure(error, stack, restoreErrors: transaction.rollback());
  }

  await settle(transaction, format: format, repoRoot: repoRoot);

  return (written: transaction.written, removed: transaction.removed);
}

/// What has to happen once a transaction's writes have landed, whoever
/// committed it: format what changed, then refresh the `docs/flows` export.
///
/// Two lines, and they are a pair in that order. [apply] runs them for a single
/// changeset; `batch` runs them once for a whole transaction, because it stages
/// every intent and commits at the end. Its copy carried the comment "in the
/// order the single-command path uses" — a duplicate that knew it was one.
/// Named, the order is not something a third caller has to notice and get
/// right.
Future<void> settle(
  WriteTransaction transaction, {
  required bool format,
  Directory? repoRoot,
}) async {
  await formatFiles(transaction.written, enabled: format);
  if (repoRoot != null) await refreshFlowDocs(repoRoot);
}

/// One rollback boundary, across as many changesets as are staged into it.
///
/// A single [apply] is a one-changeset transaction. A batch is the reason this is
/// a value: a batch is not merely fewer keystrokes, it is **one rollback boundary
/// where eight invocations are eight boundaries**, and a failure at the fifth
/// leaves the first four applied.
class WriteTransaction {
  final _Journal _journal = _Journal();

  /// Files that exist afterwards, in the order they were written.
  final List<String> written = [];

  /// Paths removed, in the order they were removed.
  final List<String> removed = [];

  /// Build steps the staged changesets asked for, for the caller to run **once**
  /// after the transaction closes. Codegen is not part of the transaction: it
  /// rolls nothing back, and running it per changeset would run it eight times.
  final List<BuildStep> buildSteps = [];

  /// Each staged changeset in the machine write format, in order — what a batch
  /// emits as one combined plan.
  ///
  /// Collected by `runChangeset` rather than derived here, because a report has to
  /// be frozen *before* its changeset is applied: `create` vs `overwrite` and the
  /// diff are both read off the disk as it stands.
  final List<WriteReport> reports = [];

  /// Carries out [plan], recording how to undo every step.
  ///
  /// Throws on failure without unwinding — the owner decides, because in a batch
  /// the failure of the fifth changeset has to take the first four with it.
  void stage(Changeset plan) {
    // Deletes first: `add-substate --force` clears a folder it is about to
    // repopulate, so writing before deleting would throw the new files away.
    // Atomicity makes that order recoverable; it does not reorder it.
    for (final c in plan.changes) {
      switch (c) {
        case DeleteFile():
          final file = File(c.path);
          if (file.existsSync()) {
            _journal.capture(file);
            file.deleteSync();
            removed.add(c.path);
          }
        case DeleteDirectory():
          final dir = Directory(c.path);
          if (dir.existsSync()) {
            _journal.captureTree(dir);
            dir.deleteSync(recursive: true);
            removed.add(c.path);
          }
        case WriteFile():
        case EditFile():
        case MoveFile():
          break;
      }
    }

    for (final c in plan.changes) {
      switch (c) {
        case WriteFile():
          final file = File(c.path);
          _journal.createParents(file);
          _journal.capture(file);
          file.writeAsStringSync(c.content);
          written.add(c.path);
        case EditFile():
          final file = File(c.path);
          _journal.capture(file);
          file.writeAsStringSync(c.after);
          written.add(c.path);
        case MoveFile():
          final dest = File(c.path);
          _journal.createParents(dest);
          // `renameSync` overwrites its destination, so the victim is captured
          // before the move that replaces it — recorded first so the unwind
          // puts the move back before restoring what it displaced.
          _journal.capture(dest);
          _journal.captureMove(from: c.from, to: c.path);
          File(c.from).renameSync(dest.path);
          written.add(c.path);
        case DeleteFile():
        case DeleteDirectory():
          break;
      }
    }
  }

  /// Puts everything back. Returns the steps that failed — empty when the tree is
  /// as it was.
  List<String> rollback() => _journal.rollback();
}

const _transactionKey = #frxTransaction;

/// The transaction [apply] joins, or null when each changeset is its own.
///
/// A zone value for the reason the console is one: [apply] is reached through
/// fifteen commands, and threading a parameter through every one of them would be
/// a larger change than the batch it serves. A zone value is scoped to the body
/// that asked for it and cannot leak into whatever runs next — which a mutable
/// global would, since `dart test` runs a suite's cases on one isolate.
WriteTransaction? get currentTransaction =>
    Zone.current[_transactionKey] as WriteTransaction?;

/// Runs [body] with every [apply] inside it staging into [transaction].
R withTransaction<R>(WriteTransaction transaction, R Function() body) =>
    runZoned(body, zoneValues: {_transactionKey: transaction});

/// The undo log [apply] builds as it goes, unwound in reverse on failure.
///
/// Recorded while applying rather than derived from the plan up front, because a
/// plan says what it *intends* and only the applier knows what it found: whether
/// a write target existed, which parent directories it had to create, what a
/// delete removed.
///
/// That last one is the addition atomicity forced. An [EditFile] carries its
/// `before` and a [MoveFile] knows both ends, but a delete knows only a path,
/// and a path is not something you can restore from — so content is captured
/// here, immediately before the removal. Not when the plan was built: a plan is
/// built before the collision guard and the dry-run gate, so content read that
/// early would be a guess about what the file still held.
///
/// File modes are not restored, only contents and paths. Every file this engine
/// touches is Dart source; a tree that mixes in executables would need `stat`
/// and `chmod`, which are not portable, and no changeset produces one.
class _Journal {
  final List<_Undo> _undo = [];

  /// Records how to put [file] back, whether it currently exists or not — an
  /// absent file is restored by deleting whatever took its place.
  void capture(File file) {
    if (!file.existsSync()) {
      _undo.add((describe: 'remove ${file.path}', run: () => _erase(file)));
      return;
    }
    final was = file.readAsBytesSync();
    _undo.add((
      describe: 'restore ${file.path}',
      run: () => file
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(was),
    ));
  }

  /// Records how to rebuild [dir] and everything under it.
  ///
  /// Empty subdirectories are captured too: the folder a `--force` re-creation
  /// clears may hold one, and "byte-identical" is a claim about the tree, not
  /// only about its files. Links are skipped — no changeset creates one, and
  /// re-creating one blind is how a rollback does damage of its own.
  void captureTree(Directory dir) {
    final dirs = <String>[dir.path];
    final files = <String, List<int>>{};
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      switch (entity) {
        case Directory():
          dirs.add(entity.path);
        case File():
          files[entity.path] = entity.readAsBytesSync();
        default:
          break;
      }
    }
    _undo.add((
      describe: 'restore ${dir.path}${p.separator}',
      run: () {
        for (final d in dirs) {
          Directory(d).createSync(recursive: true);
        }
        for (final entry in files.entries) {
          File(entry.key).writeAsBytesSync(entry.value);
        }
      },
    ));
  }

  /// Records how to undo the move of [from] to [to].
  void captureMove({required String from, required String to}) {
    _undo.add((
      describe: 'move $to back to $from',
      run: () {
        final moved = File(to);
        if (!moved.existsSync()) return;
        File(from).parent.createSync(recursive: true);
        moved.renameSync(from);
      },
    ));
  }

  /// Creates the parent directories of [file], recording the topmost one that
  /// did not exist so the unwind can take the whole branch away with it.
  ///
  /// Called *before* the change's other captures, because the unwind runs newest
  /// first and removing the branch has to be the last thing it does: a move into
  /// a fresh directory is undone by moving the file back out, and a branch
  /// removed first would delete the file the move-back was looking for.
  void createParents(File file) {
    final parent = file.parent;
    if (parent.existsSync()) return;
    var top = parent;
    while (!top.parent.existsSync() && top.parent.path != top.path) {
      top = top.parent;
    }
    parent.createSync(recursive: true);
    _undo.add((
      describe: 'remove ${top.path}${p.separator}',
      run: () {
        if (top.existsSync()) top.deleteSync(recursive: true);
      },
    ));
  }

  /// Unwinds every recorded step, newest first. Returns the steps that failed —
  /// empty when the tree is back to what it was.
  ///
  /// Every step is attempted even after one fails: a second failure is more
  /// information, and stopping early would strand parts of the tree that the
  /// remaining steps could still have put back.
  List<String> rollback() {
    final failed = <String>[];
    for (final step in _undo.reversed) {
      try {
        step.run();
      } on Object catch (e) {
        failed.add('could not ${step.describe}: $e');
      }
    }
    return failed;
  }

  static void _erase(File file) {
    if (file.existsSync()) file.deleteSync();
  }
}

/// One reversal: what it does, phrased for a reader, and the doing of it.
typedef _Undo = ({String describe, void Function() run});
