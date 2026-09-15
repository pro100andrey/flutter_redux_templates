import 'package:args/args.dart';

import '../engine/changeset.dart';
import '../model/artifact_files.dart';
import '../model/artifact_name.dart';
import '../scaffold/artifact_templates.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a `StoreConnector` for the dumb widget of the same name.
///
/// The connector pairs with `frx add-widget <name>` (it imports
/// `package:ui/widgets/<name>.dart`). For a *page* connector + route wiring,
/// use `frx add-page` instead.
class AddConnectorCommand extends WritingCommand {
  @override
  String get name => 'add-connector';

  @override
  String get description => 'Scaffold a StoreConnector for a ui widget.';

  @override
  String get invocation => 'frx add-connector <name>';

  @override
  List<String> get aliases => ['ac'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final typed = requireName();
    // See [ArtifactName]: `Toolbar` and `ToolbarConnector` are one artifact.
    final name = ArtifactName.connectorStem(typed);

    return WritePlan(
      changes: Changeset([
        WriteFile(
          connectorFile(repo, typed),
          ArtifactTemplates.connector(name),
        ),
      ]),
      header: 'Connector "${name.pascal}Connector"',
    );
  }
}
