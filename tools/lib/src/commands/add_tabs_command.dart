import 'package:args/args.dart';

import '../engine/build_step.dart';
import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../routing/routes_source.dart';
import '../scaffold/page_scaffold.dart';
import '../scaffold/tabs_scaffold.dart';
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
      'Scaffold an AutoTabsScaffold shell + tab pages and wire the nested '
      'route.';

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
    // See [PageArtifact], which owns the stemming — the shell and each tab
    // take either spelling, and neither is stemmed here.
    final typed = requireName();
    final tabArgs = results['tab'] as List<String>;
    if (tabArgs.length < 2) {
      usageException('Provide at least two --tab options.');
    }

    final tabs = requireCasings(tabArgs, what: 'tab');

    final source = RoutesSource.of(repo);

    final shell = PageArtifact(typed);
    final name = shell.name;
    final shellRoute = shell.routeType;
    final shellPath = shell.defaultPath;
    // The artifact's name, not the argument, for everything below: a tab named
    // `BasketPage` was scaffolded as `class BasketPagePage` into
    // `basket_page.dart`, with a connector importing a `basket_page_page.dart`
    // nobody wrote — and `tab.words` gave it the path `basket-page` under a
    // route named `BasketRoute`.
    final tabArtifacts = [for (final tab in tabs) PageArtifact(tab)];

    // Files: a page + @RoutePage() connector per tab, plus the shell connector.
    final files = <String, String>{};
    for (final a in tabArtifacts) {
      final scaffold = PageScaffold(a.name);
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
        for (final a in tabArtifacts) a.connectorImport,
      ],
      path: shellPath,
      tabs: [
        for (final a in tabArtifacts)
          (route: a.routeType, path: a.name.words.join('-')),
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
