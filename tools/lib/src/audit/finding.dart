/// What the audit reports, and what `--fix` would do about it.
///
/// The remedy used to be spelled three times in three unlike shapes — as three
/// nullable fields on the finding, as a `where` filter picking the fixable ones
/// out again, and as a nested ternary in the JSON encoder. Adding a check with a
/// new remedy meant three co-ordinated edits, and nothing made them agree.
///
/// Here it is one value. [Fix.id] is the only place a remedy's name is written,
/// and those names are a contract: the editor reads them to offer a quick-fix.
library;

/// How bad a finding is.
///
/// The name is the wire value the `--json` consumer reads, so the two cannot
/// drift.
enum Severity { error, warn }

/// A remedy `--fix` knows how to apply.
///
/// Sealed, so a new remedy is a compile error everywhere it has to be handled
/// rather than a silently-unfixed finding.
sealed class Fix {
  const Fix();

  /// The name the editor keys its quick-fix on. Part of the CLI's contract with
  /// the extension — additive only.
  String get id;
}

/// Regenerate a package's ungenerated parts.
class BuildRunnerFix extends Fix {
  const BuildRunnerFix(this.package);

  /// Package whose `build_runner build` regenerates the missing part.
  final String package;

  @override
  String get id => 'build_runner';
}

/// Delete a `redux/<folder>` substate folder that nothing composes.
class OrphanFix extends Fix {
  const OrphanFix(this.folder);

  /// The folder's basename on disk, as the audit found it — not a re-derived
  /// casing, because the name that was walked is the one that can be deleted.
  final String folder;

  @override
  String get id => 'orphan';
}

/// Rewrite the `docs/flows/` export from the current sources.
///
/// Carries nothing: the export is a pure function of the whole tree, so there
/// is no per-finding subject to regenerate — one drifted file and twenty mean
/// the same single rewrite.
class FlowDocsFix extends Fix {
  const FlowDocsFix();

  @override
  String get id => 'flow-docs';
}

/// A single problem the audit found.
class Finding {
  const Finding(this.severity, this.message, {this.file, this.fix, this.rule});

  const Finding.error(String message, {String? file, Fix? fix, String? rule})
    : this(Severity.error, message, file: file, fix: fix, rule: rule);

  const Finding.warn(String message, {String? file, Fix? fix, String? rule})
    : this(Severity.warn, message, file: file, fix: fix, rule: rule);

  final Severity severity;
  final String message;

  /// The placement rule that produced this, when one did — the id a project
  /// silences it by in `.frxrc`. Null for the drift checks, which are not
  /// individually silenceable because they cannot be wrong about someone else's
  /// project.
  final String? rule;

  /// Absolute path of an existing file to anchor a diagnostic on (the `--json`
  /// consumer squiggles it). Null for findings with no on-disk anchor.
  final String? file;

  /// What `--fix` would do, or null for a report-only finding.
  final Fix? fix;

  Map<String, Object?> toJson() => {
    'severity': severity.name,
    'message': message,
    'file': file,
    // The remedy `--fix` would apply, so the editor can offer a quick-fix;
    // null for report-only findings.
    'fix': fix?.id,
    // The `.frxrc` id, so a consumer can offer "silence this rule" without
    // knowing the catalogue.
    'rule': rule,
  };
}
