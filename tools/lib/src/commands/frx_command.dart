import 'package:args/command_runner.dart';

import '../util/casing.dart';

/// Shared parsing for a command's positional arguments.
///
/// A command declares what it takes and asks for it parsed; the arity check,
/// the [Casing.parse] and the `FormatException` → usage-error dance are here.
/// Before this the single-`<name>` case was collapsed and the rest was not:
/// fifteen guards across the package, in three wordings for one condition —
/// `add-selector` said *"Expected two arguments: `<substate> <name>`"*,
/// `add-nav` said *"Give exactly two pages"*, `rename` said *"Expected exactly
/// two arguments"*.
///
/// The names are the ones [Command.invocation] already prints, so the message
/// cannot drift from the usage line: `frx_command_test` asserts the two agree.
mixin NameArg on Command<int> {
  /// The positional arguments this command takes, in order, spelled as
  /// [invocation] spells them — `['substate', 'name:type']`.
  ///
  /// One `<name>` is the common case and the default, so only a command taking
  /// something else says so.
  List<String> get positionals => const ['name'];

  /// The positional arguments, checked for arity.
  ///
  /// The message names them rather than counting them: "expected two arguments"
  /// leaves the reader to find out which two, and the answer is already written
  /// one line above in [invocation].
  List<String> requireArgs() {
    final rest = argResults!.rest;
    if (rest.length != positionals.length) {
      usageException(
        'Expected ${positionals.length} argument'
        '${positionals.length == 1 ? '' : 's'}: '
        '${positionals.map((a) => '<$a>').join(' ')}.',
      );
    }
    return rest;
  }

  /// The positional argument at [at], parsed to a [Casing].
  ///
  /// An invalid one is a usage error naming the argument and quoting what was
  /// given, because "invalid name" without the text is a message the user
  /// cannot act on.
  Casing requireCasing(int at) {
    final raw = requireArgs()[at];
    try {
      return Casing.parse(raw);
    } on FormatException catch (e) {
      usageException('Invalid ${positionals[at]} "$raw": ${e.message}');
    }
  }

  /// The single positional argument, parsed to a [Casing].
  ///
  /// What the thirteen one-argument commands call. A command taking something
  /// other than `<name>` says so in [positionals] rather than here — `flow`
  /// takes a `<page>` — so the messages and the usage line have one source.
  Casing requireName() => requireCasing(0);

  /// The positional argument at [at], split on its single `:` into a name and
  /// the text after it — `total:int`, `id:String?`.
  ///
  /// One place, because there are two: `add-field` takes this shape as a
  /// positional and `add-page --param` takes it repeatably as an option. They
  /// stay separate calls — one is an argument and the other is a flag, and the
  /// second must name *which* `--param` was wrong — but they split it the same
  /// way and refuse the same halves.
  (Casing, String) requireSpec(int at) {
    final raw = requireArgs()[at];
    try {
      final split = splitSpec(raw);
      if (split == null) {
        usageException('Expected <${positionals[at]}>, got "$raw".');
      }
      return split;
    } on FormatException catch (e) {
      // The two failures are different and were one message: `nope` is not this
      // shape at all, while `2bad:String?` is — and its name half is what is
      // wrong. Collapsing them costs the reader the sentence that says why.
      usageException('Invalid name in "$raw": ${e.message}');
    }
  }

  /// `name:rest` as a parsed name and the text after the colon, or null when it
  /// is not that shape or either half is empty.
  ///
  /// Throws [FormatException] when the shape is right and the *name* is not, so
  /// a caller can say which of the two went wrong.
  ///
  /// Static, because `--param` is not a positional and reaches it from
  /// `add-page`'s own loop.
  static (Casing, String)? splitSpec(String raw) {
    final i = raw.indexOf(':');
    if (i <= 0 || i == raw.length - 1) return null;
    final rest = raw.substring(i + 1).trim();
    if (rest.isEmpty) return null;
    return (Casing.parse(raw.substring(0, i).trim()), rest);
  }
}
