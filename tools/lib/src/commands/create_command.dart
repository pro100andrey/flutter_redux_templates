import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;

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

      if (applying) {
        await const Unbundler().unbundleBytes(
          source: base64Decode(kFrxTemplateBase64),
          targetDir: target,
          vars: vars,
        );
      }

      for (final warning in warnings) {
        console.err.writeln('⚠ $warning');
      }
      _report(
        plan,
        target: target,
        vars: vars,
        applied: applying,
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

  /// Say what was (or would be) created.
  void _report(
    UnpackPlan plan, {
    required String target,
    required Map<String, String> vars,
    required bool applied,
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
