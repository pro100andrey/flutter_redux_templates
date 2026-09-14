import 'dart:convert';

import 'package:args/command_runner.dart';

import '../audit/checks.dart';
import '../audit/finding.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'doctor_repair.dart';
import 'options.dart';

/// Audits the project for common drift: substates not wired into `AppState`,
/// missing freezed/auto_route parts (build_runner not run), and route ↔
/// connector mismatches — plus **placement**: code that is fully wired,
/// compiles, and sits in the wrong place. Read-only by default; `--fix` repairs
/// the findings that carry a [Fix]. Exits 1 when errors remain, which no
/// placement finding ever is.
///
/// What to check lives in [auditChecks]; this command decides how to say it,
/// and `doctor_repair.dart` how to repair it.
class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser
      ..addFlag(
        'fix',
        negatable: false,
        help:
            'Repair auto-fixable findings: run build_runner for missing '
            'parts, remove orphan substate folders, regenerate docs/flows and '
            'rewrite .claude/skills. It applies without a preview — '
            '`frx update-skills --dry-run --diff` is the one that shows the '
            'skill changes first.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit findings as JSON '
            '({findings:[{severity,message,file,fix,rule}]}) instead of the '
            'report. Read-only (ignores --fix).',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Audit the project for wiring drift, ungenerated code and misplaced '
      'declarations.';

  @override
  List<String> get aliases => ['dr'];

  @override
  Future<int> run() async {
    final root = argResults?['root'] as String?;
    final fix = argResults?['fix'] as bool? ?? false;
    final json = argResults?['json'] as bool? ?? false;
    final repo = FrxWorkspace.locate(startDir: root);

    // Process-state observations are for a human reading the report; the
    // editor re-audits on file events and would keep a stale one on screen.
    var findings = audit(repo, processState: !json);

    // Machine-readable mode is read-only (the VSCode Problems integration reads
    // it); emit and exit before any report or repair.
    if (json) {
      console.out.writeln(
        jsonEncode({
          'findings': [for (final f in findings) f.toJson()],
        }),
      );
      return _exitCode(findings);
    }

    _report(repo, findings);

    if (findings.isEmpty || !fix) {
      return _exitCode(findings);
    }

    final fixes = findings.map((f) => f.fix).nonNulls.toList();
    if (fixes.isEmpty) {
      console.out
        ..writeln()
        ..writeln('Nothing here is auto-fixable — resolve manually.');
      return _exitCode(findings);
    }

    console.out
      ..writeln()
      ..writeln('--fix: applying ${fixes.length} remediation(s)…');

    await repair(repo, fixes);

    console.out
      ..writeln()
      ..writeln('Re-checking…')
      ..writeln();
    findings = audit(repo, processState: true);
    _report(repo, findings);
    return _exitCode(findings);
  }

  void _report(FrxWorkspace repo, List<Finding> findings) {
    console.out
      ..writeln('frx doctor  (${repo.root.path})')
      ..writeln();
    if (findings.isEmpty) {
      console.out.writeln('✓ No issues found.');
      return;
    }
    final errors = findings.where((f) => f.severity == Severity.error).length;
    for (final f in findings) {
      console.out.writeln(
        '  ${f.severity == Severity.error ? '✗' : '⚠'} ${f.message}',
      );
    }
    console.out
      ..writeln()
      ..writeln('${findings.length} issue(s) — $errors error(s).');
  }

  int _exitCode(List<Finding> findings) =>
      findings.any((f) => f.severity == Severity.error) ? 1 : 0;
}
