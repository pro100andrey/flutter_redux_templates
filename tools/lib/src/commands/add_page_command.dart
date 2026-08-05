import 'package:args/args.dart';

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../scaffold/page_scaffold.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import '../util/casing.dart';
import 'frx_command.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Scaffolds a page + connector and wires the route into `AppRouter` via AST.
///
/// The auto_route analogue of `add-substate`: generates the dumb page (in `ui`)
/// and the `@RoutePage()` connector (in `app`), then inserts the connector
/// import and an `AutoRoute(...)` entry into `app_router.dart`. build_runner
/// then generates the `<Name>Route` class the entry refers to.
class AddPageCommand extends WritingCommand {
  @override
  String get name => 'add-page';

  @override
  String get description =>
      'Scaffold a page + connector and wire the route into AppRouter (AST).';

  @override
  String get invocation => 'frx add-page <name>';

  @override
  List<String> get aliases => ['ap'];

  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addFlag(
        'public',
        negatable: false,
        help:
            'Page is reachable while logged out — add its route to the '
            'auth guard\'s _authArea set.',
      )
      ..addMultiOption(
        'param',
        abbr: 'p',
        help:
            'Typed route param "name:type" (repeatable), e.g. -p id:int. '
            'Becomes a /:name path segment + a constructor field.',
      )
      ..addOption(
        'path',
        help: 'Route path. Defaults to /<dash-name> plus a /:p per --param.',
      );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // Not stemmed here: `PageArtifact` owns that, and doing it at the call
    // site too stripped twice — `CheckoutPagePage` reached the scaffolder as
    // `CheckoutPage` and the artifact as `Checkout`, so the class, the file it
    // was written to and the route registered for it were three different
    // spellings, and the command exited 0.
    final typed = requireName();
    final public = results['public'] as bool;

    final List<PageParam> params;
    try {
      params = _parseParams(results['param'] as List<String>);
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final source = RoutesSource.of(repo);

    final a = PageArtifact(typed);
    // Everything downstream reads the artifact's own name, so there is one
    // normalisation and no way for two of them to disagree.
    final name = a.name;
    final routeType = a.routeType;
    // Default path: /<dash-name> plus a /:p segment per param.
    final path = _normalizePath(
      results['path'] as String? ??
          '${a.defaultPath}${params.map((p) => '/:${p.name}').join()}',
    );

    final scaffold = PageScaffold(name, params: params);
    final wire = source.wirePage(
      routeType: routeType,
      connectorImport: a.connectorImport,
      path: path,
      public: public,
      importMaterial: params.isNotEmpty,
    );

    final wiring = [
      Wiring.of(
        'Router',
        source.file,
        wire,
        skipped: 'route $routeType already registered — wiring skipped.',
      ),
    ];

    return WritePlan(
      changes: Changeset([
        WriteFile(a.pageFile(source.pagesDir).path, scaffold.page()),
        WriteFile(
          a.connectorFile(source.connectorsDir).path,
          scaffold.connector(),
        ),
        ...wiring.edits,
      ]),
      header:
          'Page "${name.pascal}"  '
          '(route: $routeType, path: $path${public ? ', public' : ''})',
      narrate: () {
        wiring.narrate();
        for (final warning in wire.warnings) {
          console.err.writeln('⚠ $warning');
        }
      },
      build: (_) => BuildStep.build(
        source.appPackageRoot.path,
        nextHint: 'generate the $routeType class',
      ),
    );
  }

  /// Ensures the path starts with a single leading slash.
  String _normalizePath(String path) => path.startsWith('/') ? path : '/$path';

  /// Parses `name:type` entries into typed params.
  ///
  /// Split by [NameArg.splitSpec], the same way `add-field` splits its
  /// positional — but reported here, because the message has to name *which*
  /// `--param` was wrong out of however many were given, and a positional has
  /// no such ambiguity.
  List<PageParam> _parseParams(List<String> raw) {
    final params = <PageParam>[];
    for (final entry in raw) {
      final (Casing, String)? split;
      try {
        split = NameArg.splitSpec(entry);
      } on FormatException catch (e) {
        usageException('Invalid param name in --param "$entry": ${e.message}');
      }
      if (split == null) {
        usageException('Invalid --param "$entry": expected name:type.');
      }
      params.add((name: split.$1.camel, type: split.$2));
    }
    return params;
  }
}
