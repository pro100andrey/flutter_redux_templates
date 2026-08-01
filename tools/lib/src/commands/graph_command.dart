import 'dart:convert';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../graph/graph_model.dart';
import '../graph/graph_reader.dart';
import '../model/naming_convention.dart';
import '../model/target_resolver.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'options.dart';
import '../util/console.dart';

/// Emits the whole app as one graph.
///
/// `frx flow` answers "what does this page do" and `frx flow --routes` answers
/// "how do the screens connect". Neither answers "who can change
/// `session.token`", because that crosses every reader at once — and stitching
/// six JSON outputs together is where a consumer invents the joins frx already
/// knows.
///
/// The output names its own blind spots. `unresolved` lists what frx saw but
/// could not follow, `orphans` lists actions nothing dispatches: without them,
/// a connection frx failed to parse looks exactly like a connection that is not
/// there, which is the one mistake a reader cannot detect on its own.
class GraphCommand extends Command<int> {
  GraphCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the graph as JSON (the machine-readable form).',
      )
      ..addOption(
        'focus',
        help:
            'Only the subgraph around one artifact. Takes a node id '
            '(page:logIn), a symbol (LogInRoute, SetEmailAction) or a bare name '
            '(log_in).',
      )
      ..addOption(
        'direction',
        abbr: 'd',
        allowed: GraphDirection.values.map((d) => d.name),
        defaultsTo: GraphDirection.both.name,
        help: 'With --focus: which way to follow the edges.',
        allowedHelp: {
          'inbound':
              'What depends on it — "what breaks if I touch this". '
              'Unbounded unless --depth says otherwise.',
          'outbound': 'What it reaches.',
          'both': 'Everything around it (the default).',
        },
      )
      ..addOption(
        'depth',
        defaultsTo: '1',
        help:
            'With --focus: how many hops out to follow, or `all` for as far as '
            'the edges go.',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'graph';

  @override
  String get description =>
      'Emit the whole app as one graph (nodes, edges, and what frx could not '
      'resolve).';

  @override
  String get invocation =>
      'frx graph [--json] [--focus <artifact>] [--direction inbound]';

  @override
  List<String> get aliases => ['g'];

  @override
  Future<int> run() async {
    final results = argResults!;
    final focusArg = results['focus'] as String?;
    final direction = GraphDirection.parse(results['direction'] as String);

    if (focusArg == null && results.wasParsed('depth')) {
      usageException('--depth only applies with --focus.');
    }
    if (focusArg == null && results.wasParsed('direction')) {
      usageException('--direction only applies with --focus.');
    }

    // Unbounded by default for an inbound walk. An impact answer is read as
    // exhaustive, and one hop of it answers a question nobody asked; an
    // outbound or undirected walk keeps the single hop it has always taken.
    final int? depth;
    final rawDepth = results['depth'] as String;
    if (!results.wasParsed('depth')) {
      depth = direction == GraphDirection.inbound ? null : 1;
    } else if (rawDepth == 'all') {
      depth = null;
    } else {
      final parsed = int.tryParse(rawDepth);
      if (parsed == null || parsed < 1) {
        usageException(
          '--depth must be a positive integer or `all`, got "$rawDepth".',
        );
      }
      depth = parsed;
    }

    final FrxWorkspace workspace;
    try {
      workspace = FrxWorkspace.locate(startDir: results['root'] as String?);
    } on StateError catch (e) {
      console.err.writeln('frx: ${e.message}');
      return 70;
    }

    final AppGraph whole;
    try {
      whole = GraphReader(workspace).read();
    } on StateError catch (e) {
      console.err.writeln('frx: ${e.message}');
      return 70;
    }

    var graph = whole;
    if (focusArg != null) {
      final resolved = _resolveFocus(focusArg, whole, results);
      if (resolved.error != null) {
        console.err.writeln('frx: ${resolved.error}');
        return 70;
      }
      graph = whole.focusOn(resolved.id!, depth: depth, direction: direction);
    }

    if (results.flag('json')) {
      console.out.writeln(jsonEncode(graph.toJson()));
      return 0;
    }

    _report(graph, workspace);
    return 0;
  }

  /// The node id [token] names, or the reason it names none.
  ///
  /// Three spellings, most specific first: a node id, then whatever the
  /// identifier resolver makes of a substate/page symbol, then a bare node name.
  /// The resolver is the one `frx which` and the editor's F2 already use — a
  /// second implementation of "what does `LogInRoute` mean" is how the
  /// conventions fork.
  ({String? id, String? error}) _resolveFocus(
    String token,
    AppGraph graph,
    ArgResults results,
  ) {
    if (graph.node(token) != null) return (id: token, error: null);

    final resolver = TargetResolver.locate(results['root'] as String?);
    final match = NamingConvention.resolve(
      token,
      isSubstate: resolver.isSubstate,
      isPage: resolver.isPage,
    );
    if (match != null) {
      final camel = Casing.parse(match.name).camel;
      final id = match.kind == ArtifactKind.substate
          ? 'substate:$camel'
          : 'page:$camel';
      if (graph.node(id) != null) return (id: id, error: null);
    }

    // Actions, selectors and services are not the resolver's business — it
    // answers "substate or page". Their node names are unique enough to match
    // on, and when they are not, the candidates are worth more than a guess.
    final byName = [
      for (final n in graph.nodes)
        if (n.name == token) n,
    ];
    if (byName.length == 1) return (id: byName.single.id, error: null);
    if (byName.length > 1) {
      return (
        id: null,
        error:
            '"$token" names ${byName.length} nodes — '
            '${byName.map((n) => n.id).join(', ')}. Pass one of those ids.',
      );
    }

    return (
      id: null,
      error:
          'nothing in the graph is called "$token".\n'
          'Takes a node id (page:logIn, substate:session, '
          'action:logIn.SetEmailAction), a symbol (LogInRoute, LogInState) or a '
          'bare name (log_in). Run `frx graph` to list them.',
    );
  }

  void _report(AppGraph graph, FrxWorkspace workspace) {
    final focus = graph.focus;
    console.out
      ..writeln(
        focus == null
            ? 'frx graph  (${workspace.root.path})'
            : 'frx graph  ${focus.node}  ${focus.direction.name}, '
                  '${focus.depth == null ? 'unbounded' : 'depth ${focus.depth}'}'
                  '  (${workspace.root.path})',
      )
      ..writeln();

    // Named, not counted. "3 substates, 7 reads" answers no question a reader of
    // this command has — least of all "what breaks if I touch this", where the
    // whole answer is *which* ones.
    _listNodes(graph);
    _listEdges(graph);

    // Stated whenever a bound was applied, because an impact answer is read as
    // exhaustive: a truncated dependency list looks exactly like a short one.
    if (focus != null && focus.truncated) {
      console.out
        ..writeln()
        ..writeln(
          '⚠ stopped at depth ${focus.depth} — there is more beyond it. '
          'Re-run with --depth all.',
        );
    }

    // The blind spots come last so they are what stays on screen.
    if (graph.unresolved.isNotEmpty) {
      console.out
        ..writeln()
        ..writeln('⚠ ${graph.unresolved.length} unresolved');
      for (final u in graph.unresolved) {
        final where = [
          u.kind,
          if (u.expr != null) u.expr!,
          if (u.at != null) _short(u.at!, workspace),
        ].join('  ');
        console.out
          ..writeln('  $where')
          ..writeln('      ${u.why}');
      }
    }

    final orphans = graph.orphans;
    if (orphans.isNotEmpty) {
      console.out
        ..writeln()
        ..writeln('⚠ ${orphans.length} artifact(s) nothing reaches');
      for (final o in orphans) {
        console.out.writeln('  ${o.node.id.padRight(46)}  ${o.why}');
      }
    }

    if (graph.unresolved.isEmpty && orphans.isEmpty) {
      console.out
        ..writeln()
        ..writeln('✓ every reference resolved, every action reachable.');
    }
  }

  /// The nodes, grouped by kind and named. An unresolved node is marked, so a
  /// placeholder standing in for something frx could not find is not read as an
  /// artifact that exists.
  void _listNodes(AppGraph graph) {
    console.out.writeln('NODES (${graph.nodes.length})');
    for (final kind in NodeKind.values) {
      final of = [
        for (final n in graph.nodes)
          if (n.kind == kind) n,
      ]..sort((a, b) => a.id.compareTo(b.id));
      if (of.isEmpty) continue;
      console.out.writeln('  ${kind.name} (${of.length})');
      for (final n in of) {
        console.out.writeln(
          '    ${n.name}${n.resolved ? '' : '  (unresolved)'}'
          '${n.substate == null ? '' : '  ← ${n.substate}'}',
        );
      }
    }
  }

  /// The edges, grouped by kind, each as `from → to` with what triggers it.
  void _listEdges(AppGraph graph) {
    console.out
      ..writeln()
      ..writeln('EDGES (${graph.edges.length})');
    for (final kind in EdgeKind.values) {
      final of = [
        for (final e in graph.edges)
          if (e.kind == kind) e,
      ]..sort((a, b) => '${a.from}${a.to}'.compareTo('${b.from}${b.to}'));
      if (of.isEmpty) continue;
      console.out.writeln('  ${kind.name} (${of.length})');
      for (final e in of) {
        final detail = [
          if (e.via != null) 'via ${e.via}',
          if (e.condition != null) 'if ${e.condition}',
          if (e.inferred) 'inferred',
        ].join(', ');
        console.out.writeln(
          '    ${e.from} → ${e.to}${detail.isEmpty ? '' : '  ($detail)'}',
        );
      }
    }
  }

  /// Trims an absolute path down to repo-relative; leaves node ids alone.
  String _short(String at, FrxWorkspace workspace) {
    final root = '${workspace.root.path}/';
    return at.startsWith(root) ? at.substring(root.length) : at;
  }
}
