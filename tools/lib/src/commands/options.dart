/// Option text every command shares.
///
/// `--root` was spelled out eighteen times and the help had already drifted in
/// two of them — `list-mixins` says something different on purpose, everything
/// else said the same thing by hand.
///
/// Constants rather than an `addRootOption(parser)` helper because every
/// command declares its options as one cascade on `argParser`, and a void
/// function does not compose into a cascade without breaking the chain. The
/// duplication worth removing here is the *string*, not the call.
///
/// The related invariant — every `--json` command also accepts `--root`,
/// because the editor reads every machine-readable command through one helper
/// that appends both, and a command that refuses `--root` is unreachable from
/// there *silently* — is enforced by `frx_command_test.dart`, which walks the
/// registered commands.
///
/// `WritingCommand` is where that invariant became structural for the commands
/// built on it: they cannot forget a flag they never declare. Until every
/// writing command is one, the registry walk is still what holds the rest — and
/// it holds the reading commands either way, which have no such base and need
/// none.
library;

/// Help for `--root` on a command that reads the repo.
const kRootHelp = 'Repo root to search from.';

/// Help for `--root` on a command that does not read the repo but accepts the
/// option anyway, so the editor's one JSON helper can reach it.
const kRootAcceptedHelp = 'Repo root (accepted for consistency).';

/// Help for `--json` on a command that **writes**.
///
/// One string because the flag means one thing on all of them: the changeset,
/// in the same shape whether it was applied or only planned. A reading
/// command's `--json` describes what it found and keeps its own wording.
const kMachineHelp =
    'Emit the changeset as JSON instead of the human report '
    '(with --dry-run it is marked not applied).';
