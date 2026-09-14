import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../util/console.dart';
import 'inventory.dart';

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

    printInventory(
      title: 'AppState substates  (${source.file.path})',
      columns: ('FIELD', 'TYPE'),
      rows: [for (final s in substates) (s.field, s.type)],
      unit: 'field',
    );
    return 0;
  }
}
