// The repository's task runner: `package:xtask` plus this project's verbs.
//
// The tasks are data, in ../xtask.yaml. What lives here is the handful with
// real logic in them — a version bump across seven files, a VS Code profile
// looked up in the editor's own storage — because the file cannot branch, and
// a task that needs a condition becomes a verb. `dart run :xtask <task>`
// resolves to this file by name; `dart install .` does not put it on PATH,
// because `executables:` in pubspec.yaml names `frx` alone.
//
// Under bin/ rather than tool/, and the reason the old program gave for the
// opposite no longer holds: `dart run :xtask` reaches bin/xtask.dart and
// nothing else, and the executables map is what keeps it off PATH.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xtask/xtask.dart';

/// The repository root — where xtask.yaml is — found from the task's own
/// directory upwards, the way the engine found the file.
///
/// Not `Platform.script`: under `dart run :xtask` that is a snapshot in
/// `.dart_tool/pub/bin/`, three directories from anywhere.
String rootOf(VerbContext context) {
  for (var dir = context.workingDirectory; ; dir = p.dirname(dir)) {
    if (File(p.join(dir, 'xtask.yaml')).existsSync()) {
      return dir;
    }
    if (p.dirname(dir) == dir) {
      throw StateError('no xtask.yaml above ${context.workingDirectory}');
    }
  }
}

String toolsOf(VerbContext context) => p.join(rootOf(context), 'tools');
String extOf(VerbContext context) => p.join(toolsOf(context), 'vscode');

Future<void> main(List<String> args) async {
  // Assigned, not discarded: `runXtask` answers with the exit code, and a
  // caller that throws it away reports success for every outcome.
  exitCode = await runXtask(
    args,
    verbs: {
      'cli-verify': cliVerify,
      'dist': dist,
      'version': version,
      'pack-template': packTemplate,
      'install-ext': installExt,
      'profiles': profiles,
      'uninstall': uninstall,
      'format-workspace': formatWorkspace,
      'codegen-drift': codegenDrift,
    },
  );
}

// --- what the verbs read --------------------------------------------------

String extVersion(VerbContext context) {
  try {
    final manifest =
        jsonDecode(
              File(p.join(extOf(context), 'package.json')).readAsStringSync(),
            )
            as Map<String, Object?>;
    return manifest['version'] as String? ?? '?';
  } on Object {
    return '?';
  }
}

String vsixOf(VerbContext context) => 'frx-${extVersion(context)}.vsix';

/// Human-readable size, the way `du -h` would put it.
String sizeOf(File f) {
  final bytes = f.lengthSync();
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)}M';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).round()}K';
  }
  return '${bytes}B';
}

/// Runs [exe] quietly and returns its stdout, or null when it could not run
/// or failed — for questions, not for work. Work goes through
/// [VerbContext.run], which streams and resolves the program the way a
/// `run:` body does.
Future<String?> ask(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args, runInShell: Platform.isWindows);
    return r.exitCode == 0 ? (r.stdout as String) : null;
  } on ProcessException {
    return null;
  }
}

/// The options a person passes after `--`: `--profile <name>`, `--code <exe>`,
/// `--names`. `$PROFILE` and `$CODE` stand in for the first two, as they did
/// for make — set the profile once and forget it.
final class Options {
  Options._(this.profile, this.code, this.names);

  factory Options.of(VerbContext context) {
    var profile = context.env['PROFILE'];
    var code = context.env['CODE'];
    var names = false;
    final args = context.args;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--profile' when i + 1 < args.length:
          profile = args[++i];
        case '--code' when i + 1 < args.length:
          code = args[++i];
        case '--names':
          names = true;
        case final other:
          throw ArgumentError('unknown argument `$other`');
      }
    }
    return Options._(
      profile == null || profile.isEmpty ? null : profile,
      code == null || code.isEmpty ? 'code' : code,
      names,
    );
  }

  /// The VS Code profile, or null for the Default one.
  final String? profile;

  /// The `code` executable.
  final String code;

  final bool names;

  /// `--profile <name>` for `code`, when there is one.
  List<String> get profileArgs => switch (profile) {
    final name? => ['--profile', name],
    null => const [],
  };
}

// --- the CLI ----------------------------------------------------------------

/// After `dart install .`: which frx answers on PATH, or that none does.
Future<int> cliVerify(VerbContext context) async {
  final version = await ask('frx', ['--version']);
  if (version != null) {
    context.log('✓ ${version.trim()} on PATH');
  } else {
    context.log(
      '⚠ installed, but frx is not on PATH — add '
      '~/Library/Application Support/Dart/install/bin (macOS) or '
      '~/.dart/install/bin',
    );
  }
  return ExitCode.success;
}

