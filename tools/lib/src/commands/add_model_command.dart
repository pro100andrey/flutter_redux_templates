import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/artifact_templates.dart';
import '../scaffold/package_scaffold.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a `@freezed` model in the `models` package — a single-variant
/// class by default, a sealed union with `--case` (repeatable, ≥2).
class AddModelCommand extends WritingCommand {
  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  void describeArgs(ArgParser parser) {
    parser
      // Was `--json`, which collided with the machine-output flag every other
      // writing command now carries. A flag that means "serialize the model" on
      // one command and "serialize the result" on the rest is the drift the
      // surface criterion prunes, so this one moved.
      ..addFlag(
        'serializable',
        negatable: false,
        help: 'Also generate fromJson/toJson (adds the .g.dart part).',
      )
      ..addMultiOption(
        'case',
        abbr: 'c',
        help:
            'Union case name (repeatable, ≥2) — makes the model a sealed '
            'union with one factory per case, e.g. -c loading -c success.',
      );
  }

  @override
  String get name => 'add-model';

  @override
  String get description =>
      'Scaffold a freezed model (or sealed union) in the models package.';

  @override
  String get invocation =>
      'frx add-model <name> [--serializable] [-c <case> …]';

  @override
  List<String> get aliases => ['am'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // The name first: a usage error is about the command line and this is
    // about the workspace, so checking the workspace first answered `frx
    // add-model` with no argument by sending the user to create a package.
    final name = requireName();

    // `models` is optional, so this is a target-existence check like the one
    // `add-action` runs on a substate — not a package to conjure. Writing the
    // file into a directory that is not a package produced a model that
    // compiled into nothing and a workspace that still did not resolve it.
    if (!PackageKind.models.existsIn(repo)) {
      refuse(
        'There is no "models" package in this workspace. '
        'Create it with `frx add-package models`, then run this again.',
      );
    }
    final caseArgs = results['case'] as List<String>;
    if (caseArgs.length == 1) {
      usageException('A union needs at least two --case values.');
    }

    final List<Casing> cases;
    try {
      cases = caseArgs.map(Casing.parse).toList();
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final file = p.join(repo.modelsLib.path, '${name.snake}.dart');
    final serializable = results['serializable'] as bool;

    return WritePlan(
      changes: Changeset([
        WriteFile(
          file,
          cases.isEmpty
              ? ArtifactTemplates.model(name, json: serializable)
              : ArtifactTemplates.modelUnion(name, cases, json: serializable),
        ),
      ]),
      header: cases.isEmpty
          ? 'Model "${name.pascal}"'
          : 'Model (union, ${cases.length} cases) "${name.pascal}"',
    );
  }
}
