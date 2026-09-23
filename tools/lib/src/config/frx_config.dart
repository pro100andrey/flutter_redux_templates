import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/ancestors.dart';
import '../util/console.dart';

/// Project defaults read from a `.frxrc` JSON file at (or above) the working
/// directory, so a repo can set its house style once instead of everyone typing
/// the same flags. A value is applied only when the command accepts that flag
/// and the user didn't pass it — an explicit CLI flag always wins.
///
/// Recognized keys (all optional):
/// ```json
/// {
///   "buildRunner": true,      // default -b on codegen scaffolders
///   "format": true,           // default --format
///   "substateKind": "table",  // default --kind for add-substate
///   "placement": {            // per-rule opt-out for doctor's placement checks
///     "selector-outside-facade": false
///   }
/// }
/// ```
class FrxConfig {
  const FrxConfig({
    this.buildRunner,
    this.format,
    this.substateKind,
    this.placement = const {},
  });

  /// Loads `.frxrc` by walking up from [startDir] (or the current directory).
  /// A missing file yields an empty config; a malformed one warns and is
  /// ignored (a broken config must never break the CLI).
  factory FrxConfig.load({String? startDir}) {
    final file = _find(startDir);
    if (file == null) {
      return const FrxConfig();
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return FrxConfig(
        buildRunner: json['buildRunner'] as bool?,
        format: json['format'] as bool?,
        substateKind: json['substateKind'] as String?,
        placement: {
          for (final e
              in (json['placement'] as Map<String, dynamic>? ?? {}).entries)
            if (e.value is bool) e.key: e.value as bool,
        },
      );
    } on Object catch (e) {
      console.err.writeln('⚠ ignoring ${p.relative(file.path)}: $e');
      return const FrxConfig();
    }
  }

  final bool? buildRunner;
  final bool? format;
  final String? substateKind;

  /// Placement rule id → whether `frx doctor` reports it. A rule not named here
  /// is on.
  ///
  /// Not a flag, so it does not go through [applyTo]: it is read straight by
  /// the audit. Placement findings are warnings a project must be able to turn
  /// off *individually* — this template is cloned and diverged from on purpose,
  /// so a deliberate divergence should silence one rule rather than the whole
  /// check.
  final Map<String, bool> placement;

  bool get isEmpty =>
      buildRunner == null && format == null && substateKind == null;

  static const _fileName = '.frxrc';

  static File? _find(String? startDir) {
    final holder = nearestAncestorWith(
      Directory(startDir ?? Directory.current.path).absolute,
      _fileName,
    );
    return holder == null ? null : File(p.join(holder.path, _fileName));
  }

  /// Returns [args] with this config's defaults injected for the command
  /// [cmdName], skipping any the user already set or the command doesn't
  /// accept. [options] is the command's option-name set.
  ///
  /// Injected before a `--`, and only what precedes it is asked whether a
  /// flag was set: after `--` every argument is a positional, so a default
  /// appended there would be read as a name — which is why a caller could
  /// not pass `--` to keep a name like `-x` from being read as an option.
  List<String> applyTo(List<String> args, String cmdName, Set<String> options) {
    if (isEmpty) {
      return args;
    }
    final end = args.indexOf('--');
    final rest = end < 0 ? const <String>[] : args.sublist(end);
    final head = end < 0 ? args : args.sublist(0, end);
    final out = [...head];

    void injectFlag(String name, String? abbr, bool? value) {
      if (value == null || !options.contains(name)) {
        return;
      }

      if (_present(head, name, abbr)) {
        return;
      }

      out.add(value ? '--$name' : '--no-$name');
    }

    injectFlag('build-runner', 'b', buildRunner);
    injectFlag('format', null, format);
    // `kind` means different things per command (substate flavour vs action
    // body shape), so only default it for add-substate.
    if (substateKind != null &&
        cmdName == 'add-substate' &&
        options.contains('kind') &&
        !_present(head, 'kind', 'k')) {
      out
        ..add('--kind')
        ..add(substateKind!);
    }
    return [...out, ...rest];
  }

  /// Whether the user already passed `--name` / `--no-name` / `--name=…`, or
  /// the bundled short `-abbr`.
  static bool _present(List<String> args, String name, String? abbr) {
    for (final a in args) {
      if (a == '--$name' || a == '--no-$name' || a.startsWith('--$name=')) {
        return true;
      }

      if (abbr != null &&
          a.length >= 2 &&
          a[0] == '-' &&
          a[1] != '-' &&
          a.substring(1).contains(abbr)) {
        return true;
      }
    }

    return false;
  }
}
