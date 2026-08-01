import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/artifact_templates.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a `ThemeExtension` in `ui/lib/theme/extensions/`.
class AddThemeExtensionCommand extends WritingCommand {
  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  String get name => 'add-theme-extension';

  @override
  String get description => 'Scaffold a ThemeExtension in the ui package.';

  @override
  String get invocation => 'frx add-theme-extension <name>';

  @override
  List<String> get aliases => ['ate'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final name = requireName();

    final file = p.join(repo.uiThemeExtensions.path, '${name.snake}.dart');

    return WritePlan(
      changes: Changeset([
        WriteFile(file, ArtifactTemplates.themeExtension(name)),
      ]),
      header: 'ThemeExtension "${name.pascal}"',
    );
  }
}
