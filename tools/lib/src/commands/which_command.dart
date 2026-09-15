import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/naming_convention.dart';
import '../model/target_resolver.dart';
import '../util/console.dart';
import 'options.dart';

/// Resolves an identifier (a generated class, route, field or folder name) back
/// to the frx artifact it belongs to — the authoritative token → artifact map.
///
/// The VSCode extension calls `which <token> --json` for its editor rename: it
/// needs to know whether the symbol under the cursor is a renamable substate or
/// page, the canonical base name to hand `frx rename`, and which suffix/prefix
/// was stripped (so it can strip the same one from the new name). Keeping the
/// convention knowledge here means the extension stays a thin shell.
class WhichCommand extends Command<int> {
  WhichCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit JSON ({kind, name, suffix, prefix}) instead of a line. '
            'kind is null when the identifier is not a wired artifact.',
      )
      // No flag for the exit code: a miss exits 1 in both modes (see
      // [exitNoMatch]), and the JSON is still printed on it.
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'which';

  @override
  String get description =>
      'Resolve an identifier (class/route/field) to its frx artifact. '
      'Exits 1 when nothing wired answers to it.';

  /// Nothing is wired under that name.
  ///
  /// `grep`'s convention, and `upgrade --check`'s: 1 is "no", not "broken".
  /// It used to be 0 with a sentence, which read as success to anything that
  /// does not parse English — an agent gating a rename on `frx which`, a
  /// script's `&&`. A refusal (70) is wrong the other way: the question was
  /// answerable, and the answer was no.
  static const exitNoMatch = 1;

  @override
  String get invocation => 'frx which <identifier>';

  @override
  List<String> get aliases => ['w'];

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Expected exactly one <identifier> argument.');
    }
    final token = results.rest.single;
    final resolver = TargetResolver.locate(results['root'] as String?);
    final match = _resolve(token, resolver);

    if (results.flag('json')) {
      console.out.writeln(
        jsonEncode(
          match == null
              ? {'kind': null}
              : {
                  'kind': match.kind.name,
                  'name': match.name,
                  'suffix': match.suffix,
                  'prefix': match.prefix,
                },
        ),
      );
      return match == null ? exitNoMatch : 0;
    }

    if (match == null) {
      console.out.writeln('"$token" is not a wired frx substate or page.');
      return exitNoMatch;
    }
    final via = match.suffix != null
        ? ' (from the ${match.suffix} suffix)'
        : match.prefix != null
        ? ' (from the ${match.prefix} prefix)'
        : '';
    console.out.writeln('${match.kind.name}  ${match.name}$via');
    return 0;
  }

  /// Strips a known frx suffix/prefix off [token] to get a candidate base name,
  /// then confirms it against the wiring. Tries the most specific forms first;
  /// the bare token (a field or folder name) is the fallback. Returns null when
  /// nothing wired matches.
  ResolvedName? _resolve(String token, TargetResolver resolver) =>
      NamingConvention.resolve(
        token,
        isSubstate: resolver.isSubstate,
        isPage: resolver.isPage,
      );
}
