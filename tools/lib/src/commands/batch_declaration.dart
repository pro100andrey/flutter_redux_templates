/// The declaration `frx batch` takes, validated into the intents it lists.
///
/// **The input is a declaration of intents** — the commands you would have
/// typed, as data. A file is reviewable, diffable and committable; standard
/// input suits an agent generating one.
///
/// **It is deliberately not the changeset format.** A changeset describes file
/// operations; a batch declares intents. Feeding a changeset back in would mean
/// "apply exactly these file edits", bypassing the readers that derive them —
/// and deriving the edits rather than being told them is where frx's value
/// lives. The appealing symmetry of "plan out, plan in" was examined and
/// withdrawn.
library;

import 'dart:convert';

import 'frx_command.dart';

/// One declared intent, as the argv it becomes.
class Intent {
  Intent(this.argv);

  final List<String> argv;

  /// How the intent reads in a report — the command line it stands for.
  String get description => argv.join(' ');
}

/// Flags that decide *when or whether* the batch writes. They belong to the
/// batch, so an intent carrying one is refused rather than quietly obeyed —
/// a per-intent `--dry-run` would mean the batch was partly a rehearsal.
const _batchOwned = {'dry-run', 'apply', 'json', 'build-runner', 'format'};

/// The declaration, validated. Throws [FormatException] with what to fix.
///
/// **Scope is the additive commands only** — every creation command,
/// including the field, selector and navigation commands, which are the
/// ordering case and cannot be excluded without removing the point. Rename
/// and removal stay out: a declaration file that deletes artifacts is a
/// different class of risk, nothing asked for it, and the asymmetry runs one
/// way — widening later is additive, narrowing after release is a break.
List<Intent> parseBatchDeclaration(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw FormatException('the declaration is not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'the declaration must be an object with an "intents" list.',
    );
  }
  final list = decoded['intents'];
  if (list is! List) {
    throw const FormatException('"intents" must be a list.');
  }
  if (list.isEmpty) {
    throw const FormatException('"intents" is empty — nothing to wire.');
  }

  final intents = <Intent>[];
  for (var i = 0; i < list.length; i++) {
    final where = 'intent ${i + 1}';
    final entry = list[i];
    if (entry is! Map<String, Object?>) {
      throw FormatException('$where must be an object.');
    }
    final command = entry['command'];
    if (command is! String || command.isEmpty) {
      throw FormatException('$where has no "command".');
    }
    _refuse(where, command);

    final args = <String>[];
    switch (entry['args']) {
      case null:
        break;
      case final List<Object?> raw:
        for (final a in raw) {
          if (a is! String) {
            throw FormatException(
              '$where: every "args" entry must be a string.',
            );
          }
          args.add(a);
        }
      default:
        throw FormatException('$where: "args" must be a list of strings.');
    }

    final options = <String>[];
    switch (entry['options']) {
      case null:
        break;
      case final Map<String, Object?> raw:
        for (final option in raw.entries) {
          options.addAll(_flag(where, option.key, option.value));
        }
      default:
        throw FormatException('$where: "options" must be an object.');
    }

    final argv = [command, ...args, ...options];
    // Checked over the whole argv, not over `options` alone: a flag spelled
    // into `args` reaches the command just the same, and `--dry-run` smuggled
    // in that way made an intent silently a rehearsal — the batch reported
    // success and wrote nothing.
    _refuseBatchFlags(where, argv);
    intents.add(Intent(argv));
  }
  return intents;
}

/// Refuses a command that is not a creation command, saying which it is.
void _refuse(String where, String command) {
  const destructive = {
    'rename': 'renaming moves files and rewrites references',
    'remove': 'removal deletes artifacts',
  };
  if (destructive[command] case final why?) {
    throw FormatException(
      '$where: "$command" is not allowed in a batch — $why, and a '
      'declaration '
      'file that does it is a different class of risk. Run it on its own.',
    );
  }
  if (command == 'new') {
    throw FormatException(
      '$where: "new" is the interactive wizard; it prints the flag-driven '
      'command it would run — declare that instead.',
    );
  }
  if (createdKindOf(command) == null) {
    throw FormatException(
      '$where: "$command" is not a creation command. A batch wires '
      'artifacts; '
      'reading and auditing commands are not part of one.',
    );
  }
}

/// Refuses an intent that carries a flag deciding *when or whether* the batch
/// writes, however it was spelled.
void _refuseBatchFlags(String where, List<String> argv) {
  for (final arg in argv) {
    if (!arg.startsWith('--')) {
      continue;
    }
    // `--flag`, `--no-flag` and `--flag=value` all name the same flag.
    final named = arg.substring(2).split('=').first;
    final bare = named.startsWith('no-') ? named.substring(3) : named;
    if (_batchOwned.contains(bare)) {
      throw FormatException(
        '$where: "$bare" belongs to the batch, not to an intent — pass it to '
        '`frx batch` instead.',
      );
    }
  }
}

/// One `options` entry as argv. A bool is a flag, a list is repeated.
List<String> _flag(String where, String key, Object? value) => switch (value) {
  true => ['--$key'],
  false => ['--no-$key'],
  final String s => ['--$key', s],
  final num n => ['--$key', '$n'],
  final List<Object?> many => [
    for (final v in many) ...['--$key', '$v'],
  ],
  _ => throw FormatException(
    '$where: "$key" must be a string, a number, a boolean or a list.',
  ),
};