/// `dart compile exe` builds for the host and does not cross-compile. Worth
/// having locally to check what an install actually gets: `dart install` and
/// `dart run` both take different paths through the SDK than an AOT snapshot
/// does — and it is the binary a release attaches, built on each platform's
/// own runner.
///
/// The CLI is self-contained: the template `frx create` unpacks is a
/// generated Dart source, and the skills and contract it writes are string
/// constants, so the binary needs no files beside it. Three things are then
/// asked of it, each a different way an AOT build can be broken while still
/// linking: it runs at all, it parses a real project (the analyzer front end
/// works), and `create --dry-run` decodes the embedded template archive — the
/// one artifact that is a data blob rather than code, and so the one a compile
/// could plausibly mangle. All three cost about a second and need no network.
Future<int> dist(VerbContext context) async {
  final tools = toolsOf(context);
  Directory(p.join(tools, 'dist')).createSync(recursive: true);
  final out = p.join('dist', Platform.isWindows ? 'frx.exe' : 'frx');
  final compiled = await context.run([
    'dart',
    'compile',
    'exe',
    'bin/frx.dart',
    '-o',
    out,
  ]);
  if (compiled != ExitCode.success) {
    return compiled;
  }
  final frx = p.join(tools, out);
  final smoke = Directory.systemTemp.createTempSync('frx_smoke_');
  try {
    for (final args in [
      ['--version'],
      ['list-substates', '--root', '..'],
      ['create', 'smoke_app', '--dry-run', '--target', smoke.path],
    ]) {
      final ran = await context.run([frx, ...args]);
      if (ran != ExitCode.success) {
        return ran;
      }
    }
  } finally {
    smoke.deleteSync(recursive: true);
  }
  context.log('${sizeOf(File(frx))}  $out');
  return ExitCode.success;
}

/// One version, and seven files that carry it: the three declarations
/// (pubspec.yaml, version.dart, package.json with its lock), the CHANGELOG
/// heading the Marketplace shows, and two derived from the running CLI — the
/// `.frx-owned` stamp `update-skills` writes, and the template that packs it.
/// The release refuses a tag the declarations disagree with, but nothing
/// failed on the other three: v0.3.0 and v0.3.1 both shipped a template
/// stamped with the version before. So this does all seven, in the order they
/// derive — the stamp from the constant, the template from the stamp.
///
/// Everything that can refuse is asked before anything is written: the
/// version's shape (no `+build`, which npm strips, so the three could never
/// agree), both patterns, the CHANGELOG heading. What is left can fail only
/// on a tool, and says which step to rerun.
Future<int> version(VerbContext context) async {
  if (context.args.length != 1) {
    context.log('usage: dart run :xtask version -- 1.2.3');
    return ExitCode.invalidFile;
  }
  final v = context.args.single;
  if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$').hasMatch(v)) {
    context.log(
      '"$v" is not a version npm keeps as written — '
      'MAJOR.MINOR.PATCH, optionally -prerelease, no +build',
    );
    return ExitCode.invalidFile;
  }
  final tools = toolsOf(context);
  final edits = <(File, String)>[];
  for (final (path, pattern, replacement) in [
    (
      p.join(tools, 'pubspec.yaml'),
      RegExp(r'^version: .*$', multiLine: true),
      'version: $v',
    ),
    (
      p.join(tools, 'lib', 'src', 'version.dart'),
      RegExp("frxVersion = '[^']*'"),
      "frxVersion = '$v'",
    ),
  ]) {
    final file = File(path);
    final before = file.readAsStringSync();
    if (!pattern.hasMatch(before)) {
      context.log('$path: nothing matched ${pattern.pattern}');
      return ExitCode.taskFailed;
    }
    edits.add((file, before.replaceFirst(pattern, replacement)));
  }

  // The notes accumulate under `## Unreleased`; the bump names them. A
  // rerun finds them named already. Neither is a release with no notes.
  final changelog = File(p.join(tools, 'vscode', 'CHANGELOG.md'));
  final notes = changelog.readAsStringSync();
  final unreleased = RegExp(r'^## Unreleased$', multiLine: true);
  if (unreleased.hasMatch(notes)) {
    edits.add((changelog, notes.replaceFirst(unreleased, '## $v')));
  } else if (!notes.contains(
    RegExp('^## ${RegExp.escape(v)}\$', multiLine: true),
  )) {
    context.log(
      '${changelog.path}: no `## Unreleased` to name $v, '
      'and no `## $v` already — the release would have no notes',
    );
    return ExitCode.taskFailed;
  }

  final bumped = await context.run([
    'npm',
    'version',
    v,
    '--no-git-tag-version',
    '--allow-same-version',
  ], workingDirectory: 'tools/vscode');
  if (bumped != ExitCode.success) {
    return bumped;
  }
  for (final (file, content) in edits) {
    file.writeAsStringSync(content);
  }

  final verified = await context.run([
    'dart',
    'test',
    'test/version_test.dart',
  ], workingDirectory: 'tools');
  if (verified != ExitCode.success) {
    context.log(
      'the three files disagree — see `dart test test/version_test.dart`',
    );
    return ExitCode.taskFailed;
  }

  // `dart run` compiles version.dart as just written, so the stamp is $v.
  for (final (task, what) in [
    ('skills', 'the .frx-owned stamp'),
    ('template', 'the template'),
  ]) {
    final ran = await context.run([
      'dart',
      'run',
      ':xtask',
      task,
    ], workingDirectory: 'tools');
    if (ran != ExitCode.success) {
      context.log(
        '$what is still the old version — '
        'rerun `cd tools && dart run :xtask $task`',
      );
      return ran;
    }
  }

  context
    ..log(
      '✓ $v in all seven: the declarations, the CHANGELOG, the stamp, '
      'the template',
    )
    ..log('')
    ..log("  git commit -am 'v$v' && git push origin main")
    ..log('  # once CI on that commit is green:')
    ..log('  git tag v$v && git push origin v$v');
  return ExitCode.success;
}

