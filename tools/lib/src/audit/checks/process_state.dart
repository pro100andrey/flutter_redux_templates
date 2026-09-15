import '../../engine/watch_processes.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// `build_runner watch` processes whose parent died.
///
/// They linger for hours regenerating nothing, and look identical to a
/// healthy watch from the outside — the generated file simply stops keeping
/// up. frx already refuses to build around a live watch, so an orphan would
/// otherwise make it stand down for a process that will never do the work.
///
/// **Neither remedy is a plain `kill`, and that is the point.**
/// `build_runner watch` installs a handler for exactly one signal — `SIGINT`
/// (`build_runner/lib/src/commands/watch_command.dart`,
/// `ProcessSignal .sigint.watch()`). A bare `kill` sends `SIGTERM`, which it
/// never hears about, so the process dies wherever it happens to be with no
/// drain and no release of its lock.
///
/// `build_runner stop` is named first because it is the sanctioned one: it
/// writes a `.requested` file beside the build lock and the running watch picks
/// it up through a file watcher, so it never asks who the parent was — which is
/// exactly the property an orphan needs. It is scoped to one project, though,
/// so `kill -INT` stays as the answer for an orphan belonging to a project you
/// are not standing in.
// The workspace is unused — this check reads the process table, not the tree.
// Kept in the signature so every check has one shape and the registry can hold
// them together; the alternative is a second signature and a branch to pick it.
void checkOrphanedWatch(FrxWorkspace repo, List<Finding> into) {
  // Scoped to this repo: a watch abandoned in another project is that
  // project's to clean up, and naming its pid here sends the reader to
  // `kill` a process that has nothing to do with what they are auditing.
  for (final pid in orphanedBuildRunnerWatchPids(within: repo.root.path)) {
    into.add(
      Finding.warn(
        'build_runner watch (pid $pid) outlived the terminal or IDE that '
        'started it — it regenerates nothing. Stop it with '
        '`dart run build_runner stop --workspace` from the project it '
        'watches, or `kill -INT $pid` — then start a new one.',
      ),
    );
  }
}
