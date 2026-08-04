import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tools/src/contract/contract_gen.dart';

/// Writes the extension's generated constants from the CLI's own contract.
///
/// A derived artifact, like `.claude/skills` and the embedded template:
/// regenerate it with `make contract`, and `contract_freshness_test.dart` fails
/// when it is stale, so `make check` and CI catch a `--kind` added on one side
/// only.
void main(List<String> args) {
  final root = args.isNotEmpty
      ? args.first
      : p.normalize(p.join(Directory.current.path, '..'));

  final files = ContractGen.generate();
  for (final entry in files.entries) {
    File(p.join(root, entry.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  stdout.writeln('✓ ${files.keys.join(', ')}');
}
