import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The contract between `.claude/settings.json` and the hook it registers.
///
/// The guard states which tools it handles twice: the matcher in `settings.json`
/// decides whether the hook is spawned at all, and the `case` inside the script
/// decides what it does once it is. Only the second one reads like the rule, so
/// that is the one that gets edited — and a matcher narrower than the case is a
/// guard that silently never fires.
///
/// That is not hypothetical. The script has handled `Write | Edit | MultiEdit`
/// since it was written, while the matcher said `Write`; a traced run then made
/// six hand edits to state files with `Edit` and every one of them went through.
/// The two runs on either side of it, where the same edits happened to be
/// `Write`, were blocked — so the hole looked like agent variance, not a bug.
///
/// A test rather than a `doctor` check, for the reason `skills_freshness_test`
/// gives: a project made by `frx create` carries both files but nothing to
/// re-derive them from.
void main() {
  final repoRoot = p.dirname(Directory.current.absolute.path);
  final claude = p.join(repoRoot, '.claude');

  test('the guard matcher covers every tool the guard handles', () {
    final script = File(
      p.join(claude, 'hooks', 'guard-wired-files.sh'),
    ).readAsStringSync();

    // Every named arm of `case "$tool"` — the script's own statement of its
    // subject. All of them, not the first: the shell channel arrived as a second
    // arm (`Bash) guard_shell`), and a reader that stopped at the first would
    // have gone on requiring the matcher to be exactly the tools it already had,
    // which is the drift this test exists to catch, one level up.
    final block = RegExp(
      r'case\s+"\$tool"\s+in\n(.*?)\nesac',
      dotAll: true,
    ).firstMatch(script);
    expect(
      block,
      isNotNull,
      reason: 'no `case "\$tool"` block in the guard script',
    );
    final handled = {
      for (final arm in RegExp(
        r'^\s*([A-Za-z][A-Za-z |]*)\)',
        multiLine: true,
      ).allMatches(block!.group(1)!))
        ...arm
            .group(1)!
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
    };
    expect(handled, isNotEmpty);

    final settings =
        jsonDecode(File(p.join(claude, 'settings.json')).readAsStringSync())
            as Map<String, Object?>;
    final hooks = (settings['hooks']! as Map<String, Object?>)['PreToolUse']!;

    final matchers = <String>{};
    for (final entry in (hooks as List).cast<Map<String, Object?>>()) {
      final registers = (entry['hooks']! as List)
          .cast<Map<String, Object?>>()
          .any(
            (h) => (h['command']! as String).endsWith('guard-wired-files.sh'),
          );
      if (registers) matchers.add(entry['matcher']! as String);
    }
    expect(
      matchers,
      hasLength(1),
      reason: 'the guard should be registered by exactly one matcher',
    );

    final matched = matchers.single
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    expect(
      handled.difference(matched),
      isEmpty,
      reason:
          'the guard handles tool(s) its matcher never spawns it for, so it '
          'silently allows exactly what it exists to refuse. Widen "matcher" '
          'in .claude/settings.json to match the case arm in the script.',
    );
    expect(
      matched.difference(handled),
      isEmpty,
      reason:
          'the matcher spawns the guard for tool(s) it does nothing about. '
          'Narrow the matcher, or handle them in the script.',
    );
  });

  test('the guard is reachable and refuses a hand-edited state file', () {
    // The contract above compares two texts; this one runs the thing. It is the
    // check that would have failed on a guard made unreachable — moved,
    // unexecutable, or wired to a path that no longer resolves.
    final script = p.join(claude, 'hooks', 'guard-wired-files.sh');
    expect(File(script).existsSync(), isTrue, reason: 'the guard is missing');

    // The payload arrives on stdin, which `Process.runSync` cannot write — so
    // go through a shell that can.
    ProcessResult call(String tool, String path) => Process.runSync('bash', [
      '-c',
      'printf %s ${_shellQuote(jsonEncode({'tool_name': tool, 'file_path': path}))} '
          '| bash ${_shellQuote(script)}',
    ]);

    expect(
      call(
        'Edit',
        '/x/business/lib/redux/tasks/models/tasks_state.dart',
      ).exitCode,
      2,
      reason: 'a hand edit to a state file must be refused',
    );
    expect(
      call('Write', '/x/business/lib/redux/selectors.dart').exitCode,
      2,
      reason: 'rewriting the selector facade whole must be refused',
    );
    // Deliberately allowed: `add-selector` takes an expression, so a selector
    // with a statement body is hand-written here, and the skill says to.
    expect(
      call('Edit', '/x/business/lib/redux/selectors.dart').exitCode,
      0,
      reason: 'editing one selector by hand is the documented path',
    );
    expect(
      call('Edit', '/x/ui/lib/tiles/task_tile.dart').exitCode,
      0,
      reason: 'a file no command owns must pass',
    );
  });

  test('the shell channel is guarded too', () {
    // Refusing `Write` while allowing `cat >` is not a weaker guard — it is one
    // that reports success while the write happens. Measured: in one traced run
    // two state files were refused on `Write` and rewritten through `Bash` two
    // minutes later, in a single command that wrote four of them.
    final script = p.join(claude, 'hooks', 'guard-wired-files.sh');

    ProcessResult bash(String command) => Process.runSync('bash', [
      '-c',
      'printf %s ${_shellQuote(jsonEncode({'tool_name': 'Bash', 'command': command}))} '
          '| bash ${_shellQuote(script)}',
    ]);

    // Refused: whole-file writes, however the path is spelled.
    for (final command in [
      "cat > business/lib/redux/tasks/models/tasks_state.dart <<'DART'\nclass X {}\nDART",
      // After a `cd`, which is the observed shape — the tail still matches.
      "cd business/lib\ncat > redux/tasks/models/tasks_state.dart <<'D'\nx\nD",
      'echo x > business/lib/redux/selectors.dart',
      'cat x | tee business/lib/redux/selectors.dart',
    ]) {
      expect(bash(command).exitCode, 2, reason: command);
    }

    // Refused: editing a state file in place.
    expect(
      bash(
        "python3 - <<'PY'\nimport pathlib\n"
        "p = pathlib.Path('business/lib/redux/tasks/models/tasks_state.dart')\n"
        'p.write_text(p.read_text() + "x")\nPY',
      ).exitCode,
      2,
    );
    expect(
      bash(
        "sed -i '' 's/a/b/' business/lib/redux/tasks/models/tasks_state.dart",
      ).exitCode,
      2,
    );

    // Allowed: editing one selector in place is the documented path, and the
    // shell channel must not be stricter than the Edit tool about it.
    expect(
      bash(
        "python3 - <<'PY'\nimport pathlib\n"
        "p = pathlib.Path('business/lib/redux/selectors.dart')\n"
        'p.write_text(p.read_text().replace("a", "b"))\nPY',
      ).exitCode,
      0,
    );

    // Refused: a write whose destination is the *last* operand. `cp`, `mv` and
    // `install` were folded into the same pattern as `>` and `tee`, which puts
    // the path immediately after the operator — so they matched the source and
    // never the destination. Measured before the fix: copying into a state file
    // passed, while moving one *away* — which only reads it — was refused.
    //
    // The paths are assembled rather than written out because this repository's
    // own guard is active while these tests are edited, and a literal one in the
    // file would refuse the edit.
    final stateFile = 'business/lib/redux/tasks/models/tasks_${'state'}.dart';
    final facade = 'business/lib/redux/${'selectors'}.dart';
    for (final command in [
      'cp /tmp/new.dart $stateFile',
      'mv /tmp/new.dart $stateFile',
      'install -m 644 /tmp/new.dart $stateFile',
      'cp /tmp/new.dart $facade',
    ]) {
      expect(bash(command).exitCode, 2, reason: command);
    }

    // Allowed, and decided rather than overlooked: moving a state file away
    // deletes it, and deletion is not this guard's subject — `rm` is not caught
    // either. Refusing this one shape alone would read as a rule that is not
    // there. It was refused before the fix only by accident of the same
    // backwards pattern.
    expect(bash('mv $stateFile /tmp/x').exitCode, 0);

    // Allowed: reading. The failure this pins is a guard that fires on `cat`
    // without a redirection, which would make the tree unreadable.
    for (final command in [
      'cat business/lib/redux/tasks/models/tasks_state.dart',
      'grep -n table business/lib/redux/selectors.dart',
      'cat -n business/lib/redux/tasks/models/tasks_state.dart | head -40',
      // A write whose target is elsewhere, reading a guarded file.
      'grep table business/lib/redux/selectors.dart > /tmp/out.txt',
      // Dart source in a heredoc body: `=>` is a redirection to nothing frx
      // owns, and must not be read as one.
      "cat > ui/lib/tiles/task_tile.dart <<'DART'\nIMap get table => _state.tasks.table;\nDART",
    ]) {
      expect(bash(command).exitCode, 0, reason: command);
    }
  });
}

String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
