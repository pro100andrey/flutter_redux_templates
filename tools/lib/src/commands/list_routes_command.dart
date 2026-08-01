import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import 'options.dart';
import '../util/console.dart';

/// Lists the routes registered in `AppRouter.routes`, read via AST.
///
/// Read-only inventory + the proof that [RoutesSource] parses the router
/// correctly before `add-page` starts mutating it. `--json` emits a
/// machine-readable form (the VSCode tree view consumes it).
class ListRoutesCommand extends Command<int> {
  ListRoutesCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit JSON ({routes:[{route,path,connector}]}) instead of a table.',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'list-routes';

  @override
  String get description =>
      'List the routes registered in AppRouter (parsed via AST).';

  @override
  List<String> get aliases => ['lr'];

  @override
  Future<int> run() async {
    final root = argResults?['root'] as String?;
    final source = RoutesSource.locate(startDir: root);
    final routes = source.readRoutes();

    if (argResults!.flag('json')) {
      console.out.writeln(
        jsonEncode({
          'routes': [
            for (final r in routes)
              {
                'route': r.routeType,
                'path': r.fullPath,
                'connector': PageArtifact.fromRouteType(
                  r.routeType,
                )?.connectorFile(source.connectorsDir).path,
              },
          ],
        }),
      );
      return 0;
    }

    console.out.writeln('AppRouter routes  (${source.file.path})');
    console.out.writeln();

    if (routes.isEmpty) {
      console.out.writeln('  (none found)');
      return 0;
    }

    final typeWidth = routes
        .map((r) => r.routeType.length)
        .fold(5, (a, b) => a > b ? a : b);

    console.out.writeln('  ${'ROUTE'.padRight(typeWidth)}  PATH');
    console.out.writeln('  ${'-' * typeWidth}  ${'-' * 20}');
    for (final r in routes) {
      console.out.writeln(
        '  ${r.routeType.padRight(typeWidth)}  ${r.fullPath ?? ''}',
      );
    }
    console.out.writeln();
    console.out.writeln('${routes.length} route(s).');
    return 0;
  }
}
