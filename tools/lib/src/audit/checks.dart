/// The audit's checks, as a list it walks.
///
/// The list is not the point — walking the entries costs the same edit to
/// extend as calling that many functions did. (It said "seven" while there were
/// eleven, which is what a count in prose does.) Two things are:
///
/// - **A check is addressable and runnable alone.** Answering "what does the
///   substate check say about this tree" used to cost a subprocess and arrive
///   mixed in with six other checks' findings.
/// - **The gate is data.** "Observes the running machine rather than the file
///   tree" was an `if` in the middle of the calls; it is now a property of the
///   check that declares it, which is what the `--json` consumer's exclusion
///   keys on.
///
/// What a check *reports* is [Finding], and what `--fix` would do about it is a
/// [Fix] — named once there rather than three times in three shapes, which is
/// the duplication this split was actually for.
///
/// The checks themselves live under `checks/`, one file per concern; this
/// file is the list, and re-exports them so a test can run one by name.
library;

import '../ast/source_index.dart';
import '../workspace/frx_workspace.dart';
import 'checks/action_mixin_order.dart';
import 'checks/agent_hooks.dart';
import 'checks/dangling_imports.dart';
import 'checks/derived_artifacts.dart';
import 'checks/duplicate_selectors.dart';
import 'checks/generated_parts.dart';
import 'checks/placement.dart';
import 'checks/process_state.dart';
import 'checks/recovered_files.dart';
import 'checks/routes.dart';
import 'checks/source_text.dart';
import 'checks/substates.dart';
import 'finding.dart';

export 'checks/action_mixin_order.dart';
export 'checks/agent_hooks.dart';
export 'checks/dangling_imports.dart';
export 'checks/derived_artifacts.dart';
export 'checks/duplicate_selectors.dart';
export 'checks/generated_parts.dart';
export 'checks/placement.dart';
export 'checks/process_state.dart';
export 'checks/recovered_files.dart';
export 'checks/routes.dart';
export 'checks/source_text.dart';
export 'checks/substates.dart';

/// One audit check: what it is called, and what it reports.
class Check {
  const Check(this.id, this.run, {this.needsProcessState = false});

  /// Stable, kebab-case. Not emitted in `--json` — findings carry the `.frxrc`
  /// rule id, which is a different and finer thing — but it is how a test names
  /// one check, and how a future "run only this" would address it.
  final String id;

  /// Whether this check observes what is *running* rather than what is on disk.
  ///
  /// Those appear and vanish with no file changing, so a consumer that
  /// re-audits on file events — the editor — would keep showing one long after
  /// it was true.
  final bool needsProcessState;

  final void Function(FrxWorkspace repo, List<Finding> into) run;
}

/// Every check, in report order.
const auditChecks = <Check>[
  // First so its finding is read first, not because ordering protects it: a
  // file that is not valid UTF-8 makes `readAsStringSync` throw in whichever
  // check reaches it, and what keeps that from taking the audit down is the
  // per-check guard in [audit], not this position. The first version of this
  // comment claimed otherwise and was wrong — `frx doctor` still died with a
  // stack trace on the very file class this check exists to name.
  Check('source-text', checkSourceText),
  Check('substates', checkSubstates),
  Check('change-log', checkChangeLog),
  Check('routes-and-connectors', checkRoutesAndConnectors),
  Check('generated-parts', checkGeneratedParts),
  Check('dangling-imports', checkDanglingImports),
  Check('flow-docs', checkFlowDocs),
  Check('placement', checkPlacement),
  Check('view-model-equality', checkViewModels),
  Check('action-mixin-order', checkActionMixinOrder),
  Check('duplicate-selectors', checkDuplicateSelectors),
  Check('skills-stale', checkSkills),
  Check('agent-hooks', checkAgentHooks),
  Check('orphaned-watch', checkOrphanedWatch, needsProcessState: true),
  // Last: it reports on what the checks above read, so it has to run after
  // them. See [checkRecoveredFiles] for why that bound is the honest one.
  Check('recovered-files', checkRecoveredFiles),
];

/// Every finding derived from [repo], minus the process-state checks unless
/// [processState] asks for them.
List<Finding> audit(FrxWorkspace repo, {bool processState = false}) =>
    inSourceIndex(() {
      final findings = <Finding>[];
      for (final check in auditChecks) {
        if (check.needsProcessState && !processState) {
          continue;
        }
        try {
          check.run(repo, findings);
        } on Object catch (error, stack) {
          // **A check that throws must not take the audit with it.** Measured:
          // one source file of invalid UTF-8 made `readAsStringSync` throw
          // inside `checkGeneratedParts`, and `frx doctor` died with a stack
          // trace — losing every finding already collected, including
          // `checkSourceText`'s report of that exact file. Running the text
          // check first did not save it: the list is returned after the loop,
          // so an exception discards it whole.
          //
          // Reported rather than swallowed, and as an error: a check that could
          // not run is not a clean tree, and the editor's Problems panel is
          // where a user would otherwise see nothing at all.
          //
          // No `rule:`. That field is the `.frxrc` id a project silences a
          // *placement* finding by; a check id is not one, and putting it there
          // would offer the editor a "silence this" that silences nothing.
          //
          // The first frames of the trace go in the message, because the
          // alternative is a one-line "could not run" with no file and no line
          // — which reads to a user as "my project is broken" when it means
          // "frx is broken", and leaves nobody able to triage it.
          findings.add(
            Finding.error(
              'the "${check.id}" check could not run: $error\n'
              '${_firstFrames(stack)}',
            ),
          );
        }
      }
      return findings;
    });

/// The top of a stack trace, indented, for a finding that reports a crash.
///
/// Bounded because a finding is one entry in a list a user reads, not a crash
/// dump — the frames that name the failing check and its caller are the ones
/// that make it triageable, and the rest is `dart test`'s job.
String _firstFrames(StackTrace stack, {int frames = 4}) => stack
    .toString()
    .trimRight()
    .split('\n')
    .take(frames)
    .map((line) => '  $line')
    .join('\n');
