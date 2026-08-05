import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/command_runner.dart';
import 'package:tools/src/contract/contract_gen.dart';

/// The extension's generated constants match the CLI they came from.
///
/// The same shape as `skills_freshness_test` and `template_freshness_test`, and
/// for the same reason: the output is committed, because the extension's CI has
/// Node and no Dart and cannot re-derive it.
///
/// What it replaces is an *assertion*. `extension_contract_test` used to read
/// `remove --kind` off the live parser and compare it against a regex
/// extraction of `ARTIFACT_KINDS` from `ui.ts` — a test standing in for a seam.
/// Four more `--kind` sets had no test at all.
void main() {
  final repoRoot = p.dirname(Directory.current.absolute.path);
  const regen = 'Regenerate it: cd tools && make contract';

  test('the generated contract is not stale', () {
    for (final entry in ContractGen.generate().entries) {
      final file = File(p.join(repoRoot, entry.key));
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} is missing. $regen',
      );
      expect(
        file.readAsStringSync(),
        entry.value,
        reason: '${entry.key} is stale. $regen',
      );
    }
  });

  test('every --kind the CLI takes reaches the contract', () {
    // The generator walks the runner, so this is really asking whether the walk
    // still finds them — a command that declared `kind` some other way (a
    // positional, a differently-named option) would leave the editor with a
    // hand-written list again and nothing would say so.
    final declaring = <String>{
      for (final c in FrxRunner().commands.values)
        if (c.argParser.options['kind']?.allowed != null) c.name,
    };
    expect(
      declaring,
      isNotEmpty,
      reason: 'no command declares --kind — the walk is broken, not the CLI',
    );
    expect(
      ContractGen.kinds(),
      hasLength(declaring.length),
      reason:
          'commands declaring --kind: ${declaring.join(', ')} — but the '
          'contract carries ${ContractGen.kinds().keys.join(', ')}',
    );
  });
}
