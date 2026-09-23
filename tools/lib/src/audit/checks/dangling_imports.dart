import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../ast/source_index.dart';
import '../../workspace/frx_workspace.dart';
import '../../workspace/workspace_uri.dart';
import '../finding.dart';

/// An `import` or `export` of a project file that does not exist.
///
/// The audit knew the architecture's wiring and nothing about the plain fact
/// underneath it: a file that imports a deleted file does not compile. So
/// `remove theme --kind substate` left the persistor, `app.dart`, the log-in
/// connector and the tests importing a state file that was gone — seventeen
/// analyzer errors — and the closing line's "run `frx doctor`" answered ✓.
/// Likewise `remove --kind service` under `dependencies.dart`, and a model
/// still imported by a state field.
///
/// Only URIs into the project's own packages are judged: whether a
/// dependency's file exists is pub's question, answered from a resolution this
/// does not read. `part` directives are left to `checkGeneratedParts` — a
/// missing generated part means build_runner has not run, not that something
/// was deleted.
void checkDanglingImports(FrxWorkspace repo, List<Finding> into) {
  final packages = repo.packageLibs();
  for (final package in FrxWorkspace.sourcePackages) {
    for (final tree in const ['lib', 'test']) {
      final dir = Directory(p.join(repo.root.path, package, tree));
      if (!dir.existsSync()) {
        continue;
      }
      for (final file in sourceIndex.filesUnder(dir)) {
        if (FrxWorkspace.isGenerated(file.path)) {
          continue;
        }
        // Read as text, not parsed: the audit parses only what it has to, and
        // every file has imports. A directive is one line of a known shape.
        final source = sourceIndex.sourceOf(file);
        for (final m in _directive.allMatches(source)) {
          final value = m.group(2)!;
          final target = workspaceTarget(
            value,
            from: file.absolute.path,
            packages: packages,
          );
          // A generated file that is not there yet is build_runner's to write.
          if (target == null ||
              FrxWorkspace.isGenerated(target) ||
              File(target).existsSync()) {
            continue;
          }

          final at = positionInSource(
            source,
            m.start + m[0]!.lastIndexOf(value),
          );
          into.add(
            Finding.error(
              '${p.relative(file.path, from: repo.root.path)} imports '
              '"$value", which does not exist.',
              file: file.path,
              line: at.line,
              column: at.column,
            ),
          );
        }
      }
    }
  }
}

/// An `import` or `export` directive at the start of a line, and its URI.
final _directive = RegExp(
  r'''^\s*(import|export)\s+r?['"]([^'"]+)['"]''',
  multiLine: true,
);
