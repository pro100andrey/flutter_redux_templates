// frx — the build, install and release tasks, as a Dart program.
//
// These lived in a Makefile: `make install PROFILE=Flutter`, `make version
// V=0.3.6`, `make check`. A Makefile is a fine dispatcher and a poor place for
// logic — the version bump was perl because `sed -i` differs between BSD and
// GNU, the profile listing shelled out to python for its JSON, and none of it
// ran on Windows, which this repository otherwise carries a CI leg for. The
// tasks are in the project's own language now, with the project's own tests
// and the project's own `args`: `dart run tool/xtask.dart <task>`.
//
//   dart run tool/xtask.dart                       what you can run
//   dart run tool/xtask.dart install --profile Flutter
//   dart run tool/xtask.dart version 0.3.6
//   dart run tool/xtask.dart check
//
// `PROFILE` and `CODE` in the environment stand in for `--profile` and
// `--code`, as they did for make: set the profile once and forget it.
//
// Under `tool/`, not `bin/`: `dart install` puts every `bin/` entry point on
// PATH, and these tasks are the developer's, not the user's.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// `tools/` — where the pubspec is, whatever directory the task was run from.
final String toolsRoot = p.normalize(
  p.join(p.dirname(Platform.script.toFilePath()), '..'),
);
final String extDir = p.join(toolsRoot, 'vscode');

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'xtask',
          'frx — build, install and release tasks.\n\n'
              'CLI ${_cliVersion()} · extension ${_extVersion()}',
        )
        ..argParser.addOption(
          'profile',
          help:
              'The VSCode profile to install the extension into. VSCode keeps '
              'extensions per profile, so a VSIX put in the Default profile is '
              'invisible while you work in, say, "Flutter". Defaults to '
              r'$PROFILE; unset means the Default profile.',
        )
        ..argParser.addOption(
          'code',
          help: r'The `code` executable. Defaults to $CODE, then `code`.',
        )
        ..addCommand(_Install())
        ..addCommand(_Cli())
        ..addCommand(_Ext())
        ..addCommand(_Package())
        ..addCommand(_ExtInstall())
        ..addCommand(_Profiles())
        ..addCommand(_Dist())
        ..addCommand(_Version())
        ..addCommand(_Check())
        ..addCommand(_Test())
        ..addCommand(_Docs())
        ..addCommand(_Skills())
        ..addCommand(_Contract())
        ..addCommand(_Template())
        ..addCommand(_Uninstall())
        ..addCommand(_Clean());
  try {
    exitCode = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on _Failed catch (e) {
    stderr.writeln(e.message);
    exitCode = e.code;
  }
}

// --- the shared machinery ----------------------------------------------------

/// A task that stopped: what to say, and the code to exit with.
class _Failed implements Exception {
  const _Failed(this.message, {this.code = 1});
  final String message;
  final int code;
}

abstract class _Task extends Command<int> {
  /// `--profile`, or `$PROFILE`, or null for the Default profile.
  String? get profile {
    final flag = globalResults?['profile'] as String?;
    final env = Platform.environment['PROFILE'];
    final value = flag ?? env;
    return value == null || value.isEmpty ? null : value;
  }

  /// `--code`, or `$CODE`, or `code`.
  String get code =>
      (globalResults?['code'] as String?) ??
      Platform.environment['CODE'] ??
      'code';

  /// `--profile <name>` for `code`, when there is one.
  List<String> get profileArgs => switch (profile) {
    final name? => ['--profile', name],
    null => const [],
  };
}

/// Runs [exe] with the caller's terminal, in [cwd] (default `tools/`), and
/// fails the task on a non-zero exit unless [allowFailure].
///
/// In a shell on Windows, where `npm`, `npx` and `code` are `.cmd` shims that
/// `Process.start` cannot exec directly.
Future<int> _run(
  String exe,
  List<String> args, {
  String? cwd,
  bool allowFailure = false,
}) async {
  final proc = await Process.start(
    exe,
    args,
    workingDirectory: cwd ?? toolsRoot,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final result = await proc.exitCode;
  if (result != 0 && !allowFailure) {
    throw _Failed('$exe ${args.join(' ')} exited $result', code: result);
  }
  return result;
}

/// Runs [exe] quietly and returns its stdout, or null when it could not run
/// or failed — for questions, not for work.
Future<String?> _ask(String exe, List<String> args, {String? cwd}) async {
  try {
    final r = await Process.run(
      exe,
      args,
      workingDirectory: cwd ?? toolsRoot,
      runInShell: Platform.isWindows,
    );
    return r.exitCode == 0 ? (r.stdout as String) : null;
  } on ProcessException {
    return null;
  }
}

void _say(String line) => stdout.writeln(line);

String _cliVersion() {
  final pubspec = File(p.join(toolsRoot, 'pubspec.yaml')).readAsStringSync();
  return RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1) ??
      '?';
}

