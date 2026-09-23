import 'package:args/command_runner.dart';

import '../util/casing.dart';
import '../util/dart_names.dart';

/// The kind an `add-<kind>` command creates — `add-substate` → `substate` —
/// or null when [command] is not one.
///
/// The one naming rule the CLI keeps: a command that scaffolds an artifact is
/// `add-` and the artifact. `batch` admits a command by it, and the editor's
/// contract keys a command's `--kind` values by it, so it is stated here rather
/// than tested in both.
String? createdKindOf(String command) =>
    command.startsWith('add-') ? command.substring('add-'.length) : null;

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
  /// Whether this command's names become new Dart — a class, a field, a
  /// value — and so must be names Dart accepts ([DartNames]).
  ///
  /// True for the scaffolders; false for a command that only *looks up* a
  /// name, which is whatever the thing it names is already called.
  bool get createsNames => false;

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
  ///
  /// With [creates], the name is also one this command is about to write, and
  /// is refused when Dart would not take it — or when [taken] says the context
  /// already owns it.
  Casing requireCasing(
    int at, {
    bool creates = false,
    Map<String, String> taken = const {},
  }) {
    final raw = requireArgs()[at];
    final Casing name;
    try {
      name = Casing.parse(raw);
    } on FormatException catch (e) {
      usageException('Invalid ${positionals[at]} "$raw": ${e.message}');
    }
    if (creates) {
      requireWritable(name, what: positionals[at], taken: taken);
    }
    return name;
  }

  /// Refuses [name] as a usage error when Dart would not accept it where this
  /// command writes it, naming [what] it was given as and why.
  void requireWritable(
    Casing name, {
    required String what,
    Map<String, String> taken = const {},
  }) {
    if (DartNames.problemWith(name, taken: taken) case final problem?) {
      usageException('Invalid $what: $problem.');
    }
  }

  /// The single positional argument, parsed to a [Casing].
  ///
  /// What the thirteen one-argument commands call. A command taking something
  /// other than `<name>` says so in [positionals] rather than here — `flow`
  /// takes a `<page>` — so the messages and the usage line have one source.
  ///
  /// A scaffolder's name is checked as a Dart name ([createsNames]); [taken]
  /// adds what the context already owns.
  Casing requireName({Map<String, String> taken = const {}}) =>
      requireCasing(0, creates: createsNames, taken: taken);

  /// Every value of a repeatable option, parsed to a [Casing].
  ///
  /// `add-enum -v`, `add-model -c` and `add-tabs -t` each take a list of names
  /// and each had the same four-line `try` around `Casing.parse`. The message
  /// is the parser's own, as it was at all three.
  ///
  /// Each is a name the command writes when [createsNames] — an enum value, a
  /// union case, a tab — so each is checked as one, against [taken] too.
  List<Casing> requireCasings(
    List<String> raw, {
    String what = 'name',
    Map<String, String> taken = const {},
  }) {
    final List<Casing> names;
    try {
      names = raw.map(Casing.parse).toList();
    } on FormatException catch (e) {
      usageException(e.message);
    }
    if (createsNames) {
      for (final name in names) {
        requireWritable(name, what: what, taken: taken);
      }
    }
    return names;
  }

  /// The positional argument at [at], split on its single `:` into a name and
  /// the text after it — `total:int`, `id:String?`.
  ///
  /// One place, because there are two: `add-field` takes this shape as a
  /// positional and `add-page --param` takes it repeatably as an option. They
  /// stay separate calls — one is an argument and the other is a flag, and the
  /// second must name *which* `--param` was wrong — but they split it the same
  /// way and refuse the same halves.
  ///
  /// The name half is one this command writes, checked like [requireName]'s.
  (Casing, String) requireSpec(
    int at, {
    Map<String, String> taken = const {},
  }) {
    final raw = requireArgs()[at];
    final (Casing, String) split;
    try {
      final parsed = splitSpec(raw);
      if (parsed == null) {
        usageException('Expected <${positionals[at]}>, got "$raw".');
      }
      split = parsed;
    } on FormatException catch (e) {
      // The two failures are different and were one message: `nope` is not this
      // shape at all, while `2bad:String?` is — and its name half is what is
      // wrong. Collapsing them costs the reader the sentence that says why.
      usageException('Invalid name in "$raw": ${e.message}');
    }
    if (createsNames) {
      requireWritable(split.$1, what: 'name in "$raw"', taken: taken);
    }
    return split;
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
    if (i <= 0 || i == raw.length - 1) {
      return null;
    }

    final rest = raw.substring(i + 1).trim();
    if (rest.isEmpty) {
      return null;
    }

    return (Casing.parse(raw.substring(0, i).trim()), rest);
  }
}
