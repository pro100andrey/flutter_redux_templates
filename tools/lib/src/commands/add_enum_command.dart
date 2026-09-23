import 'package:args/args.dart';

import '../engine/changeset.dart';
import '../model/artifact_files.dart';
import '../scaffold/artifact_templates.dart';
import '../util/dart_names.dart';
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

    // `values`, `index` and `name` are members every enum already has; a value
    // spelled like one wrote `values_declaration_in_enum`.
    final values = requireCasings(
      valueArgs,
      what: 'value',
      taken: DartNames.enumMembers,
    );

    final file = modelFile(repo, name);

    return WritePlan(
      changes: Changeset([
        WriteFile(file, ArtifactTemplates.enumeration(name, values)),
      ]),
      header:
          'Enum "${name.pascal} (${values.map((v) => v.camel).join(', ')})"',
    );
  }
}
