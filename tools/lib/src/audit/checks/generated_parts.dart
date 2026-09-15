import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ast/source_index.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Any `part 'x.(freezed|g|g.theme|gr).dart'` whose target file is absent means
/// build_runner hasn't run (or is stale).
void checkGeneratedParts(FrxWorkspace repo, List<Finding> into) {
  for (final (:package, :lib) in repo.sourceLibs()) {
    for (final entity in sourceIndex.filesUnder(lib)) {
      for (final m in _partDirective.allMatches(sourceIndex.sourceOf(entity))) {
        final target = File(p.join(entity.parent.path, m.group(1)));
        if (target.existsSync()) {
          continue;
        }

        into.add(
          Finding.error(
            '${p.relative(entity.path, from: repo.root.path)} → part '
            '"${m.group(1)}" missing (run build_runner).',
            file: entity.path,
            fix: BuildRunnerFix(package),
          ),
        );
      }
    }
  }
}

/// A `part` directive naming build_runner output.
final _partDirective = RegExp(
  r'''^part\s+['"]([^'"]+\.(?:freezed|g|g\.theme|gr)\.dart)['"]\s*;''',
  multiLine: true,
);
