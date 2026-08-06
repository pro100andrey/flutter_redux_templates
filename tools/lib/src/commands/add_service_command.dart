import 'package:args/args.dart';

import '../engine/changeset.dart';
import '../model/artifact_name.dart';
import '../scaffold/artifact_templates.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';
import '../model/artifact_files.dart';

/// Scaffolds a service + listener pair under `business/lib/redux/services/`.
class AddServiceCommand extends WritingCommand {
  @override
  String get name => 'add-service';

  @override
  String get description =>
      'Scaffold a service + Redux dispatcher under redux/services.';

  @override
  String get invocation => 'frx add-service <name>';

  @override
  List<String> get aliases => ['asvc'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // See [ArtifactName]: `Sync` and `SyncService` are one artifact.
    final name = ArtifactName.serviceStem(requireName());

    final files = ArtifactFiles.serviceFiles(repo, name);

    return WritePlan(
      changes: Changeset([
        WriteFile(files.service, ArtifactTemplates.service(name)),
        WriteFile(files.dispatcher, ArtifactTemplates.serviceDispatcher(name)),
      ]),
      header: 'Service "${name.pascal}Service"',
    );
  }
}
