import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/naming_convention.dart';
import '../model/target_resolver.dart';
import 'options.dart';
import '../util/console.dart';

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
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'which';

  @override
  String get description =>
      'Resolve an identifier (class/route/field) to its frx artifact.';

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
      return 0;
    }

    if (match == null) {
      console.out.writeln('"$token" is not a wired frx substate or page.');
      return 0;
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
