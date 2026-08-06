import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/package_scaffold.dart';
import '../template/template.g.dart';
import '../util/console.dart';
import 'options.dart';

/// Materialises this monorepo under a new name.
///
/// **The template is this repository**, packed by `mold` and embedded as base64
/// in `lib/src/template/template.g.dart`, so `frx create` needs neither a
/// checkout nor a network — install frx once and scaffold anywhere. What gets
/// renamed is declared in the repo's `mold.yaml`, which travels inside the
/// archive; nothing about the renaming lives here.
///
/// **The template has no placeholders in its source**, which is the whole point:
/// it builds, runs and has tests, so it stays current by being the thing we
/// actually use. Its identity token is `flutter_application_1` — exactly what
/// `flutter create flutter_application_1` emits, so the platform folders can be
/// regenerated at any Flutter upgrade and diffed against ours.
///
/// **`--without` is what makes the optional packages optional.** `add-package`
/// exists to put `models`, `http_client` or `storage` back into a project that
/// does not have them, and until now nothing could produce such a project: the
/// archive is the whole repository, and every member came with it. What may be
/// dropped is not a list kept here — it is read off the archive, as "no Dart
/// file outside the package imports it", so `storage` is refused by the same
/// rule that would start refusing `http_client` the day something wires it up.
///
/// **It deliberately does not emit the changeset format** the other writing
/// commands share. That format carries a unified diff per change so a reviewer
/// can see an edit that has not happened yet; here every one of five hundred–odd
/// files is a creation into an empty directory, so the diffs would be the files
/// themselves and the plan would be larger than the archive. Counts and the
/// resolved identity are what a caller can act on.
class CreateCommand extends Command<int> {
  CreateCommand() {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'Directory to create. Defaults to ./<project_name>.',
      )
      ..addOption(
        'org',
        help:
            'Reverse-DNS organisation prefix — the stem of the Android '
            'applicationId, the Apple bundle identifier and the Kotlin package.',
        defaultsTo: 'com.example',
      )
      ..addOption(
        'title',
        help:
            'The name shown to the user, on the device and in the app itself. '
            'Defaults to <project_name> in Title Case.',
      )
      ..addMultiOption(
        'without',
        allowed: [for (final k in PackageKind.values) k.dir],
        help:
            'Leave an optional package out of the new project. Repeatable, or '
            'comma-separated. `frx add-package <kind>` puts one back.',
        valueHelp: 'package',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'List what would be written, without writing it.',
      )
      ..addFlag('json', negatable: false, help: kMachineHelp);
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new project from this monorepo template.';

  @override
  String get invocation => 'frx create <project_name> [options]';

