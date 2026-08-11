import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../upgrade/upgrade.dart';
import '../util/console.dart';
import '../version.dart';

/// Replaces the installed `frx` with the newest release.
///
/// **The only command that opens a socket.** Everything else frx does is local,
/// and that is a property people rely on without being told — a build container
/// with no route out, a locked-down proxy, a plane. So there is no background
/// check and no "a new version is available" appended to unrelated output: the
/// network is reached when somebody asks for it by name, and never otherwise.
///
/// `--check` asks the question without answering it destructively, and says so
/// in the exit code, so a shell can act on it:
///
/// ```bash
/// frx upgrade --check || frx upgrade
/// ```
class UpgradeCommand extends Command<int> {
  UpgradeCommand({this.upgrader}) {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Report whether a newer release exists and stop. Exits 1 when one '
            'does, so it can gate a command.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the outcome as JSON instead of a sentence.',
      )
      ..addOption(
        'version',
        help: 'Install this release instead of the newest one.',
      );
  }

  /// Injected by tests, which point it at a release served over localhost.
  final Upgrader? upgrader;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Replace this frx binary with the newest release.';

  @override
  List<String> get aliases => ['up'];

  @override
  Future<int> run() async {
    final check = argResults!.flag('check');
    final json = argResults!.flag('json');
    final pinned = argResults?['version'] as String?;

    final upgrader =
        this.upgrader ??
        Upgrader(
          currentVersion: frxVersion,
          executable: File(Platform.resolvedExecutable),
        );

    final UpgradeResult result;
    try {
      result = await upgrader.run(check: check, pinned: pinned);
    } on UpgradeException catch (e) {
      if (json) {
        console.out.writeln(
          jsonEncode({'status': 'failed', 'message': e.message}),
        );
      } else {
        console.err.writeln('frx: ${e.message}');
      }
      return 1;
    }

    if (json) {
      console.out.writeln(jsonEncode(result.toJson()));
    } else {
      _report(result);
    }

    // `--check` reports through the exit code as well as the text, so it can
    // gate a command without being parsed: 0 when there is nothing to do, 1
    // when there is. Without `--check` an upgrade is the work, not the news,
    // and a successful one exits 0.
    if (check && result.status == UpgradeStatus.available) return 1;
    return result.status == UpgradeStatus.refused ? 1 : 0;
  }

  void _report(UpgradeResult result) {
    switch (result.status) {
      case UpgradeStatus.current:
        console.out.writeln('frx ${result.from} is the newest release.');
      case UpgradeStatus.available:
        // Only `--check` returns this — an unchecked run installs instead of
        // announcing — so the hint needs no condition. The `check` parameter
        // stays out of it rather than reading as a branch that can go both ways.
        console.out
          ..writeln('frx ${result.to} is available (this is ${result.from}).')
          ..writeln('Run `frx upgrade` to install it.');
      case UpgradeStatus.upgraded:
        console.out.writeln('frx ${result.from} → ${result.to}');
      case UpgradeStatus.refused:
        console.err.writeln('frx: ${result.message}');
    }
  }
}
