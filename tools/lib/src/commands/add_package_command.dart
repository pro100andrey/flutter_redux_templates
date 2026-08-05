import 'package:args/args.dart';

import '../engine/changeset.dart';
import '../scaffold/package_scaffold.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Adds a workspace member — a whole pub package, resolved and lintable.
///
/// Exists because the packages it creates are optional. `models` and
/// `http_client` are declared in `business/pubspec.yaml` and imported by
/// nothing, so a project that never talks to a server carries two packages it
/// does not use; a project that starts without them and later needs one had no
/// way to get it back.
///
/// **It is a separate command and not a side effect of `add-model`.** A command
/// named for an artifact should not quietly create a package, edit the root
/// pubspec and change what `pub get` resolves. The commands that write *into*
/// these packages refuse and name this one instead — the same thing
/// `add-action` does when a substate is missing.
class AddPackageCommand extends WritingCommand {
  // No `buildRunner`: a fresh package has nothing to generate, and the build
  // could not run anyway — adding a member invalidates the resolution, so
  // `pub get` has to come first. The closing line says so instead.
  @override
  List<String> get positionals => const ['kind'];

  @override
  String get name => 'add-package';

  @override
  String get description =>
      'Add an optional workspace member (models, http_client, storage).';

  @override
  String get invocation => 'frx add-package <kind>';

  @override
  List<String> get aliases => ['apkg'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    requireArgs();
    final requested = results.rest.first;

    final kind = PackageKind.byName(requested);
    if (kind == null) {
      // Named rather than listed as `allowed:` on an option, because the
      // argument is positional — and because a refusal that says what *is*
      // available is what every other command here does with a bad target.
      refuse(
        '"$requested" is not a package this command knows how to create.\n'
        'Available:\n'
        '${PackageKind.values.map((k) => '  ${k.dir.padRight(12)} ${k.summary}').join('\n')}',
      );
    }

    if (kind.existsIn(repo)) {
      // Not a failure: asking for a package that is already there is the
      // idempotent case, and the rest of this CLI answers it with an empty
      // plan rather than an error.
      return WritePlan(
        changes: Changeset(),
        header: 'Package "${kind.dir}"',
        narrate: () => console.out.writeln(
          '  ${kind.dir} is already a workspace member — nothing to do.',
        ),
      );
    }

    return WritePlan(
      changes: Changeset(PackageScaffold.create(repo, kind)),
      header: 'Package "${kind.dir}" — ${kind.summary}',
      narrate: () => console.out
        ..writeln('  Workspace:')
        ..writeln('    + ${kind.dir}'),
      // A new member changes what `pub get` resolves, and nothing downstream
      // works until it has run — including build_runner, which is why this
      // command declares no build step of its own.
      closing:
          'Run `flutter pub get` from the workspace root before using it — '
          'the new member is not resolved yet.',
    );
  }
}