String _extVersion() {
  try {
    final manifest =
        jsonDecode(File(p.join(extDir, 'package.json')).readAsStringSync())
            as Map<String, Object?>;
    return manifest['version'] as String? ?? '?';
  } on Object {
    return '?';
  }
}

String get _vsix => 'frx-${_extVersion()}.vsix';

/// Human-readable size, the way `du -h` would put it.
String _sizeOf(File f) {
  final bytes = f.lengthSync();
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)}M';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).round()}K';
  }
  return '${bytes}B';
}

// --- install -----------------------------------------------------------------

class _Install extends _Task {
  @override
  String get name => 'install';
  @override
  String get description =>
      'CLI + extension (the everyday one): `cli` then `ext`.';

  @override
  Future<int> run() async {
    await _Cli().run();
    return _Ext().runWith(profile: profile, code: code);
  }
}

class _Cli extends _Task {
  @override
  String get name => 'cli';
  @override
  String get description => 'dart install the frx binary onto PATH.';

  @override
  Future<int> run() async {
    await _run('dart', ['pub', 'get']);
    // `dart install <dir>` — the descriptor forms in `dart install --help` are
    // for hosted/git packages; a local checkout installs by path.
    await _run('dart', ['install', '.']);
    final version = await _ask('frx', ['--version']);
    if (version != null) {
      _say('✓ ${version.trim()} on PATH');
    } else {
      _say(
        '⚠ installed, but frx is not on PATH — add '
        '~/Library/Application Support/Dart/install/bin (macOS) or '
        '~/.dart/install/bin',
      );
    }
    return 0;
  }
}

class _Package extends _Task {
  @override
  String get name => 'package';
  @override
  String get description => 'Build the VSIX only.';

  @override
  Future<int> run() async {
    await _run('npm', ['install', '--silent'], cwd: extDir);
    await _run('npm', ['run', 'compile'], cwd: extDir);
    await _run('npx', ['--yes', '@vscode/vsce', 'package'], cwd: extDir);
    _say('✓ vscode/$_vsix');
    return 0;
  }
}

class _Ext extends _Task {
  @override
  String get name => 'ext';
  @override
  String get description =>
      'Compile, package and install the extension (into --profile).';

  @override
  Future<int> run() => runWith(profile: profile, code: code);

  /// The same, for `install` — which resolved the options once already.
  Future<int> runWith({required String? profile, required String code}) async {
    await _Package().run();
    return _ExtInstall.install(profile: profile, code: code);
  }
}

class _ExtInstall extends _Task {
  @override
  String get name => 'ext-install';
  @override
  String get description =>
      'Install the built VSIX into VSCode (into --profile).';

  @override
  Future<int> run() => install(profile: profile, code: code);

  static Future<int> install({
    required String? profile,
    required String code,
  }) async {
    if (profile != null) {
      final known = await _Profiles.names();
      if (!known.contains(profile)) {
        throw _Failed(
          'No VSCode profile named "$profile". Known:\n'
          '${known.map((n) => '  $n').join('\n')}',
        );
      }
    }
    final vsix = File(p.join(extDir, _vsix));
    if (!vsix.existsSync()) {
      throw _Failed("missing vscode/$_vsix — run 'package'");
    }
    if (profile == null) {
      _say(
        "⚠ --profile is unset — installing into VSCode's Default profile. "
        "'profiles' shows the others.",
      );
    }
    final profileArgs = profile == null
        ? const <String>[]
        : ['--profile', profile];
    // `--force` because the version rarely changes between local builds, and
    // without it VSCode declines to reinstall the same version.
    await _run(code, [
      ...profileArgs,
      '--install-extension',
      _vsix,
      '--force',
    ], cwd: extDir);
    final where = profile == null
        ? 'the Default profile'
        : 'profile "$profile"';
    _say("✓ installed into $where — now run 'Developer: Reload Window'");
    return 0;
  }
}

