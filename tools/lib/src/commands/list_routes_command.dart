import 'dart:convert';

import 'package:args/command_runner.dart';

import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../util/console.dart';
import 'inventory.dart';
import 'options.dart';

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

    printInventory(
      title: 'AppRouter routes  (${source.file.path})',
      columns: ('ROUTE', 'PATH'),
      rows: [for (final r in routes) (r.routeType, r.fullPath ?? '')],
      unit: 'route',
    );
    return 0;
  }
}
