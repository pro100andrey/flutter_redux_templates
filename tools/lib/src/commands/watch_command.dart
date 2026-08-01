import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../engine/build_step.dart';
import '../workspace/frx_workspace.dart';
import 'options.dart';
import '../util/console.dart';

/// Runs `build_runner watch` from the right directory with the right flags, so
/// you don't have to `cd` to the workspace root or remember the incantation.
///
/// Defaults to the whole pub workspace; `--package <name>` narrows it to one
/// package (a smaller builder graph). `--print` shows the command without
/// running it.
class WatchCommand extends Command<int> {
  WatchCommand() {
    argParser
      ..addOption(
        'package',
        abbr: 'p',
        help:
            'Watch a single package (e.g. business) instead of the whole '
            'workspace.',
      )
      ..addFlag(
        'delete-conflicting-outputs',
        defaultsTo: true,
        help: 'Pass --delete-conflicting-outputs to build_runner.',
      )
      ..addFlag(
        'print',
        negatable: false,
        help: 'Print the command that would run, then exit (don\'t watch).',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'watch';

  @override
  String get description =>
      'Run build_runner watch (whole workspace, or one --package).';

  @override
  List<String> get aliases => ['wa'];

  @override
  Future<int> run() async {
    final results = argResults!;
    final workspace = FrxWorkspace.locate(startDir: results['root'] as String?);
    final package = results['package'] as String?;

    final String cwd;
    if (package == null) {
      cwd = workspace.root.path;
    } else {
      cwd = p.join(workspace.root.path, package);
      if (!File(p.join(cwd, 'pubspec.yaml')).existsSync()) {
        throw StateError(
          'No package "$package" at ${p.relative(cwd)} '
          '(looked for its pubspec.yaml).',
        );
      }
    }

    final args = [
      'run',
      'build_runner',
      'watch',
      // --workspace builds every member; omit it for a single package.
      if (package == null) '--workspace',
      if (results['delete-conflicting-outputs'] as bool)
        '--delete-conflicting-outputs',
    ];

    final rel = p.relative(cwd);
    final cmd = 'dart ${args.join(' ')}';
    if (results['print'] as bool) {
      console.out.writeln('cd $rel && $cmd');
      return 0;
    }

    console.out
      ..writeln(
        'frx watch — ${package == null ? 'workspace' : 'package "$package"'} '
        '(${rel == '.' ? 'repo root' : rel})',
      )
      ..writeln('  $cmd')
      ..writeln('  Ctrl-C to stop.')
      ..writeln();
    return streamProcess('dart', args, cwd);
  }
}
