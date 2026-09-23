import 'dart:convert';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../graph/graph_model.dart';
import '../graph/graph_reader.dart';
import '../model/naming_convention.dart';
import '../model/target_resolver.dart';
import '../refusal.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'graph_report.dart';
import 'options.dart';
import 'reading.dart';

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
            '(page:logIn), a symbol (LogInRoute, SetEmailAction), a bare '
            'name (log_in), or one field of a substate (session.token) — '
            'what touches that field, not the whole slice.',
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
      ..addFlag(
        'fail-on-orphans',
        negatable: false,
        help:
            'Exit 1 when the "nothing reaches" list is not empty — a gate for '
            'CI. Advice rather than drift, which is why doctor does not report '
            'it: `add-action -k waiting` writes an isWaiting getter nothing '
            "reads yet, and a check that fired on frx's own output would be "
            'noise.',
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
    } on FrxRefusal catch (e) {
      return refused(e);
    }

    final AppGraph whole;
    try {
      whole = GraphReader(workspace).read();
    } on FrxRefusal catch (e) {
      return refused(e);
    }

    var graph = whole;
    if (focusArg != null) {
      final resolved = _resolveFocus(focusArg, whole, results);
      if (resolved.error != null) {
        console.err.writeln('frx: ${resolved.error}');
        return 70;
      }
      graph = whole.focusOn(
        resolved.id!,
        depth: depth,
        direction: direction,
        field: resolved.field,
      );
    }

    if (results.flag('json')) {
      console.out.writeln(jsonEncode(graph.toJson()));
    } else {
      GraphReport(graph, workspace).print();
    }

    // The gate reads the graph that was printed, so with `--focus` it answers
    // for the subgraph on screen — what a reader would check by eye. Each
    // verdict on it is still the whole app's: see `AppGraph.orphans`.
    if (results.flag('fail-on-orphans') && graph.orphans.isNotEmpty) {
      return 1;
    }

    return 0;
  }

  /// The node id [token] names, or the reason it names none.
  ///
  /// Four spellings, most specific first: a node id, then a substate's field
  /// (`session.token`), then whatever the identifier resolver makes of a
  /// substate/page symbol, then a bare node name. The resolver is the one
  /// `frx which` and the editor's F2 already use — a second implementation of
  /// "what does `LogInRoute` mean" is how the conventions fork.
  ({String? id, String? field, String? error}) _resolveFocus(
    String token,
    AppGraph graph,
    ArgResults results,
  ) {
    if (graph.node(token) != null) {
      return (id: token, field: null, error: null);
    }

    // `session.token` — two lower-case identifiers, the first a substate.
    // Checked against the slice's own fields: a focus on a field that is not
    // there would be answered with whatever touches the whole slice, which
    // reads as "only the persistor" about a typo.
    final field = _fieldSpelling.firstMatch(token);
    if (field != null) {
      final id = 'substate:${Casing.parse(field[1]!).camel}';
      final node = graph.node(id);
      if (node != null) {
        final fields = node.fields['fields'];
        if (fields is! List) {
          return (
            id: null,
            field: null,
            error:
                '${field[1]} is not a slice of ours — it has no state class '
                'to list the fields of.',
          );
        }
        if (!fields.contains(field[2])) {
          return (
            id: null,
            field: null,
            error:
                '${field[1]} has no field `${field[2]}`. It has: '
                '${fields.join(', ')}.',
          );
        }
        return (id: id, field: field[2], error: null);
      }
    }

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
      if (graph.node(id) != null) {
        return (id: id, field: null, error: null);
      }
    }

    // Actions, selectors and services are not the resolver's business — it
    // answers "substate or page". Their node names are unique enough to match
    // on, and when they are not, the candidates are worth more than a guess.
    final byName = [
      for (final n in graph.nodes)
        if (n.name == token) n,
    ];
    if (byName.length == 1) {
      return (id: byName.single.id, field: null, error: null);
    }

    if (byName.length > 1) {
      return (
        id: null,
        field: null,
        error:
            '"$token" names ${byName.length} nodes — '
            '${byName.map((n) => n.id).join(', ')}. Pass one of those ids.',
      );
    }

    return (
      id: null,
      field: null,
      error:
          'nothing in the graph is called "$token".\n'
          'Takes a node id (page:logIn, substate:session, '
          'action:logIn.SetEmailAction), a symbol (LogInRoute, LogInState), '
          'a bare name (log_in) or a field (session.token). Run `frx graph` '
          'to list them.',
    );
  }

  /// `session.token`, or `log_in.email` — the substate however the caller
  /// spells it, since `--focus log_in` already takes the snake form — and
  /// `field:session.token`, which is how the orphan list names one.
  static final _fieldSpelling = RegExp(
    r'^(?:field:)?([a-z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9]*)$',
  );
}
