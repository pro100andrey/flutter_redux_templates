import '../graph/graph_model.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';

/// The human rendering of an [AppGraph] — what `frx graph` prints when nobody
/// asked for JSON.
///
/// Named, not counted. "3 substates, 7 reads" answers no question a reader of
/// this command has — least of all "what breaks if I touch this", where the
/// whole answer is *which* ones.
class GraphReport {
  const GraphReport(this.graph, this.workspace);

  final AppGraph graph;
  final FrxWorkspace workspace;

  void print() {
    final focus = graph.focus;
    final depth = focus?.depth == null ? 'unbounded' : 'depth ${focus!.depth}';
    console.out
      ..writeln(
        focus == null
            ? 'frx graph  (${workspace.root.path})'
            : 'frx graph  ${focus.node}  ${focus.direction.name}, '
                  '$depth  (${workspace.root.path})',
      )
      ..writeln();

    _listNodes();
    _listEdges();

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
          if (u.at != null) _short(u.at!),
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
  void _listNodes() {
    console.out.writeln('NODES (${graph.nodes.length})');
    final byKind = _grouped(graph.nodes, (n) => n.kind);
    for (final kind in NodeKind.values) {
      final of = byKind[kind];
      if (of == null) {
        continue;
      }

      of.sort((a, b) => a.id.compareTo(b.id));
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
  void _listEdges() {
    console.out
      ..writeln()
      ..writeln('EDGES (${graph.edges.length})');
    final byKind = _grouped(graph.edges, (e) => e.kind);
    for (final kind in EdgeKind.values) {
      final of = byKind[kind];
      if (of == null) {
        continue;
      }

      of.sort((a, b) => '${a.from}${a.to}'.compareTo('${b.from}${b.to}'));
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

  /// [items] bucketed by [kindOf], in one pass rather than one per kind.
  static Map<K, List<T>> _grouped<K, T>(List<T> items, K Function(T) kindOf) {
    final groups = <K, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(kindOf(item), () => []).add(item);
    }

    return groups;
  }

  /// Trims an absolute path down to repo-relative; leaves node ids alone.
  String _short(String at) {
    final root = '${workspace.root.path}/';
    return at.startsWith(root) ? at.substring(root.length) : at;
  }
}
