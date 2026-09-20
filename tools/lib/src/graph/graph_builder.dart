/// The graph under construction: what has been added so far, and which node
/// owns which file.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../util/casing.dart';
import 'graph_model.dart';

/// Collects nodes, edges and blind spots as the passes of a read find them.
///
/// Both collections de-duplicate on identity and keep first-come order, so a
/// pass that attributes a relation more precisely runs first and a later,
/// barer duplicate of it is dropped.
class GraphBuilder {
  final _nodes = <String, GraphNode>{};
  final _edges = <String, GraphEdge>{};
  final unresolved = <Unresolved>[];

  /// Canonical file path → the node that owns it, for the files that read
  /// selectors: a connector, an action, a service dispatcher. Claimed as each
  /// pass runs so the later sweeps can say *who* reads or dispatches what,
  /// rather than re-deriving the same file-to-artifact map a third time.
  final _owners = <String, String>{};

  Iterable<GraphNode> get nodes => _nodes.values;
  Iterable<GraphEdge> get edges => _edges.values;

  void addNode(GraphNode n) => _nodes.putIfAbsent(n.id, () => n);
  void addEdge(GraphEdge e) => _edges.putIfAbsent(e.key, () => e);

  bool hasNode(String id) => _nodes.containsKey(id);

  /// Whether `AppState` composes a substate called [field] — the test every
  /// edge into a substate makes, so a `copyWith` field that is not one draws
  /// nothing.
  bool hasSubstate(String field) => hasNode('substate:$field');

  /// Records that [file] belongs to the node [id].
  void own(String file, String id) => _owners[p.canonicalize(file)] = id;

  /// The node [file] belongs to, or null when no artifact claimed it.
  String? ownerOf(String file) => _owners[p.canonicalize(file)];

  /// The node [file] is read as: the artifact that owns it, or — for a file no
  /// artifact owns — a [NodeKind.consumer] node made for it, once.
  ///
  /// The dispatcher, reader or builder with no node of its own — see
  /// [NodeKind.consumer]. The one place a sweep over the app's own files gets
  /// its `from` node, so the sweeps cannot disagree about what a file is.
  String nodeFor(File file, CompilationUnit unit) {
    final owner = ownerOf(file.path);
    if (owner != null) {
      return owner;
    }
    final name = artifactNameIn(unit, file);
    final id = 'consumer:$name';
    addNode(
      GraphNode(id: id, kind: NodeKind.consumer, name: name, file: file.path),
    );
    return id;
  }

  AppGraph build() => AppGraph(
    nodes: nodes.toList(),
    edges: edges.toList(),
    unresolved: unresolved,
  );
}

/// What to call the artifact in [file]: its first public class, or the file's
/// own name in Pascal case when it declares none.
///
/// Public, because a connector file that puts its `_Factory` above the
/// widget is still the connector, and a node called `_Factory` names nothing
/// anyone would look for — three files in a project all called that would be
/// one node. A file of private classes only is named by the file, which by
/// the convention is the artifact's name.
String artifactNameIn(CompilationUnit unit, File file) {
  for (final c in classesIn(unit)) {
    final name = c.namePart.typeName.lexeme;
    if (!name.startsWith('_')) {
      return name;
    }
  }
  return Casing.parse(p.basenameWithoutExtension(file.path)).pascal;
}
