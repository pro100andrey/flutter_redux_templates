import 'package:args/args.dart';

import '../model/artifact_name.dart';
import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../scaffold/page_scaffold.dart';
import '../scaffold/tabs_scaffold.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Scaffolds a tab flow: a shell page hosting `AutoTabsScaffold` over N tab
/// pages, and a nested `AutoRoute` (shell + children) wired into `AppRouter`.
class AddTabsCommand extends WritingCommand {
  @override
  String get name => 'add-tabs';

  @override
  String get description =>
      'Scaffold an AutoTabsScaffold shell + tab pages and wire the nested route.';

  @override
  String get invocation => 'frx add-tabs <name> --tab <t1> --tab <t2> …';

  @override
  List<String> get aliases => ['at'];

  @override
  WriteFlags get flags => const WriteFlags(buildRunner: true);

  @override
  void describeArgs(ArgParser parser) {
    parser.addMultiOption(
      'tab',
      abbr: 't',
      help: 'A tab page name (repeatable, ≥2), e.g. -t home -t profile.',
    );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // See [ArtifactName]: the shell and each tab take either spelling.
    final name = ArtifactName.pageStem(requireName());
    final tabArgs = results['tab'] as List<String>;
    if (tabArgs.length < 2) {
      usageException('Provide at least two --tab options.');
    }

    final List<Casing> tabs;
    try {
      tabs = tabArgs.map(Casing.parse).toList();
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final source = RoutesSource.of(repo);

    final shell = PageArtifact(name);
    final shellRoute = shell.routeType;
    final shellPath = shell.defaultPath;

    // Files: a page + @RoutePage() connector per tab, plus the shell connector.
    final files = <String, String>{};
    for (final tab in tabs) {
      final scaffold = PageScaffold(tab);
      final a = PageArtifact(tab);
      files[a.pageFile(source.pagesDir).path] = scaffold.page();
      files[a.connectorFile(source.connectorsDir).path] = scaffold.connector();
    }
    files[shell.connectorFile(source.connectorsDir).path] = TabsScaffold(
      name,
      tabs,
    ).shell();

    final wire = source.wireTabsRoute(
      shellRoute: shellRoute,
      connectorImports: [
        shell.connectorImport,
        for (final tab in tabs) PageArtifact(tab).connectorImport,
      ],
      path: shellPath,
      tabs: [
        for (final tab in tabs)
          (route: PageArtifact(tab).routeType, path: tab.words.join('-')),
      ],
    );

    final wiring = [
      Wiring.of(
        'Router',
        source.file,
        wire,
        skipped: 'route $shellRoute already registered — wiring skipped.',
      ),
    ];

    return WritePlan(
      changes: Changeset([
        for (final entry in files.entries) WriteFile(entry.key, entry.value),
        ...wiring.edits,
      ]),
      header:
          'Tabs "${name.pascal}"  '
          '(route: $shellRoute, path: $shellPath, '
          'tabs: ${tabs.map((t) => t.pascal).join(', ')})',
      narrate: wiring.narrate,
      build: (_) => BuildStep.build(
        source.appPackageRoot.path,
        nextHint: 'generate the route classes',
      ),
    );
  }
}