class _Profiles extends _Task {
  _Profiles() {
    argParser.addFlag(
      'names',
      negatable: false,
      help: 'Just the names, one per line (for scripting).',
    );
  }

  @override
  String get name => 'profiles';
  @override
  String get description =>
      'List the VSCode profiles on this machine and the frx build in each.';

  /// Where VSCode keeps the user's profiles on this platform.
  static String? get userDir {
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
  static Future<List<String>> names() async {
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
      final data =
          jsonDecode(storage.readAsStringSync()) as Map<String, Object?>;
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

  @override
  Future<int> run() async {
    final all = await names();
    if (argResults!.flag('names')) {
      all.forEach(_say);
      return 0;
    }
    if (await _ask(code, ['--version']) == null) {
      throw _Failed(
        'the `$code` command is not on PATH.\n'
        '  In VSCode: Command Palette → '
        "'Shell Command: Install code command in PATH'.",
      );
    }
    _say('${'PROFILE'.padRight(16)}  frx');
    _say('${'-' * 16}  ${'-' * 16}');
    for (final name in all) {
      final listed = await _ask(code, [
        if (name != 'Default') ...['--profile', name],
        '--list-extensions',
        '--show-versions',
      ]);
      final installed = (listed ?? '')
          .split('\n')
          .where((l) => l.toLowerCase().contains('frx'))
          .join(', ');
      _say('${name.padRight(16)}  ${installed.isEmpty ? '—' : installed}');
    }
    return 0;
  }
}

// --- release -----------------------------------------------------------------

class _Dist extends _Task {
  @override
  String get name => 'dist';
  @override
  String get description =>
      'Compile a native frx binary into dist/ — the same binary the release '
      'attaches, for this machine only.';

  @override
  Future<int> run() async {
    // `dart compile exe` builds for the host and does not cross-compile. Worth
    // having locally to check what an install actually gets: `dart install` and
    // `dart run` both take different paths through the SDK than an AOT
    // snapshot does.
    await _run('dart', ['pub', 'get']);
    Directory(p.join(toolsRoot, 'dist')).createSync(recursive: true);
    final out = p.join('dist', Platform.isWindows ? 'frx.exe' : 'frx');
    await _run('dart', ['compile', 'exe', 'bin/frx.dart', '-o', out]);
    await _run(p.join(toolsRoot, out), ['--version']);
    _say(_sizeOf(File(p.join(toolsRoot, out))));
    return 0;
  }
}

class _Version extends _Task {
  @override
  String get name => 'version';
  @override
  String get description =>
      'Bump the three version declarations at once: pubspec.yaml, '
      'version.dart and the extension manifest.';
  @override
  String get invocation => 'xtask version <x.y.z>';

  /// One version, declared in three files, and the release refuses a tag they
  /// disagree with — so bumping them by hand is three chances to publish a
  /// binary that reports a version it is not. `version_test.dart` is what
  /// catches that; this is what avoids it.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('usage: xtask version 0.3.0');
    }
    final v = rest.single;
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+([-+].+)?$').hasMatch(v)) {
      usageException('"$v" is not a semantic version');
    }
    _rewrite(
      p.join(toolsRoot, 'pubspec.yaml'),
      RegExp(r'^version: .*$', multiLine: true),
      'version: $v',
    );
    _rewrite(
      p.join(toolsRoot, 'lib', 'src', 'version.dart'),
      RegExp("frxVersion = '[^']*'"),
      "frxVersion = '$v'",
    );
    await _run('npm', [
      'version',
      v,
      '--no-git-tag-version',
      '--allow-same-version',
    ], cwd: extDir);
    final verified = await _ask('dart', ['test', 'test/version_test.dart']);
    if (verified == null) {
      throw const _Failed(
        'the three files disagree — see `dart test test/version_test.dart`',
      );
    }
    _say('✓ pubspec, version.dart and package.json all say $v');
    _say('');
    _say("  git commit -am 'v$v' && git tag v$v && git push origin main v$v");
    return 0;
  }

  static void _rewrite(String path, RegExp pattern, String replacement) {
    final file = File(path);
    final before = file.readAsStringSync();
    if (!pattern.hasMatch(before)) {
      throw _Failed('$path: nothing matched ${pattern.pattern}');
    }
    file.writeAsStringSync(before.replaceFirst(pattern, replacement));
  }
}

