import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/audit/checks.dart';
import 'package:tools/src/audit/finding.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// A hook whose script is not where the settings file says fails *open*: the
/// tool call it exists to refuse simply succeeds, and nothing anywhere says so.
/// That is the one failure mode a guard must not have, and the only way to see
/// it is to look.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('frx_hooks_'));
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String body) {
    File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(body);
  }

  void settings(String command) => put('.claude/settings.json', '''
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "$command" }]
      }
    ]
  }
}
''');

  List<Finding> run() {
    final found = <Finding>[];
    checkAgentHooks(FrxWorkspace(root), found);
    return found;
  }

  test('a hook whose script is there says nothing', () {
    settings(r'$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh');
    put('.claude/hooks/guard.sh', '#!/bin/bash\n');
    expect(run(), isEmpty);
  });

  test('a hook whose script is missing is reported', () {
    settings(r'$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh');
    final found = run();
    expect(found, hasLength(1));
    expect(found.single.message, contains('.claude/hooks/guard.sh'));
    expect(found.single.message, contains('fails open'));
  });

  test('the subdirectory mistake is caught', () {
    // The one that happened. A template unpacked at `apps/tm_console` gets its
    // command hand-patched to carry that prefix — but $CLAUDE_PROJECT_DIR is
    // the directory holding `.claude/`, which is already the project, so the
    // prefix is counted twice and the hook resolves to nothing.
    settings(r'$CLAUDE_PROJECT_DIR/apps/tm_console/.claude/hooks/guard.sh');
    put('.claude/hooks/guard.sh', '#!/bin/bash\n');
    final found = run();
    expect(found, hasLength(1));
    expect(found.single.message, contains('apps/tm_console/.claude/hooks'));
  });

  test('a path relative to the project resolves too', () {
    settings('.claude/hooks/guard.sh');
    put('.claude/hooks/guard.sh', '#!/bin/bash\n');
    expect(run(), isEmpty);
  });

  test('no settings file, nothing to say', () {
    // Agent hooks are opt-in. A project that removed them is not broken.
    expect(run(), isEmpty);
  });

  test('settings without a hooks block is not a finding', () {
    put('.claude/settings.json', '{ "model": "opus" }');
    expect(run(), isEmpty);
  });

  test('unreadable settings are reported rather than skipped', () {
    // Invalid JSON means *every* hook it declares is off, which is a bigger
    // silence than one missing script.
    put('.claude/settings.json', '{ "hooks": ');
    final found = run();
    expect(found, hasLength(1));
    expect(found.single.message, contains('not valid JSON'));
  });

  test('a command this check cannot be sure about is left alone', () {
    // A shell one-liner, an absolute path outside the project, and a bare name
    // resolved on PATH are all somebody's deliberate choice. Guessing which
    // token is the script would warn about hooks that work — worse than
    // silence.
    for (final command in [
      r'$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh | tee /tmp/log',
      r'bash -c "exit 0"',
      '/usr/local/bin/some-guard',
      'prettier',
    ]) {
      settings(command.replaceAll(r'"', r'\"'));
      expect(run(), isEmpty, reason: command);
    }
  });

  test('every declared hook is checked, not just the first', () {
    put('.claude/settings.json', r'''
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/a.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/b.sh" }] }
    ]
  }
}
''');
    put('.claude/hooks/a.sh', '#!/bin/bash\n');
    final found = run();
    expect(found, hasLength(1));
    expect(found.single.message, contains('PostToolUse'));
    expect(found.single.message, contains('b.sh'));
  });
}
