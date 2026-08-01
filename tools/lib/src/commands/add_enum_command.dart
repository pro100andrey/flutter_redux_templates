import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/artifact_templates.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a plain enum in the `models` package.
class AddEnumCommand extends WritingCommand {
  @override
  void describeArgs(ArgParser parser) {
    parser.addMultiOption(
      'value',
      abbr: 'v',
      help: 'An enum value (repeatable, ≥1), e.g. -v pending -v done.',
    );
  }

  @override
  String get name => 'add-enum';

  @override
  String get description => 'Scaffold a plain enum in the models package.';

  @override
  String get invocation => 'frx add-enum <name> -v <value> [-v <value> …]';

  @override
  List<String> get aliases => ['ae'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final name = requireName();
    final valueArgs = results['value'] as List<String>;
    if (valueArgs.isEmpty) {
      usageException('Provide at least one --value.');
    }

    final List<Casing> values;
    try {
      values = valueArgs.map(Casing.parse).toList();
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final file = p.join(repo.modelsLib.path, '${name.snake}.dart');

    return WritePlan(
      changes: Changeset([
        WriteFile(file, ArtifactTemplates.enumeration(name, values)),
      ]),
      header:
          'Enum "${name.pascal} (${values.map((v) => v.camel).join(', ')})"',
    );
  }
}
