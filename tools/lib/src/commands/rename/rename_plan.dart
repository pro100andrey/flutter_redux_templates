import '../../ast/rename_edits.dart';
import '../../engine/build_step.dart';

/// A planned file move.
typedef Move = ({String from, String to});

/// A rename, decided but not yet carried out: what moves, what is rewritten,
/// what was generated from the old name, and what regenerates it under the
/// new one.
///
/// The two kinds `rename` knows — a substate and a page — differ only in how
/// they fill this in. Everything after it, from the preview to the codegen, is
/// one path; see `rename_execution.dart`.
class RenamePlan {
  const RenamePlan({
    required this.what,
    required this.repoRoot,
    required this.moves,
    required this.rename,
    required this.build,
    this.staleGenerated = const [],
    this.emptiedDirs = const [],
    this.afterEdits,
  });

  /// The headline — `substate "Old" → "New"`.
  final String what;

  /// The monorepo root the sweep and the report are anchored on.
  final String repoRoot;

  /// The files that change path.
  final List<Move> moves;

  /// The identifier, field, URI and literal rewrites, applied to every
  /// non-generated `.dart` under the `business`/`app`/`ui` lib and test trees.
  final RenameEdits rename;

  /// The codegen that remakes what the old name generated.
  final BuildStep build;

  /// Generated files left behind under the old name, to delete — build_runner
  /// remakes them under the new one. Only the ones that exist are planned.
  final List<String> staleGenerated;

  /// Directories the moves may have emptied, pruned afterwards when they are.
  final List<String> emptiedDirs;

  /// A last pass over each rewritten file, for the one string neither the
  /// token walk nor a path rule can reach.
  final String Function(String path, String content)? afterEdits;
}