/// The archive `frx create` unpacks — a derived artifact like docs/flows, and
/// it goes stale the moment the product moves. `cli-test` catches that:
/// template_freshness_test.dart is part of it.
///
/// None of the three flags is adjustable. `-f base64` keeps the payload a
/// single string literal; `-f bytes` writes the same archive as a const list
/// 4.7× the size. `-n frx` names the constant `create_command.dart` imports.
/// The manifest is not passed because `pack` reads ../mold.yaml, beside the
/// project it packs.
Future<int> packTemplate(VerbContext context) async {
  const out = 'lib/src/template/template.g.dart';
  final packed = await context.run([
    'dart',
    'run',
    'mold:mold',
    'pack',
    '..',
    '-f',
    'base64',
    '-n',
    'frx',
    '-o',
    out,
  ]);
  if (packed != ExitCode.success) {
    return packed;
  }
  context.log(
    '✓ ${sizeOf(File(p.join(context.workingDirectory, out)))} embedded — run '
    "'dart test test/template_freshness_test.dart' to confirm",
  );
  return ExitCode.success;
}

// --- the workspace ----------------------------------------------------------

/// Every hand-written Dart file of the workspace is formatted.
///
/// Generated files are committed but formatted by their builders, so they are
/// left out — which is a question for git, not for a glob: `git ls-files` with
/// the three exclusions is exactly the set, and a glob would have to restate
/// it.
Future<int> formatWorkspace(VerbContext context) async {
  final listed = await Process.run('git', [
    'ls-files',
    '*.dart',
    ':!*.g.dart',
    ':!*.freezed.dart',
    ':!*.gr.dart',
  ], workingDirectory: context.workingDirectory);
  if (listed.exitCode != 0) {
    context.log('git ls-files failed: ${listed.stderr}');
    return ExitCode.taskFailed;
  }
  final files = (listed.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (files.isEmpty) {
    context.log('git ls-files named no Dart file — nothing was checked');
    return ExitCode.taskFailed;
  }
  return context.run([
    'dart',
    'format',
    '--output=none',
    '--set-exit-if-changed',
    ...files,
  ]);
}

/// The committed generated code is what its sources generate.
///
/// Regenerates everything and fails if the committed output moved — a change
/// that edits a source and forgets to commit the regenerated part is caught
/// here. `--workspace` builds every member from the `app` package. Asked of
/// `git status --porcelain` rather than `git diff`, so a NEW generated file
/// that was never committed fails too, not only a modified one.
Future<int> codegenDrift(VerbContext context) async {
  final built = await context.run([
    'dart',
    'run',
    'build_runner',
    'build',
    '--delete-conflicting-outputs',
    '--workspace',
  ], workingDirectory: 'app');
  if (built != ExitCode.success) {
    return built;
  }
  final status = await Process.run('git', [
    'status',
    '--porcelain',
    '--',
    '*.g.dart',
    '*.freezed.dart',
    '*.gr.dart',
  ], workingDirectory: context.workingDirectory);
  if (status.exitCode != 0) {
    context.log('git status failed: ${status.stderr}');
    return ExitCode.taskFailed;
  }
  final drift = (status.stdout as String).trim();
  if (drift.isEmpty) {
    return ExitCode.success;
  }
  context
    ..log('Committed generated code is stale — regenerate and commit:')
    ..log(
      '  (cd app && dart run build_runner build --delete-conflicting-outputs '
      '--workspace)',
    )
    ..log(drift);
  return ExitCode.taskFailed;
}

// --- the extension ----------------------------------------------------------

/// Where VS Code keeps the user's profiles on this platform.
String? get userDir {
  final env = Platform.environment;
  if (Platform.isMacOS) {
    return p.join(
      env['HOME']!,
      'Library',
      'Application Support',
      'Code',
      'User',
    );
  }
  if (Platform.isLinux) {
    final config = env['XDG_CONFIG_HOME'] ?? p.join(env['HOME']!, '.config');
    return p.join(config, 'Code', 'User');
  }
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    return appData == null ? null : p.join(appData, 'Code', 'User');
  }
  return null;
}

