import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/artifact_templates.dart';
import '../scaffold/package_scaffold.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a Retrofit `@RestApi()` client in `http_client/lib/api/`.
class AddRetrofitCommand extends WritingCommand {
  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  String get name => 'add-retrofit';

  @override
  String get description =>
      'Scaffold a Retrofit @RestApi client in the http_client package.';

  @override
  String get invocation => 'frx add-retrofit <name>';

  @override
  List<String> get aliases => ['ar'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // See `add-model`: the package is optional, so its absence is a target
    // that is not there, answered the way every other missing target is.
    if (!PackageKind.httpClient.existsIn(repo)) {
      refuse(
        'There is no "http_client" package in this workspace. '
        'Create it with `frx add-package http_client`, then run this again.',
      );
    }

    final name = requireName();

    final file = p.join(repo.httpApi.path, '${name.snake}.dart');

    return WritePlan(
      changes: Changeset([WriteFile(file, ArtifactTemplates.retrofit(name))]),
      header: 'Retrofit service "${name.pascal}Service"',
    );
  }
}
