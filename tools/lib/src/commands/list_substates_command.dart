import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../util/console.dart';

/// Lists the substates currently composed into `AppState`, read via AST.
///
/// Read-only. It is both a useful inventory command and the proof that the
/// AST pipeline (locate → parse → inspect `AppState`) works before any command
/// starts mutating source. `--json` emits a machine-readable form (the VSCode
/// tree view consumes it).
class ListSubstatesCommand extends Command<int> {
  ListSubstatesCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON ({substates:[{field,type,file}]}) instead of a table.',
      )
      ..addOption(
        'root',
        help:
            'Repo root to search from. Defaults to walking up from the current '
            'directory until app_state.dart is found.',
      );
  }

  @override
  String get name => 'list-substates';

  @override
  String get description =>
      'List the substates composed into AppState (parsed via AST).';

  @override
  List<String> get aliases => ['ls'];

  @override
  Future<int> run() async {
    final root = argResults?['root'] as String?;
    final source = AppStateSource.locate(startDir: root);
    final substates = source.readSubstates();

    if (argResults!.flag('json')) {
      console.out.writeln(
        jsonEncode({
          'substates': [
            for (final s in substates)
              {
                'field': s.field,
                'type': s.type,
                // Non-…State framework fields (e.g. `wait`) have no folder.
                'file': s.isSubstate
                    ? SubstateArtifact.parse(
                        s.field,
                      ).stateFile(source.reduxDir).path
                    : null,
              },
          ],
        }),
      );
      return 0;
    }

    console.out.writeln('AppState substates  (${source.file.path})');
    console.out.writeln();

    if (substates.isEmpty) {
      console.out.writeln('  (none found)');
      return 0;
    }

    final fieldWidth = substates
        .map((s) => s.field.length)
        .fold(5, (a, b) => a > b ? a : b);

    console.out.writeln('  ${'FIELD'.padRight(fieldWidth)}  TYPE');
    console.out.writeln('  ${'-' * fieldWidth}  ${'-' * 20}');
    for (final s in substates) {
      console.out.writeln('  ${s.field.padRight(fieldWidth)}  ${s.type}');
    }
    console.out.writeln();
    console.out.writeln('${substates.length} field(s).');
    return 0;
  }
}
