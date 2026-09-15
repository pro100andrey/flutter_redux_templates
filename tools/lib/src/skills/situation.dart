/// The authored half of one command's skill: how the job sounds before the
/// command is known, and what the command's own help omits.
///
/// Everything else in the skill — the invocation, the aliases, the flag list —
/// comes off the `Command` object. This is the part that cannot: a trigger has
/// to match how the task sounds in someone's head, not what the command is
/// called.
class Situation {
  /// A command that writes or moves an artifact of this architecture. Its skill
  /// carries the prohibition, because hand-writing one of these writes the
  /// files and misses the wiring.
  const Situation.wired(
    this.when, {
    this.context,
    this.paths = const [],
    this.traps = const [],
  }) : wires = true;

  /// A command that answers a question. Nothing to forbid — and, as the
  /// analyzer pointed out the moment the two were split, nothing to describe or
  /// to glob on either: [context] says what an artifact *is*, [paths] fires on
  /// the file being edited, and a command that writes no artifact has neither.
  const Situation.read(this.when, {this.traps = const []})
    : wires = false,
      context = null,
      paths = const [];

  /// Whether the description forbids hand-writing what this command wires.
  ///
  /// **Two constructors rather than a flag, and no unnamed one, so this cannot
  /// be left undecided.** It used to be a `_writes` set of command names 620
  /// lines from the only place that read it — and both reads were inside
  /// `_skill()`, where this object is already in hand. It had already come
  /// apart: `add-package` extends `WritingCommand`, and creating a package is
  /// five changes across two directories of which four alone leave a workspace
  /// that does not resolve, yet its skill said only "Answered by".
  ///
  /// It is not `cmd is WritingCommand`: `batch` and `rename` wire artifacts
  /// without extending it, and `update-skills` extends it and writes frx's own
  /// files rather than the project's — though that one never reaches here,
  /// since a command with no situation gets no skill.
  final bool wires;

  /// The trigger. Written the way the task sounds before the command is known.
  final String when;

  /// Globs that make the skill load when those files are being worked on.
  ///
  /// The measured failure this targets: an agent read five state files and
  /// rewrote them wholesale ten minutes after reading the skill that says not
  /// to. A description cannot fix that, because the standard says an agent
  /// "only consult\[s\] skills for tasks that require knowledge or capabilities
  /// beyond what they can handle alone" — and writing a Dart file looks like
  /// one it can. `paths` fires on the file instead of on the intent.
  ///
  /// Only for commands that edit an artifact that already exists. A creation
  /// command has no file to match yet, and a glob would narrow it to nothing.
  final List<String> paths;

  /// What the artifact *is*, in this template's terms, with code from it.
  ///
  /// The command help says what the command writes; it cannot say how the body
  /// is written afterwards, and that is where an agent falls back on recalled
  /// async_redux knowledge — which is right about the library and wrong here in
  /// five places (freezed rather than a hand-written `copy()`, an
  /// `extension type` facade rather than memoised selector functions,
  /// `extends Action` rather than `extends ReduxAction`, `IList` rather than
  /// `List`, private `_Factory`/`_Vm` in the connector file). Raw markdown, so
  /// it can carry the fenced code that makes the shape unambiguous.
  final String? context;

  final List<String> traps;
}
