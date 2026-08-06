import 'dart:io';

import 'package:path/path.dart' as p;

import '../audit/finding.dart';
import '../command_runner.dart';
import '../model/page_artifact.dart';
import '../scaffold/package_scaffold.dart';
import '../util/casing.dart';
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
      // The key is quoted because it comes from a command name: the first
      // hyphenated one to gain a `--kind` would emit `theme-extension: [...]`,
      // which is not a legal object key. `contract_freshness_test` compares
      // the generated string against itself, so it would pass while `tsc`
      // failed on a file this wrote.
      b.writeln("  '${entry.key}': [$values],");
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
      ..writeln('export type FixId = (typeof FIX_IDS)[number];')
      ..writeln()
      ..writeln('/**')
      ..writeln(' * What a non-zero `frx` exit means.')
      ..writeln(' *')
      ..writeln(' * The editor keys on both: `scaffold.ts` offers an overwrite')
      ..writeln(
        ' * on FAILURE, `artifact.ts` raises a disambiguation picker on',
      )
      ..writeln(' * USAGE. sysexits.h values, as a shell expects.')
      ..writeln(' */')
      ..writeln('export const EXIT = {')
      ..writeln('  usage: ${FrxRunner.exitUsage},')
      ..writeln('  failure: ${FrxRunner.exitFailure},')
      ..writeln('} as const;')
      ..writeln()
      ..write(_packages())
      ..writeln()
      ..write(_layout())
      ..writeln()
      ..write(_namingCases());
    return b.toString();
  }

  /// The optional workspace members `add-package` knows how to create.
  ///
  /// The editor had its own copy — three rows of directory and blurb — with the
  /// comment "hand-written rather than derived: `add-package` takes its kind as
  /// a positional, so there is no `--kind` list for the generator to harvest".
  /// True of the parser and beside the point: the catalogue is an enum, and an
  /// enum is data whether or not a flag happens to expose it.
  static String _packages() {
    final b = StringBuffer()
      ..writeln('/**')
      ..writeln(' * The optional workspace members `add-package` creates.')
      ..writeln(' *')
      ..writeln(' * `dir` is the argument the command takes and the folder it')
      ..writeln(' * writes; `summary` is the CLI\'s own one-liner for it.')
      ..writeln(' */')
      ..writeln('export const PACKAGES = [');
    for (final kind in PackageKind.values) {
      b.writeln(
        "  { dir: '${kind.dir}', summary: '${_escape(kind.summary)}' },",
      );
    }
    b
      ..writeln('] as const;')
      ..writeln()
      ..writeln('/** One optional package\'s directory, as a union. */')
      ..writeln("export type PackageDir = (typeof PACKAGES)[number]['dir'];");
    return b.toString();
  }

  /// Where the conventional files live, for the providers that key on a path.
  ///
  /// **Read off `FrxWorkspace` and `PageArtifact` rather than transcribed**: the
  /// generator builds a workspace at a sentinel root and asks it, so a directory
  /// that moves in Dart moves here. `codelens.ts` had the layout spelled out in
  /// four regexes and two `path.join`s, which is the same class of copy as the
  /// `--kind` sets — a lens that silently stops appearing is how it would have
  /// been noticed.
  static String _layout() {
    // A sentinel root the relative paths are taken against. Nothing touches the
    // filesystem: every one of these getters is a `join`.
    const root = '/__frx__';
    final repo = FrxWorkspace(Directory(root));
    String rel(Directory dir) =>
        p.url.joinAll(p.split(p.relative(dir.path, from: root)));

    // The suffixes, asked of the artifact that states them rather than typed
    // out: `PageArtifact` names the classes, and the files are those in snake.
    final page = PageArtifact(Casing.parse('sample_name'));
    String suffix(String className, String stem) =>
        '_${Casing.parse(className.substring(stem.length)).snake}.dart';

    final b = StringBuffer()
      ..writeln('/**')
      ..writeln(' * Where the conventional files live, slash-separated and')
      ..writeln(' * relative to the repo root.')
      ..writeln(' *')
      ..writeln(' * Join with the platform separator before touching disk.')
      ..writeln(' */')
      ..writeln('export const LAYOUT = {')
      ..writeln("  pages: '${rel(repo.uiPages)}',")
      ..writeln("  connectors: '${rel(repo.appConnectors)}',")
      ..writeln("  redux: '${rel(repo.businessRedux)}',")
      ..writeln("  pageSuffix: '${suffix(page.pageClass, 'SampleName')}',")
      ..writeln(
        "  connectorSuffix: '${suffix(page.connectorClass, 'SampleName')}',",
      )
      ..writeln("  stateSuffix: '_state.dart',")
      ..writeln('} as const;');
    return b.toString();
  }

  /// Worked examples of the CLI's casing, for the extension's own tests.
  ///
  /// **The one part of the contract that cannot be a value.** `naming.ts`
  /// re-implements `Casing` because a conversion is an algorithm, and there is
  /// no emitting an algorithm as data; calling the CLI per keystroke to
  /// validate a name is not a trade worth making. What *can* cross the seam is
  /// evidence: the CLI's own answers for a corpus chosen to hit the cases the
  /// two implementations could differ on, asserted by
  /// `vscode/test/naming.test.ts`. Drift becomes a failing test rather than a
  /// picker that quietly proposes the wrong class name.
  static String _namingCases() {
    // snake_case only, because that is the input class the extension gets:
    // `camelOf` and `pascalOf` are fed folder names off disk. `Casing` accepts
    // any spelling and the two really do differ on `ABCWidget` — asserting a
    // case neither side is asked would be inventing a disagreement.
    const corpus = [
      'my_profile',
      'log_in',
      'a',
      'theme',
      'user2_fa',
      'my__profile',
      'log_in_with_email',
    ];
    final b = StringBuffer()
      ..writeln('/**')
      ..writeln(' * What the CLI\'s `Casing` answers, for `naming.test.ts`.')
      ..writeln(' *')
      ..writeln(' * `naming.ts` re-implements the conversion because an')
      ..writeln(' * algorithm is not emittable as data. This is how the two')
      ..writeln(' * are held together: snake_case in, since that is what the')
      ..writeln(' * editor is ever handed.')
      ..writeln(' */')
      ..writeln('export const NAMING_CASES = [');
    for (final input in corpus) {
      final c = Casing.parse(input);
      b.writeln(
        "  { input: '$input', camel: '${c.camel}', pascal: '${c.pascal}', "
        "snake: '${c.snake}' },",
      );
    }
    b.writeln('] as const;');
    return b.toString();
  }

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// The remedy ids.
  ///
  /// The list is written out — `Fix` being sealed does not make a `const <Fix>[]`
  /// literal exhaustive, and the first version of this claimed it did. What
  /// makes it exhaustive is [_idOf]: a fourth subclass makes that switch
  /// non-exhaustive and the generator stops compiling until the id is listed.
  static String _fixIds() => const <Fix>[
    BuildRunnerFix(''),
    OrphanFix(''),
    FlowDocsFix(),
  ].map((f) => "'${_idOf(f)}'").join(', ');

  /// The compile-time guard the list needs.
  ///
  /// Exhaustive over the sealed hierarchy, so adding a remedy to `Fix` is a
  /// compile error here rather than a quick-fix that reaches the Problems panel
  /// with no label — `code_actions.ts` widens to index, deliberately, so nothing
  /// downstream would have failed.
  static String _idOf(Fix fix) => switch (fix) {
    BuildRunnerFix() => fix.id,
    OrphanFix() => fix.id,
    FlowDocsFix() => fix.id,
  };
}
