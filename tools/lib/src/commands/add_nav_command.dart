import 'dart:io';

import 'package:args/args.dart';

import '../engine/changeset.dart';
import '../model/page_artifact.dart';
import '../routing/nav_source.dart';
import '../routing/routes_source.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';

/// Wires one navigation hop: page A gains a callback that dispatches
/// `GoAction.push(BRoute(...))`, and page B's parameters come along.
///
/// The gap this closes: `add-page` creates screens, `flow --routes` draws the
/// hops between them, and nothing wrote the hops. Doing it by hand is five
/// edits across two packages — the `_Vm` field, the dispatch that fills it, the
/// argument handed to the page, and the page's own parameter and field — and
/// four of the five leave code that does not compile.
/// A Dart identifier: what `--via` becomes on both sides of the hop.
final _identifier = RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');

class AddNavCommand extends WritingCommand {
  @override
  String get name => 'add-nav';

  @override
  String get description =>
      'Wire a navigation hop from one page to another (AST).';

  @override
  String get invocation => 'frx add-nav <from> <to>';

  @override
  List<String> get aliases => ['an'];

  @override
  List<String> get positionals => const ['from', 'to'];

  @override
  WriteFlags get flags => const WriteFlags(force: false, diff: true);

  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'via',
        help:
            'Callback name on the source page. Defaults to onTap<Destination>.',
      )
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: ['push', 'replace', 'navigate'],
        defaultsTo: 'push',
        help: 'Which GoAction factory the callback dispatches.',
      );
  }

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final fromName = requireCasing(0);
    final toName = requireCasing(1);
    if (fromName.camel == toName.camel) {
      usageException('A page cannot navigate to itself.');
    }

    final routes = RoutesSource.of(repo);
    final from = PageArtifact(fromName);
    final to = PageArtifact(toName);

    final fromConnector = from.connectorFile(routes.connectorsDir);
    final fromPage = from.pageFile(repo.uiPages);
    final toConnector = to.connectorFile(routes.connectorsDir);
    for (final (file, what) in [
      (fromConnector, '${from.connectorClass} (the page you navigate from)'),
      (toConnector, '${to.connectorClass} (the page you navigate to)'),
    ]) {
      if (!file.existsSync()) refuse('Not found: $what\n  ${file.path}');
    }

    // The destination has to be a registered route: `GoAction.push` takes the
    // generated `<Page>Route`, and auto_route only generates one for a route
    // in the router.
    final registered = routes.readRoutes().any(
      (r) => r.routeType == to.routeType,
    );
    if (!registered) {
      refuse(
        '${to.routeType} is not registered in AppRouter, so auto_route '
        'generates no route class to push.\n'
        'Add the page first: frx add-page ${toName.snake}',
      );
    }

    final params = NavSource.paramsOf(toConnector);
    // `--via` is spliced into two packages as a field name, a parameter and an
    // argument, so it goes through the same gate every other name frx writes
    // does. Without it `--via 'on tap!'` scaffolded code that does not parse.
    final via = results['via'] as String?;
    if (via != null && !_identifier.hasMatch(via)) {
      usageException(
        '--via "$via" is not a Dart identifier — it becomes a field on the '
        'view-model and a parameter on the page.',
      );
    }
    final callback = via ?? 'onTap${toName.pascal}';

    const nav = NavSource();
    final connectorResult = nav.wireConnector(
      original: fromConnector.readAsStringSync(),
      callback: callback,
      routeType: to.routeType,
      method: results['kind'] as String,
      args: params.map((p) => '${p.name}: ${p.name}').join(', '),
      params: params,
      pageClass: from.pageClass,
    );
    final pageResult = fromPage.existsSync()
        ? nav.wirePage(
            content: fromPage.readAsStringSync(),
            callback: callback,
            pageClass: from.pageClass,
            params: params,
          )
        : null;

    // Said twice, and by two different mechanisms: as the skip block, and as the
    // closing line the write engine prints whether or not there was narration.
    final nothingToDo =
        '${from.pageClass} already has `$callback` — nothing to do.';

    final connector = Wiring(
      fromConnector,
      connectorResult,
      heading: '${_rel(repo, fromConnector)}:',
      skipped: nothingToDo,
      // The skip line names the page, not the file, so the path above it would
      // add nothing — the one of the nine blocks that reads that way.
      headingWhenSkipped: false,
    );
    // No skip line at all: an already-wired page is the same fact the connector
    // has just reported, and reporting it twice reads as two hops.
    final page = pageResult == null
        ? null
        : Wiring(fromPage, pageResult, heading: '${_rel(repo, fromPage)}:');

    final signature = params.isEmpty
        ? 'no arguments'
        : params.map((p) => '${p.type} ${p.name}').join(', ');

    // An already-wired hop is an empty changeset, not an early return: it used
    // to print its own line and exit, which put prose on the stdout a `--json`
    // consumer parses. Through the same path it is a changeset with nothing in
    // it — which is what "nothing to do" means.
    return WritePlan(
      changes: Changeset()
        ..addIf(connector.edit)
        ..addIf(page?.edit),
      header: 'Navigate ${from.pageClass} → ${to.pageClass}  ($signature)',
      // Not [WiringReport.narrate]: the two blocks run together, with one blank
      // line closing the pair rather than one after each.
      narrate: () {
        connector.narrate();
        page?.narrate();
        console.out.writeln();
      },
      relativeTo: repo.root.path,
      closing: connectorResult.unchanged
          ? '✓ $nothingToDo'
          : '✓ Wired. ${from.pageClass} calls `$callback` — hook it to '
                'whatever the user taps.',
    );
  }

  String _rel(FrxWorkspace repo, File f) => f.path.startsWith(repo.root.path)
      ? f.path.substring(repo.root.path.length + 1)
      : f.path;
}