  /// A Dart package name — and the stem every platform identifier derives from.
  static final _projectName = RegExp(r'^[a-z][a-z0-9_]*$');

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Expected exactly one <project_name> argument.');
    }
    final name = results.rest.single;
    if (!_projectName.hasMatch(name)) {
      usageException(
        '"$name" is not a usable project name. Use lower_snake_case starting '
        'with a letter: it becomes the Dart package name, and every platform '
        'identifier is derived from it.',
      );
    }

    final target = p.absolute(results.option('target') ?? name);
    final vars = {
      'project_name': name,
      'org': results.option('org')!,
      // A display name is not a mechanical function of a package name —
      // `acme_crm` should read "Acme CRM", which no transform can know. Title
      // Case is a decent guess, and `--title` is how you disagree with it.
      'app_title': results.option('title') ?? _titleCase(name),
    };

    final asJson = results.flag('json');
    final applying = !results.flag('dry-run');
    final warnings = <String>[];
    // `allowed:` on the option has already refused anything not in the
    // catalogue, so every name here resolves.
    final without = [
      for (final name in results.multiOption('without'))
        PackageKind.byName(name)!,
    ];

    try {
      // Planned in both cases, and then applied. The plan is the unpack minus
      // the writes, so running it first costs one in-memory substitution pass
      // and buys the same honest counts on both paths — a report that only knew
      // how to describe a rehearsal would have to guess at the real thing.
      final plan = const Unbundler().plan(
        bytes: base64Decode(kFrxTemplateBase64),
        targetDir: target,
        vars: vars,
        onWarning: warnings.add,
      );

      final reached = _importersOf(plan, omitted: without);
      if (reached.isNotEmpty) {
        _refuse(reached, target: target, asJson: asJson);
        return 70;
      }

      if (applying) {
        await const Unbundler().unbundleBytes(
          source: base64Decode(kFrxTemplateBase64),
          targetDir: target,
          vars: vars,
        );
        if (!await _prune(without, target: target)) return 70;
      }

      for (final warning in warnings) {
        console.err.writeln('⚠ $warning');
      }
      _report(
        UnpackPlan(_kept(plan, omitted: without)),
        target: target,
        vars: vars,
        applied: applying,
        omitted: without,
        asJson: asJson,
      );
      return 0;
    } on ValidationException catch (e) {
      // The destination is unusable, or a variable did not resolve. Nothing has
      // been written: mold validates before it writes.
      for (final error in e.errors) {
        console.err.writeln('✗ $error');
      }
      return 70;
    }
  }

  /// Removes [omitted] from the freshly unpacked tree at [target]. False when
  /// something went wrong, having said so and put the packages back.
  ///
  /// **Unpacked whole and then pruned**, rather than filtered on the way out:
  /// `Unbundler` takes no file filter, and re-implementing its write path to
  /// skip entries would fork the very computation `plan` exists to keep honest.
  ///
  /// One kind at a time, because two omissions can touch one pubspec and an
  /// `EditFile` carries the `before` it was planned against — a second edit
  /// planned against the same disk would overwrite the first. One transaction
  /// around the whole loop, so the outcome is a project with every package or a
  /// project with the ones asked for, and never a half-pruned tree.
  Future<bool> _prune(
    List<PackageKind> omitted, {
    required String target,
  }) async {
    if (omitted.isEmpty) return true;

    final transaction = WriteTransaction();
    try {
      await withTransaction(transaction, () async {
        for (final kind in omitted) {
          await apply(
            Changeset(PackageScaffold.omit(target, kind)),
            format: false,
          );
        }
      });
    } on Object catch (error) {
      final restoreErrors = transaction.rollback();
      console.err
        ..writeln('✗ could not leave the packages out: $error')
        ..writeln(
          restoreErrors.isEmpty
              ? '  The project was created with every package — nothing was '
                    'pruned. `frx create --without` again, or delete it and '
                    'start over.'
              : '  The rollback did not fully succeed:\n'
                    '${restoreErrors.map((e) => '    $e').join('\n')}',
        );
      return false;
    }
    await settle(transaction, format: false);
    return true;
  }

  /// Says which omitted packages are imported, and by what.
  ///
  /// Structured when the caller asked for structure. Every success path of this
  /// command emits one JSON object, and the list of importing files is exactly
  /// what a caller would surface — a refusal that dropped to prose would be the
  /// one outcome `--json` could not read.
  void _refuse(
    Map<PackageKind, List<String>> reached, {
    required String target,
    required bool asJson,
  }) {
    if (asJson) {
      console.out.writeln(
        jsonEncode({
          'command': name,
          'applied': false,
          'target': target,
          'error': 'imported',
          'imported': {
            for (final entry in reached.entries) entry.key.dir: entry.value,
          },
        }),
      );
      return;
    }

    for (final entry in reached.entries) {
      console.err.writeln(
        '✗ "${entry.key.dir}" cannot be left out — '
        '${entry.value.length} file(s) import it:',
      );
      for (final file in entry.value.take(5)) {
        console.err.writeln('    $file');
      }
      if (entry.value.length > 5) {
        console.err.writeln('    … and ${entry.value.length - 5} more');
      }
    }
  }

  /// The planned files that survive [omitted] — what the report has to count,
  /// since the ones under an omitted package are not going to be there.
  ///
  /// A [PlannedFile]'s `to` is its path *inside the archive* after renaming,
  /// not its destination on disk, so the package directory it is tested against
  /// is the bare `models`, not `<target>/models`. Joining the target here made
  /// every path resolve against the current directory instead, and a package's
  /// own files stopped counting as its own.
  static List<PlannedFile> _kept(
    UnpackPlan plan, {
    required List<PackageKind> omitted,
  }) {
    if (omitted.isEmpty) return plan.files;
    return [
      for (final file in plan.files)
        if (!omitted.any((k) => p.isWithin(k.dir, file.to))) file,
    ];
  }

  /// For each omitted package, the Dart files outside it that import it.
  ///
  /// **Derived from the archive rather than declared**, which is the whole
  /// safety of `--without`: `storage` is optional in the same sense the other
  /// two are — it has its own pubspec and `add-package` can create it — and
  /// `business` imports it in three places, so leaving it out produces a project
  /// that does not compile. A hardcoded list of what may be dropped would be a
  /// second copy of that fact, and would go stale the first time somebody wires
  /// `http_client` up.
  static Map<PackageKind, List<String>> _importersOf(
    UnpackPlan plan, {
    required List<PackageKind> omitted,
  }) {
    final found = <PackageKind, List<String>>{};
    for (final kind in omitted) {
      final importers = [
        for (final file in plan.files)
          if (file.to.endsWith('.dart') &&
              !p.isWithin(kind.dir, file.to) &&
              (file.after ?? '').contains("package:${kind.dir}/"))
            file.to,
      ]..sort();
      if (importers.isNotEmpty) found[kind] = importers;
    }
    return found;
  }

  /// Say what was (or would be) created.
  void _report(
    UnpackPlan plan, {
    required String target,
    required Map<String, String> vars,
    required bool applied,
    required List<PackageKind> omitted,
    required bool asJson,
  }) {
    if (asJson) {
      console.out.writeln(
        jsonEncode({
          'command': name,
          'applied': applied,
          'target': target,
          'files': plan.files.length,
          'replacements': plan.totalReplacements,
          'renamed': plan.renamed.length,
          'without': [for (final k in omitted) k.dir],
          'vars': vars,
        }),
      );
      return;
    }

    // Relative reads better for the common `frx create foo` in the current
    // directory, and turns into a wall of `../..` for anywhere else.
    final relative = p.relative(target);
    final where = relative.startsWith('..') ? target : relative;
    console.out
      ..writeln(
        applied
            ? '✓ Created "${vars['project_name']}" in $where'
            : 'Dry run — nothing written to $where',
      )
      ..writeln(
        '  ${plan.files.length} files · ${plan.totalReplacements} replacements '
        '· ${plan.renamed.length} path(s) renamed',
      )
      ..writeln(
        '  ${vars['org']}.${vars['project_name']} · "${vars['app_title']}"',
      );

    if (omitted.isNotEmpty) {
      console.out.writeln(
        '  without ${[for (final k in omitted) k.dir].join(', ')} — '
        '`frx add-package <kind>` puts one back',
      );
    }

    if (applied) {
      console.out
        ..writeln()
        ..writeln('Next:')
        ..writeln('  cd $where && flutter pub get');
    }
  }

  /// `my_app` → `My App`.
  String _titleCase(String name) => name
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