/// The profile names. The Default profile is implicit — it has no entry in
/// storage.json.
List<String> profileNames() {
  final names = ['Default'];
  final dir = userDir;
  if (dir == null) {
    return names;
  }
  final storage = File(p.join(dir, 'globalStorage', 'storage.json'));
  if (!storage.existsSync()) {
    return names;
  }
  try {
    final data = jsonDecode(storage.readAsStringSync()) as Map<String, Object?>;
    for (final profile
        in data['userDataProfiles'] as List<Object?>? ?? const []) {
      final name = (profile as Map<String, Object?>?)?['name'] as String?;
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }
  } on Object {
    // Unreadable storage: the Default profile is still a fact.
  }
  return names;
}

/// Installs the built VSIX into the profile — `ext` after packaging it,
/// `ext-install` as it stands.
Future<int> installExt(VerbContext context) async {
  final options = Options.of(context);
  final profile = options.profile;
  if (profile != null) {
    final known = profileNames();
    if (!known.contains(profile)) {
      context.log(
        'No VSCode profile named "$profile". Known:\n'
        '${known.map((n) => '  $n').join('\n')}',
      );
      return ExitCode.taskFailed;
    }
  }
  final vsix = vsixOf(context);
  if (!File(p.join(extOf(context), vsix)).existsSync()) {
    context.log("missing vscode/$vsix — run 'package'");
    return ExitCode.taskFailed;
  }
  if (profile == null) {
    context.log(
      "⚠ --profile is unset — installing into VSCode's Default profile. "
      "'profiles' shows the others.",
    );
  }
  // `--force` because the version rarely changes between local builds, and
  // without it VSCode declines to reinstall the same version.
  final installed = await context.run([
    options.code,
    ...options.profileArgs,
    '--install-extension',
    vsix,
    '--force',
  ]);
  if (installed != ExitCode.success) {
    return installed;
  }
  final where = profile == null ? 'the Default profile' : 'profile "$profile"';
  context.log("✓ installed into $where — now run 'Developer: Reload Window'");
  return ExitCode.success;
}

/// The profiles on this machine, each with the frx build it holds.
Future<int> profiles(VerbContext context) async {
  final options = Options.of(context);
  final all = profileNames();
  if (options.names) {
    all.forEach(context.log);
    return ExitCode.success;
  }
  if (await ask(options.code, ['--version']) == null) {
    context.log(
      'the `${options.code}` command is not on PATH.\n'
      '  In VSCode: Command Palette → '
      "'Shell Command: Install code command in PATH'.",
    );
    return ExitCode.missingTool;
  }
  context
    ..log('${'PROFILE'.padRight(16)}  frx')
    ..log('${'-' * 16}  ${'-' * 16}');
  for (final name in all) {
    final listed = await ask(options.code, [
      if (name != 'Default') ...['--profile', name],
      '--list-extensions',
      '--show-versions',
    ]);
    final installed = (listed ?? '')
        .split('\n')
        .where((l) => l.toLowerCase().contains('frx'))
        .join(', ');
    context.log('${name.padRight(16)}  ${installed.isEmpty ? '—' : installed}');
  }
  return ExitCode.success;
}

/// Removes both. Neither step's failure stops the other: an extension that was
/// never installed, or a binary that was, is not a reason to leave the other
/// one in place — which is why this is a verb and not two `run:` bodies.
Future<int> uninstall(VerbContext context) async {
  final options = Options.of(context);
  await context.run([
    options.code,
    ...options.profileArgs,
    '--uninstall-extension',
    'pro100dev.frx',
  ]);
  await context.run(['dart', 'uninstall', 'tools'], workingDirectory: 'tools');
  return ExitCode.success;
}
