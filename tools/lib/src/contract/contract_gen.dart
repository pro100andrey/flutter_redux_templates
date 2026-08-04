import '../audit/finding.dart';
import '../command_runner.dart';
import '../workspace/frx_workspace.dart';

/// The CLI's contract, emitted as TypeScript the extension imports.
///
/// **Why generate rather than assert.** `completions_command` already proves
/// the seam: it reads `option.allowed` off the parser, so shell completion
/// cannot drift, ever. Everything the editor knows was hand-copied instead —
/// the marker path four times, `remove --kind` in seven places, and four more
/// `--kind` sets that no test covered at all. `extension_contract_test` stood in
/// for the missing seam by regexing the TypeScript, and its fifth check asserts
/// that a constant does *not* exist, which is a test whose job is to stop a
/// duplicate coming back.
///
/// The same shape as `SkillGen` and the packed template: derived from the
/// command objects, written to disk because the consumer's CI has Node and no
/// Dart, and guarded by a freshness test rather than by anyone remembering.
///
/// **Values only.** What must not drift is the set a flag accepts. The prose
/// beside each value in a picker is the editor's, and it stays there — joined to
/// this by a `Record<Kind<'x'>, …>`, so adding a kind in Dart makes the
/// TypeScript fail to compile until somebody writes its description.
class ContractGen {
  const ContractGen._();

  /// Path (repo-relative) to content, ready to write.
  static Map<String, String> generate() => {
    'tools/vscode/src/generated/contract.ts': _contract(),
  };

  /// Every `--kind` in the CLI, by the command that takes it.
  ///
  /// Read live off the parsers, so a value added to an enum and surfaced
  /// through `allowed` arrives here without anyone deciding to bring it.
  static Map<String, List<String>> kinds() {
    final runner = FrxRunner();
    final out = <String, List<String>>{};
    for (final command in runner.commands.values) {
      final allowed = command.argParser.options['kind']?.allowed;
      if (allowed == null) continue;
      // `add-substate` → `substate`; `remove` and `rename` keep their own name,
      // since their kinds are artifact kinds rather than a flavour of one thing.
      final key = command.name.startsWith('add-')
          ? command.name.substring('add-'.length)
          : command.name;
      out[key] = allowed.toList();
    }
    return out;
  }

  static String _contract() {
    final b = StringBuffer()
      ..writeln('// AUTO-GENERATED — DO NOT EDIT.')
      ..writeln('// Produced by `cd tools && make contract`.')
      ..writeln('//')
      ..writeln(
        '// The CLI is the author of everything here: the `--kind` sets',
      )
      ..writeln('// come off each command\'s own ArgParser, the marker off')
      ..writeln(
        '// FrxWorkspace, the fix ids off the sealed Fix hierarchy. Edit',
      )
      ..writeln(
        '// the Dart and re-run; contract_freshness_test.dart fails on a',
      )
      ..writeln('// stale copy, so `make check` and CI catch it.')
      ..writeln()
      ..writeln('/**')
      ..writeln(' * The file `frx` keys on to decide where a project begins.')
      ..writeln(' *')
      ..writeln(' * Slash-separated, as the CLI states it. Join it with the')
      ..writeln(' * platform separator before touching the filesystem.')
      ..writeln(' */')
      ..writeln("export const MARKER_PATH = '${FrxWorkspace.marker}';")
      ..writeln()
      ..writeln(
        '/** Every `--kind` the CLI accepts, by the artifact it makes. */',
      )
      ..writeln('export const KINDS = {');
    for (final entry in kinds().entries) {
      final values = entry.value.map((v) => "'$v'").join(', ');
      b.writeln('  ${entry.key}: [$values],');
    }
    b
      ..writeln('} as const;')
      ..writeln()
      ..writeln('/** The values one `--kind` accepts, as a union. */')
      ..writeln(
        'export type Kind<K extends keyof typeof KINDS> = '
        '(typeof KINDS)[K][number];',
      )
      ..writeln()
      ..writeln('/**')
      ..writeln(' * The remedies `frx doctor --fix` can apply.')
      ..writeln(' *')
      ..writeln(' * The wire values the editor keys its quick-fixes on —')
      ..writeln(' * additive only, since an older extension has to keep')
      ..writeln(' * working against a newer CLI.')
      ..writeln(' */')
      ..writeln('export const FIX_IDS = [${_fixIds()}] as const;')
      ..writeln()
      ..writeln('export type FixId = (typeof FIX_IDS)[number];');
    return b.toString();
  }

  /// The remedy ids, from instances of the sealed hierarchy.
  ///
  /// Instances and not a hand-kept list: `Fix` is sealed so a new remedy is a
  /// compile error at every switch, and naming them here means the id the editor
  /// keys on comes from the same place the audit emits.
  static String _fixIds() => const <Fix>[
    BuildRunnerFix(''),
    OrphanFix(''),
    FlowDocsFix(),
  ].map((f) => "'${f.id}'").join(', ');
}
