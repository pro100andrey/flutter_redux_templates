import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/graph/graph_model.dart';
import 'package:tools/src/graph/graph_reader.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// Shapes of ordinary, live code the graph used to put on its "nothing
/// reaches" list.
///
/// That list is the one place frx says "you can delete this", and the
/// `frx-graph` skill tells an agent to `frx remove` what it names — so every
/// case here is a way live code could get deleted. Where a shape truly cannot
/// be followed, the answer is an `unresolved` entry, a blind spot declared,
/// never a silent orphan.

const _redux = 'business/lib/redux';

const _emptyRouter = '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [];
}
''';

const _todosAppState = r'''
@freezed
abstract class AppState with _$AppState {
  const factory AppState({required TodosState todos}) = _AppState;
}
''';

/// Writes [files] into a fresh workspace and reads its graph.
AppGraph _graphOf(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('frx_graph_blind_');
  addTearDown(() => root.deleteSync(recursive: true));
  final all = {'app/lib/navigation/app_router.dart': _emptyRouter, ...files};
  for (final MapEntry(:key, :value) in all.entries) {
    File(p.join(root.path, key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return GraphReader(FrxWorkspace.locate(startDir: root.path)).read();
}

/// A do-nothing action class called [name].
String _action(String name) => '''
class $name extends Action {
  @override
  AppState? reduce() => null;
}
''';

Set<String> _orphanIds(AppGraph g) => {for (final o in g.orphans) o.node.id};

Iterable<GraphEdge> _edges(AppGraph g, {String? from, String? to}) =>
    g.edges.where(
      (e) => (from == null || e.from == from) && (to == null || e.to == to),
    );

void main() {
  group('a focused graph', () {
    // The whole app: a page dispatches an action that writes a slice, and a
    // connector reads a selector on it. Focused on the slice with one hop,
    // the page and the connector sit outside the bound.
    const whole = AppGraph(
      nodes: [
        GraphNode(
          id: 'substate:logIn',
          kind: NodeKind.substate,
          name: 'logIn',
          fields: {
            'fields': ['email', 'password'],
          },
        ),
        GraphNode(
          id: 'action:logIn.SetEmailAction',
          kind: NodeKind.action,
          name: 'SetEmailAction',
          substate: 'logIn',
        ),
        GraphNode(
          id: 'action:logIn.DeadAction',
          kind: NodeKind.action,
          name: 'DeadAction',
          substate: 'logIn',
        ),
        GraphNode(id: 'page:logIn', kind: NodeKind.page, name: 'logIn'),
        GraphNode(
          id: 'selector:SelectLogIn.email',
          kind: NodeKind.selector,
          name: 'SelectLogIn.email',
          substate: 'logIn',
        ),
        GraphNode(
          id: 'consumer:EmailConnector',
          kind: NodeKind.consumer,
          name: 'EmailConnector',
        ),
      ],
      edges: [
        GraphEdge(
          from: 'page:logIn',
          to: 'action:logIn.SetEmailAction',
          kind: EdgeKind.dispatches,
        ),
        GraphEdge(
          from: 'page:logIn',
          to: 'consumer:EmailConnector',
          kind: EdgeKind.builds,
        ),
        GraphEdge(
          from: 'action:logIn.SetEmailAction',
          to: 'substate:logIn',
          kind: EdgeKind.writes,
          via: 'logIn.email',
        ),
        GraphEdge(
          from: 'action:logIn.DeadAction',
          to: 'substate:logIn',
          kind: EdgeKind.writes,
          via: 'logIn.password',
        ),
        GraphEdge(
          from: 'selector:SelectLogIn.email',
          to: 'substate:logIn',
          kind: EdgeKind.reads,
          via: 'logIn.email',
        ),
        GraphEdge(
          from: 'consumer:EmailConnector',
          to: 'selector:SelectLogIn.email',
          kind: EdgeKind.uses,
        ),
      ],
    );

    test('keeps the whole graph verdict for what it shows', () {
      final focused = whole.focusOn(
        'substate:logIn',
        direction: GraphDirection.inbound,
        depth: 1,
      );
      // The dispatcher and the reader are outside the bound — and they still
      // dispatch and read.
      expect(focused.node('page:logIn'), isNull);
      expect(focused.node('consumer:EmailConnector'), isNull);
      expect(_orphanIds(focused), {
        'action:logIn.DeadAction',
        'field:logIn.password',
      });
      expect(_orphanIds(focused), _orphanIds(whole));
    });

    test('drops the verdicts about what it does not show', () {
      final focused = whole.focusOn('consumer:EmailConnector', depth: 1);
      expect(_orphanIds(focused), isEmpty);
    });

    test('narrowed to one field, names only that field of the slice', () {
      final onEmail = whole.focusOn('substate:logIn', field: 'email');
      expect(_orphanIds(onEmail), isNot(contains('field:logIn.password')));
      final onPassword = whole.focusOn('substate:logIn', field: 'password');
      expect(_orphanIds(onPassword), contains('field:logIn.password'));
    });

    test('carries the same list into its JSON', () {
      final focused = whole.focusOn(
        'substate:logIn',
        direction: GraphDirection.inbound,
      );
      final json = focused.toJson()['orphans']! as List;
      expect(
        {for (final o in json) (o as Map)['node']},
        _orphanIds(whole),
      );
    });
  });
}
