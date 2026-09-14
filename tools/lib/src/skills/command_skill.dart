import 'package:args/command_runner.dart';

import 'situation.dart';

/// Renders one command's `SKILL.md`: the frontmatter that triggers it, then
/// the body an agent reads once it has fired.
///
/// The mechanical parts — the invocation, the alias, the flag list — are read
/// off [cmd] so they cannot drift from the CLI; the authored parts come from
/// [s].
String renderCommandSkill(Command<int> cmd, Situation s) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('name: frx-${cmd.name}')
    ..writeln('description: >-')
    ..writeln(_fold(_description(cmd, s), '  '));

  if (s.paths.isNotEmpty) {
    b.writeln('paths:');
    for (final path in s.paths) {
      b.writeln('  - "$path"');
    }
  }

  b
    ..writeln('---')
    ..writeln()
    ..writeln('# `frx ${cmd.name}`')
    ..writeln()
    ..writeln(cmd.description)
    ..writeln()
    ..writeln('```')
    ..writeln(cmd.invocation)
    ..writeln('```')
    ..writeln();

  // Context first: what the thing is comes before what to watch out for.
  if (s.context case final context?) {
    b
      ..writeln(context.trim())
      ..writeln();
  }

  if (s.traps.isNotEmpty) {
    b
      ..writeln('## Before you run it')
      ..writeln();
    for (final t in s.traps) {
      b.writeln('- ${_fold(t, '  ').trimLeft()}');
    }
    b.writeln();
  }

  b
    ..writeln('## Flags')
    ..writeln()
    ..writeln('```')
    ..writeln(cmd.argParser.usage.trimRight())
    ..writeln('```')
    ..writeln()
    ..writeln(_shared)
    ..writeln()
    ..writeln(_gates);
  return b.toString();
}

/// The description is the trigger, so it carries the situation and the
/// command name and stops there. Splicing the CLI's own one-liner in as a
/// clause reads as a conjugation bug ("which add a field…") because those
/// are imperative, and the body repeats it verbatim two lines down.
/// The prohibition stays. Anthropic's guide recommends negative triggers
/// in a description, and the 650-trial comparison has imperative-plus-
/// prohibition activating 98.6% against 62.6% for the imperative alone.
/// The opposite rule — prompt the positive — governs the body, not this.
String _description(Command<int> cmd, Situation s) {
  final alias = cmd.aliases.isEmpty ? '' : ' (alias `${cmd.aliases.first}`)';
  final verb = s.wires ? 'Wired by' : 'Answered by';
  final prohibition = s.wires
      ? ' Do NOT hand-write this artifact or edit the files it wires — run the '
            'command.'
      : '';
  return '${s.when} $verb `frx ${cmd.name}`$alias.$prohibition';
}

/// Fold to ~76 columns so the frontmatter stays readable in a diff.
String _fold(String text, String indent) {
  final lines = <String>[];
  final line = StringBuffer(indent);
  var bare = true; // nothing on the line yet but the indent
  for (final w in text.split(_whitespace)) {
    if (w.isEmpty) {
      continue;
    }
    if (!bare && line.length + w.length + 1 > 76) {
      lines.add(line.toString().trimRight());
      line
        ..clear()
        ..write(indent);
      bare = true;
    }
    line
      ..write(w)
      ..write(' ');
    bare = false;
  }
  if (!bare) {
    lines.add(line.toString().trimRight());
  }
  return lines.join('\n');
}

final _whitespace = RegExp(r'\s+');

const _shared = '''
Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.''';

const _gates = '''
## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.''';
