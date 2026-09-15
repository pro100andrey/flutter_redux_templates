import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Hooks declared in `.claude/settings.json` must name a script that is there.
///
/// A hook whose command does not resolve is the worst shape a guard can take:
/// nothing reports it, the tool call it was meant to refuse simply succeeds,
/// and the project looks guarded from the outside. It fails *open* and
/// silently.
///
/// Two ways this happens, and both have happened here:
///
///   * **The template was unpacked into a subdirectory.** The shipped command
///     is `$CLAUDE_PROJECT_DIR/.claude/hooks/…`, which is right only when the
///     project is the checkout. Unpacked at `apps/tm_console`, the variable
///     points at the outer repository and the path misses by two segments — and
///     the settings file there had already been hand-patched to compensate.
///   * **The script moved or was renamed** and the settings file did not
///     follow.
///
/// Warnings, never errors, and silent for a project with no
/// `.claude/settings.json`: agent hooks are an opt-in convenience, and a
/// project that removed them is not broken.
///
/// The variable is resolved against [repo] rather than the environment, because
/// what is being checked is the file the project ships, not the state of
/// whichever shell ran the audit. That is also the only reading under which
/// "unpacked into a subdirectory" is detectable at all.
void checkAgentHooks(FrxWorkspace repo, List<Finding> into) {
  final settings = File(p.join(repo.root.path, '.claude', 'settings.json'));
  if (!settings.existsSync()) {
    return;
  }

  final Object? parsed;
  try {
    parsed = jsonDecode(settings.readAsStringSync());
  } on FormatException catch (e) {
    into.add(
      Finding.warn(
        '${p.relative(settings.path)} is not valid JSON (${e.message}) — every '
        'hook it declares is silently off.',
        file: settings.path,
      ),
    );
    return;
  }

  if (parsed is! Map<String, Object?>) {
    return;
  }

  final hooks = parsed['hooks'];
  if (hooks is! Map<String, Object?>) {
    return;
  }

  for (final event in hooks.entries) {
    final matchers = event.value;
    if (matchers is! List) {
      continue;
    }

    for (final matcher in matchers.whereType<Map<String, Object?>>()) {
      final declared = matcher['hooks'];
      if (declared is! List) {
        continue;
      }

      for (final hook in declared.whereType<Map<String, Object?>>()) {
        if (hook['type'] != 'command') {
          continue;
        }

        final command = hook['command'];
        if (command is! String) {
          continue;
        }

        final script = _hookScript(repo, command);
        if (script == null || File(script).existsSync()) {
          continue;
        }
        into.add(
          Finding.warn(
            '.claude/settings.json declares a ${event.key} hook whose script is '
            'not at ${p.relative(script, from: repo.root.path)} — it fails '
            'open, '
            'so what it refuses is being allowed with nothing said. '
            r'$CLAUDE_PROJECT_DIR is the directory holding .claude/, so a '
            'project unpacked into a subdirectory does not need its own path '
            'in '
            'the command.',
            file: settings.path,
          ),
        );
      }
    }
  }
}

/// The file a hook command runs, resolved against [repo], or null when the
/// command is not a plain path this check can be sure about.
///
/// Deliberately incurious. A command with a pipe, a redirect or its own
/// arguments is somebody's shell one-liner, and guessing which token in it is
/// the script would produce false warnings about hooks that work — worse than
/// the silence this returns instead.
String? _hookScript(FrxWorkspace repo, String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (_shellSyntax.hasMatch(trimmed.replaceAll(_projectDir, ''))) {
    return null;
  }
  if (trimmed.contains(' ')) {
    return null;
  }

  final path = trimmed.startsWith(_projectDir)
      ? trimmed.substring(_projectDir.length).replaceFirst(_leadingSlashes, '')
      : trimmed;
  // An absolute path outside the project, or a bare name resolved on PATH, is
  // not this project's file to have an opinion about. A bare name is the one
  // that bites: joined to the root it becomes a path that is never there, so
  // every `prettier`-style hook would be reported as broken.
  if (p.isAbsolute(path) || !path.contains(p.separator)) {
    return null;
  }
  return p.join(repo.root.path, path);
}

const _projectDir = r'$CLAUDE_PROJECT_DIR';

/// A pipe, a redirect, a subshell, an expansion — anything that makes the
/// command a shell one-liner rather than a path.
final _shellSyntax = RegExp(r'[|&;><$(]');

final _leadingSlashes = RegExp('^/+');
