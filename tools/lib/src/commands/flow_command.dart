import 'dart:convert';

import 'package:args/command_runner.dart';

import '../flow/flow_docs.dart';
import '../flow/flow_reader.dart';
import '../flow/mermaid.dart';
import '../flow/route_map.dart';
import '../model/page_artifact.dart';
import '../workspace/frx_workspace.dart';
import 'frx_command.dart';
import 'options.dart';
import '../util/console.dart';

/// Diagrams what the app actually does, read from the AST.
///
/// Three views of the same model: one page's use cases as a sequence diagram
/// (`frx flow <page>`), the whole app's screens and the hops between them
/// (`--routes`), and both exported to `docs/flows/` as markdown (`--md`).
/// Because everything is derived from the source, it can't drift the way a
/// hand-drawn diagram does — and `--md --check` (also run by `frx doctor`)
/// fails the moment it starts to.
class FlowCommand extends Command<int> with NameArg {
  FlowCommand() {
    argParser
      ..addFlag(
        'routes',
        negatable: false,
        help:
            'Diagram the whole app: every screen and the navigation between '
            'them, instead of one page.',
      )
      ..addFlag(
        'md',
        negatable: false,
        help: 'Export every diagram to docs/flows/ as markdown.',
      )
      ..addFlag(
        'check',
        negatable: false,
        help:
            'With --md: verify the export is up to date instead of writing it. '
            'Exits 1 when it is not (for CI).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit the raw flow model as JSON (the VSCode viewer consumes it).',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'flow';

  @override
  String get description =>
      'Diagram use cases and navigation (mermaid) from the AST.';

  @override
  String get invocation => 'frx flow <page> | frx flow --routes | --md';

  @override
  List<String> get positionals => const ['page'];

  @override
  List<String> get aliases => ['fl'];

  @override
  Future<int> run() async {
    final routes = argResults!.flag('routes');
    final md = argResults!.flag('md');
    final json = argResults!.flag('json');

    if (routes && md) {
      usageException('Use either --routes or --md, not both.');
    }
    if (argResults!.flag('check') && !md) {
      usageException('--check only applies to --md.');
    }
    if ((routes || md) && argResults!.rest.isNotEmpty) {
      usageException(
        '--${routes ? 'routes' : 'md'} covers the whole app — drop the '
        '<page> argument.',
      );
    }

    final FrxWorkspace workspace;
    try {
      workspace = FrxWorkspace.locate(startDir: argResults?['root'] as String?);
    } on StateError catch (e) {
      console.err.writeln('frx: ${e.message}');
      return 70;
    }

    if (md) return _exportDocs(workspace, json: json);
    if (routes) return _routeMap(workspace, json: json);
    return _pageFlow(workspace, json: json);
  }

  // --- one page ---------------------------------------------------------------

  int _pageFlow(FrxWorkspace workspace, {required bool json}) {
    final input = requireName();
    final artifact = PageArtifact(input);
    final connector = artifact.connectorFile(workspace.appConnectors);
    if (!connector.existsSync()) {
      console.err.writeln(
        'frx: no page "${input.camel}" — expected ${connector.path}.\n'
        'Run `frx list-routes` to see the pages that exist.',
      );
      return 70;
    }

    final flow = FlowReader(workspace).read(
      connectorFile: connector,
      page: artifact.name.camel,
      connectorClass: artifact.connectorClass,
      pageClass: artifact.pageClass,
    );

    if (json) {
      console.out.writeln(jsonEncode(flow.toJson()));
      return 0;
    }

    if (flow.isEmpty) {
      // "Nothing to diagram" is a claim about the code, and it has to be earned.
      // A page whose every dispatch was written in a shape the reader does not
      // follow reaches here too, and saying the same sentence turns a gap in the
      // reader into a statement about the page — the purest form of the failure
      // `untraced` exists to prevent.
      if (flow.untraced.isEmpty) {
        console.out.writeln(
          '${artifact.connectorClass} has no dispatching callbacks — '
          'nothing to diagram yet.',
        );
        return 0;
      }
      // Stated as what it is — nothing was drawn, and these files dispatch —
      // rather than as a diagnosis. Part of what is counted here is a callback
      // the reader could not follow; part of it never was a callback, such as a
      // `StoreConnector(onInit: …)` that dispatches on open. Naming a cause the
      // tool cannot tell apart would be guessing in the one output added to stop
      // guesses being read as facts.
      console.out.writeln(
        '${artifact.connectorClass}: no interaction to diagram, and these '
        'files dispatch anyway:',
      );
      for (final gap in flow.untraced) {
        console.out.writeln('  ${gap.connectorClass}  ${gap.calls}');
      }
      console.out.writeln(
        '\nWhat gets drawn is a dispatch reachable from a `_Vm(...)` argument '
        'through the functions the file declares. A callback kept in a field, '
        'or a dispatch that belongs to no callback at all, is outside that.',
      );
      return 0;
    }

    console.out.writeln(renderSequence(flow));
    return 0;
  }

  // --- the whole app ----------------------------------------------------------

  int _routeMap(FrxWorkspace workspace, {required bool json}) {
    final RouteMap map;
    try {
      map = RouteMapReader(workspace).read();
    } on StateError catch (e) {
      console.err.writeln('frx: ${e.message}');
      return 70;
    }

    if (json) {
      console.out.writeln(jsonEncode(map.toJson()));
      return 0;
    }

    if (map.isEmpty) {
      console.out.writeln('No routes registered — nothing to diagram yet.');
      return 0;
    }

    console.out.writeln(renderRouteMap(map));
    return 0;
  }

  // --- markdown export --------------------------------------------------------

  int _exportDocs(FrxWorkspace workspace, {required bool json}) {
    final check = argResults!.flag('check');
    final docs = FlowDocs(workspace);

    final RouteMap map;
    try {
      map = RouteMapReader(workspace).read();
    } on StateError catch (e) {
      console.err.writeln('frx: ${e.message}');
      return 70;
    }

    // `--check` reports against what is on disk; without the directory there is
    // nothing to be stale, so say so rather than passing silently.
    if (check && !docs.enabled) {
      final msg =
          'frx: ${docs.dir.path} does not exist — run `frx flow --md` to '
          'create it.';
      if (json) {
        console.out.writeln(jsonEncode({'enabled': false, 'drift': []}));
      } else {
        console.err.writeln(msg);
      }
      return 70;
    }

    final changes = check ? docs.check(map) : docs.write(map);

    if (json) {
      console.out.writeln(
        jsonEncode({
          'enabled': true,
          'dir': docs.dir.path,
          'drift': [
            for (final c in changes)
              {'kind': c.kind.name, 'file': c.path, 'relative': c.relative},
          ],
        }),
      );
      return check && changes.isNotEmpty ? 1 : 0;
    }

    if (changes.isEmpty) {
      console.out.writeln(
        check
            ? '✓ docs/flows is up to date.'
            : '✓ docs/flows is already up to date — nothing written.',
      );
      return 0;
    }

    for (final c in changes) {
      console.out.writeln(
        check
            ? '  ✗ ${c.message}'
            : '  ${c.kind == DocDriftKind.orphan ? 'delete' : 'write '} '
                  '${c.relative}',
      );
    }
    console.out.writeln();

    if (!check) {
      console.out.writeln('${changes.length} file(s) written to docs/flows.');
      return 0;
    }
    console.out.writeln(
      '${changes.length} file(s) out of date — run `frx flow --md`.',
    );
    return 1;
  }
}