// --- checks ------------------------------------------------------------------

class _Check extends _Task {
  @override
  String get name => 'check';
  @override
  String get description => 'Everything CI runs, locally.';

  @override
  Future<int> run() async {
    await _run('dart', [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'lib',
      'test',
      'bin',
      'tool',
    ]);
    await _run('dart', ['analyze']);
    await _run('dart', ['test']);
    await _run('npm', ['install', '--silent'], cwd: extDir);
    await _run('npm', ['run', 'typecheck'], cwd: extDir);
    await _run('npm', ['run', 'validate'], cwd: extDir);
    await _run('npm', ['test'], cwd: extDir);
    return 0;
  }
}

class _Test extends _Task {
  @override
  String get name => 'test';
  @override
  String get description => 'dart test + the extension suite.';

  @override
  Future<int> run() async {
    await _run('dart', ['test']);
    await _run('npm', ['test'], cwd: extDir);
    return 0;
  }
}

class _Docs extends _Task {
  @override
  String get name => 'docs';
  @override
  String get description => 'Regenerate docs/flows.';

  @override
  Future<int> run() =>
      _run('dart', ['run', 'bin/frx.dart', 'flow', '--md', '--root', '..']);
}

class _Skills extends _Task {
  @override
  String get name => 'skills';
  @override
  String get description =>
      'Regenerate .claude/skills from the commands themselves.';

  /// The agent skills in ../.claude/skills — one per command plus the router,
  /// derived from the command objects so the flag lists cannot drift from the
  /// CLI. `check` catches a stale tree: skills_freshness_test.dart is part of
  /// `dart test`.
  @override
  Future<int> run() =>
      _run('dart', ['run', 'bin/frx.dart', 'update-skills', '--root', '..']);
}

class _Contract extends _Task {
  @override
  String get name => 'contract';
  @override
  String get description =>
      "Regenerate the extension's constants from the CLI.";

  /// The extension's generated constants — the `--kind` sets, the marker path
  /// and the doctor remedy ids, written from the CLI's own ArgParsers so the
  /// editor reads the contract instead of restating it. `check` catches a
  /// stale copy: contract_freshness_test.dart is part of `dart test`.
  @override
  Future<int> run() => _run('dart', ['run', 'bin/gen_contract.dart']);
}

class _Template extends _Task {
  @override
  String get name => 'template';
  @override
  String get description => "Repack the template 'frx create' unpacks.";

  /// The archive `frx create` unpacks — a derived artifact like docs/flows, and
  /// it goes stale the moment the product moves. `check` catches that:
  /// template_freshness_test.dart is part of `dart test`.
  ///
  /// None of the three flags is adjustable. `-f base64` keeps the payload a
  /// single string literal; `-f bytes` writes the same archive as a const list
  /// 4.7× the size. `-n frx` names the constant `create_command.dart` imports.
  /// The manifest is not passed because `pack` reads ../mold.yaml, beside the
  /// project it packs.
  @override
  Future<int> run() async {
    const out = 'lib/src/template/template.g.dart';
    await _run('dart', [
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
    _say(
      '✓ ${_sizeOf(File(p.join(toolsRoot, out)))} embedded — run '
      "'dart test test/template_freshness_test.dart' to confirm",
    );
    return 0;
  }
}

// --- teardown ----------------------------------------------------------------

class _Uninstall extends _Task {
  @override
  String get name => 'uninstall';
  @override
  String get description => 'Remove both (the extension from --profile).';

  @override
  Future<int> run() async {
    await _run(code, [
      ...profileArgs,
      '--uninstall-extension',
      'pro100dev.frx',
    ], allowFailure: true);
    await _run('dart', ['uninstall', 'tools'], allowFailure: true);
    return 0;
  }
}

class _Clean extends _Task {
  @override
  String get name => 'clean';
  @override
  String get description => 'Drop build output.';

  @override
  Future<int> run() async {
    for (final path in [
      p.join(extDir, 'out'),
      p.join(toolsRoot, 'dist'),
    ]) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
    for (final f in Directory(extDir).listSync().whereType<File>()) {
      if (f.path.endsWith('.vsix')) {
        f.deleteSync();
      }
    }
    return 0;
  }
}
