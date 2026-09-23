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
      final focused = whole.focusOn('consumer:EmailConnector');
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

  group('a dispatch written', () {
    const names = [
      'AAction',
      'BAction',
      'CAction',
      'DAction',
      'EAction',
      'FAction',
      'GAction',
      'HAction',
      'IAction',
      'JAction',
    ];

    AppGraph read() => _graphOf({
      '$_redux/app_state.dart': _todosAppState,
      for (final n in names)
        '$_redux/todos/actions/${n[0].toLowerCase()}_action.dart': _action(n),
      'app/lib/widgets/panel_connector.dart': '''
${[for (final n in names) "import 'package:business/redux/todos/actions/${n[0].toLowerCase()}_action.dart';"].join('\n')}

class PanelConnector extends StatelessWidget {
  final Store<AppState> store;
  void a() => store.dispatchAll([AAction(), BAction()]);
  void c() => store.dispatchAndWaitAll([CAction()]);
  void d(bool x) => store.dispatch(x ? DAction() : EAction());
  void f() {
    final act = FAction();
    store.dispatch(act);
  }
  void g() => widget.store.dispatch(GAction());
  void h() => this.dispatch(HAction());
  void i() => this.store.dispatch(IAction());
  void j(bool y) => dispatchAll([if (y) JAction()]);
  void opaque(ReduxAction<AppState> given) => store.dispatch(given);
}
''',
      'app/lib/app.dart': '''
import 'widgets/panel_connector.dart';
class App { Widget build() => PanelConnector(); }
''',
    });

    test('in any of the ordinary shapes reaches its action', () {
      final g = read();
      expect(_orphanIds(g), isEmpty);
      for (final n in names) {
        expect(
          _edges(g, from: 'consumer:PanelConnector', to: 'action:todos.$n'),
          isNotEmpty,
          reason: n,
        );
      }
    });

    test('as a value it cannot trace is a declared blind spot', () {
      final g = read();
      final gap = g.unresolved.where((u) => u.expr == 'given');
      expect(gap, hasLength(1));
      expect(gap.single.kind, 'dispatch-target');
      expect(gap.single.owner, 'consumer:PanelConnector');
      // And not a node for a class called `given`.
      expect(g.node('action:given'), isNull);
    });

    test('in a top-level function of an action file cascades', () {
      final g = _graphOf({
        '$_redux/app_state.dart': _todosAppState,
        '$_redux/todos/actions/refresh_action.dart': _action('RefreshAction'),
        '$_redux/todos/actions/toggle_action.dart': '''
import 'refresh_action.dart';

class ToggleAction extends Action {
  @override
  AppState? reduce() {
    _kick(this);
    return null;
  }
}

void _kick(Action a) => a.dispatch(RefreshAction());
''',
        'app/lib/widgets/list_connector.dart': '''
import 'package:business/redux/todos/actions/toggle_action.dart';
class ListConnector { void a() => dispatch(ToggleAction()); }
''',
        'app/lib/app.dart': '''
import 'widgets/list_connector.dart';
class App { build() => ListConnector(); }
''',
      });
      expect(
        _edges(
          g,
          from: 'action:todos.ToggleAction',
          to: 'action:todos.RefreshAction',
        ),
        isNotEmpty,
      );
      expect(_orphanIds(g), isNot(contains('action:todos.RefreshAction')));
    });

    test('a list is never read as a class name', () {
      final g = read();
      expect(g.nodes.where((n) => n.name.contains('[')), isEmpty);
    });
  });

  group('an action imported', () {
    AppGraph read() => _graphOf({
      '$_redux/app_state.dart': r'''
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required TodosState todos,
    required SessionState session,
  }) = _AppState;
}
''',
      '$_redux/todos/actions/load_action.dart': _action('LoadAction'),
      '$_redux/todos/actions/hidden_action.dart': _action('HiddenAction'),
      '$_redux/todos/actions/lonely_action.dart': _action('LonelyAction'),
      '$_redux/todos/actions/twin_action.dart': _action('TwinAction'),
      '$_redux/session/actions/twin_action.dart': _action('TwinAction'),
      // A barrel re-exporting a barrel, which exports the action files — and
      // exports itself back, which must not loop.
      'business/lib/todos.dart': '''
export 'redux/todos/barrel.dart' hide HiddenAction;
''',
      'business/lib/redux/todos/barrel.dart': '''
export '../../todos.dart';
export 'actions/load_action.dart';
export 'actions/hidden_action.dart';
''',
      'app/lib/widgets/list_connector.dart': '''
import 'package:business/todos.dart';

class ListConnector {
  void a() => dispatch(LoadAction());
  // Not through the barrel, which hides it: reached by its unique name.
  void b() => dispatch(HiddenAction());
  // No import at all frx can follow — one substate declares it.
  void c() => dispatch(LonelyAction());
  // Two substates declare it: a name is not enough.
  void d() => dispatch(TwinAction());
}
''',
      'app/lib/app.dart': '''
import 'widgets/list_connector.dart';
class App { build() => ListConnector(); }
''',
    });

    test('through a barrel reaches the action it exports', () {
      final g = read();
      final edge = _edges(
        g,
        from: 'consumer:ListConnector',
        to: 'action:todos.LoadAction',
      ).single;
      expect(edge.inferred, isFalse);
      expect(_orphanIds(g), isNot(contains('action:todos.LoadAction')));
    });

    test('by no import frx follows is matched by a unique name', () {
      final g = read();
      for (final name in ['HiddenAction', 'LonelyAction']) {
        final edge = _edges(
          g,
          from: 'consumer:ListConnector',
          to: 'action:todos.$name',
        ).single;
        expect(edge.inferred, isTrue, reason: name);
      }
    });

    test('by a name two substates declare is not guessed at', () {
      final g = read();
      expect(
        _edges(g, from: 'consumer:ListConnector').map((e) => e.to),
        isNot(contains(endsWith('TwinAction'))),
      );
    });
  });

  group('a substate named with a one-letter word', () {
    AppGraph read() => _graphOf({
      '$_redux/app_state.dart': r'''
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required ECommerceState eCommerce,
    required ABTestState aBTest,
  }) = _AppState;
}
''',
      '$_redux/e_commerce/models/e_commerce_state.dart': r'''
@freezed
abstract class ECommerceState with _$ECommerceState {
  const factory ECommerceState({String? cart}) = _ECommerceState;
}
''',
      '$_redux/selectors.dart': '''
mixin Selectors {
  AppState get state;
  SelectECommerce get eCommerce => SelectECommerce(state);
  SelectABTest get aBTest => SelectABTest(state);
}
extension type SelectECommerce(AppState _state) {
  String? get cart => _state.eCommerce.cart;
}
extension type SelectABTest(AppState _state) {
  bool get arm => _state.aBTest.arm;
}
''',
      'app/lib/widgets/cart_connector.dart': '''
class _Factory extends VmFactory<AppState, CartConnector, _Vm> with Selectors {
  _Vm fromStore() => _Vm(cart: eCommerce.cart, arm: aBTest.arm);
}
class CartConnector {}
''',
      'app/lib/app.dart': 'class App { build() => CartConnector(); }',
    });

    test('keeps its selectors, and they are read', () {
      final g = read();
      expect(g.node('selector:SelectECommerce.cart')?.substate, 'eCommerce');
      // Not derivable by casing — `aBTest` round-trips as `aBtest` — and
      // stated by the facade's spine.
      expect(g.node('selector:SelectABTest.arm')?.substate, 'aBTest');
      expect(_orphanIds(g), isEmpty);
    });
  });

  group('a connector', () {
    String connector(String name) => '''
class $name extends StatelessWidget {
  $name();
  $name.dialog();
  Widget build(BuildContext context) => const Placeholder();
}
''';

    test('built in any ordinary way is built', () {
      final g = _graphOf({
        '$_redux/app_state.dart': _todosAppState,
        '$_redux/todos/actions/noop_action.dart': _action('NoopAction'),
        for (final n in ['A', 'B', 'D', 'E', 'F'])
          'app/lib/widgets/${n.toLowerCase()}_connector.dart':
              '''
import 'package:business/redux/todos/actions/noop_action.dart';
${connector('${n}Connector')}
void _touch() => dispatch(NoopAction());
''',
        'app/lib/widgets/c_connector.dart': '''
import 'package:business/redux/todos/actions/noop_action.dart';
${connector('CConnector')}
void _touch() => dispatch(NoopAction());
extension OpenC on BuildContext {
  void openC() => showDialog(context: this, builder: (_) => CConnector());
}
''',
        'app/lib/app.dart': '''
import 'widgets/a_connector.dart';
import 'widgets/b_connector.dart';
import 'widgets/c_connector.dart';
import 'widgets/d_connector.dart';
import 'widgets/e_connector.dart';
import 'widgets/f_connector.dart';
class App {
  // A named constructor, without `const`.
  Widget a() => AConnector.dialog();
  // Tear-offs, of the unnamed constructor and of a named one.
  Widget b() => Builder(builder: BConnector.new);
  Widget d() => showX(DConnector.dialog);
  // An extension method whose body constructs it.
  void c(BuildContext context) => context.openC();
  // The control: a plain `const` construction.
  Widget e() => const [EConnector()].first;
  Widget f() => FConnector();
}
''',
      });
      final built = {
        for (final e in g.edges)
          if (e.kind == EdgeKind.builds) e.to,
      };
      for (final n in ['A', 'B', 'C', 'D', 'E', 'F']) {
        expect(built, contains('consumer:${n}Connector'), reason: n);
      }
      expect(_orphanIds(g), isEmpty);
    });

    test('second in its file is built with the file', () {
      final g = _graphOf({
        '$_redux/app_state.dart': _todosAppState,
        '$_redux/todos/actions/noop_action.dart': _action('NoopAction'),
        'app/lib/widgets/tabs_connector.dart': '''
import 'package:business/redux/todos/actions/noop_action.dart';
class TabHeaderConnector { void t() => dispatch(NoopAction()); }
class TabsConnector { build() => TabHeaderConnector(); }
''',
        'app/lib/app.dart': '''
import 'widgets/tabs_connector.dart';
class App { build() => TabsConnector(); }
''',
      });
      // The file's node is named after its first class; building the second
      // is building the file.
      expect(
        _edges(g, from: 'consumer:App', to: 'consumer:TabHeaderConnector'),
        isNotEmpty,
      );
      expect(_orphanIds(g), isEmpty);
    });
  });

  group('a selector method', () {
    AppGraph read() => _graphOf({
      '$_redux/app_state.dart': _todosAppState,
      '$_redux/todos/models/todos_state.dart': r'''
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({
    @Default([]) List<String> items,
    String? query,
  }) = _TodosState;
}
''',
      '$_redux/selectors.dart': r'''
mixin Selectors {
  AppState get state;
  SelectTodos get todos => SelectTodos(state);
}
extension type SelectTodos(AppState _state) {
  String? byIndex(int i) => _state.todos.items[i];
  String? get query => _state.todos.query;
  String label(String p) => '$p ${query ?? ''}';
}
''',
      '$_redux/todos/actions/use_action.dart': '''
class UseAction extends Action {
  @override
  AppState? reduce() {
    print(todos.byIndex(0));
    return null;
  }
}
''',
      'app/lib/widgets/todos_connector.dart': '''
import 'package:business/redux/todos/actions/use_action.dart';
class _Factory extends VmFactory<AppState, TodosConnector, _Vm> with Selectors {
  _Vm fromStore() => _Vm(
    label: todos.label('x'),
    onUse: () => dispatch(UseAction()),
  );
}
class TodosConnector {}
''',
      'app/lib/app.dart': 'class App { build() => TodosConnector(); }',
    });

    test('is a selector, and a call of it is a use', () {
      final g = read();
      expect(g.node('selector:SelectTodos.byIndex'), isNotNull);
      expect(
        _edges(g, to: 'selector:SelectTodos.byIndex').map((e) => e.from),
        contains('action:todos.UseAction'),
      );
      expect(
        _edges(g, to: 'selector:SelectTodos.label').map((e) => e.from),
        contains('consumer:TodosConnector'),
      );
    });

    test('reads what its body reads, and uses its siblings', () {
      final g = read();
      expect(
        _edges(g, from: 'selector:SelectTodos.byIndex').map((e) => e.via),
        contains('todos.items'),
      );
      expect(
        _edges(g, from: 'selector:SelectTodos.label').map((e) => e.to),
        contains('selector:SelectTodos.query'),
      );
      expect(_orphanIds(g), isEmpty);
    });
  });

  group('a composite read through `this`', () {
    test('is a read of it', () {
      final g = _graphOf({
        '$_redux/app_state.dart': r'''
@freezed
abstract class AppState with _$AppState {
  const factory AppState({required Wait wait}) = _AppState;
}
''',
        '$_redux/selectors.dart': '''
mixin Selectors { AppState get state; }
extension SelectComposites on Selectors {
  bool get isBusy => state.wait.isWaitingAny;
}
''',
        'app/lib/widgets/top_connector.dart': '''
class _Factory extends VmFactory<AppState, TopConnector, _Vm> with Selectors {
  _Vm fromStore() => _Vm(busy: this.isBusy);
}
class TopConnector {}
''',
        'app/lib/app.dart': 'class App { build() => TopConnector(); }',
      });
      expect(
        _edges(g, to: 'selector:SelectComposites.isBusy').map((e) => e.from),
        contains('consumer:TopConnector'),
      );
      expect(_orphanIds(g), isEmpty);
    });
  });

  group('the state read under another name', () {
    test('is a read of the fields behind it', () {
      final g = _graphOf({
        '$_redux/app_state.dart': _todosAppState,
        '$_redux/todos/models/todos_state.dart': r'''
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({String? selected, int? count, String? query}) =
      _TodosState;
}
''',
        '$_redux/todos/actions/use_action.dart': '''
class UseAction extends Action {
  @override
  AppState? reduce() {
    final pick = (AppState s) => s.todos.selected;
    print(pick(state));
    final AppState st = state;
    print(st.todos.count);
    final copy = state;
    print(copy.todos.query);
    return null;
  }
}
''',
        'app/lib/widgets/todos_connector.dart': '''
import 'package:business/redux/todos/actions/use_action.dart';
class TodosConnector { void a() => dispatch(UseAction()); }
''',
        'app/lib/app.dart': 'class App { build() => TodosConnector(); }',
      });
      expect(
        {
          for (final e in _edges(g, from: 'action:todos.UseAction'))
            if (e.kind == EdgeKind.reads) e.via,
        },
        {'todos.selected', 'todos.count', 'todos.query'},
      );
      expect(_orphanIds(g), isEmpty);
    });

    test('whole, by an observer comparing states, keeps no field alive', () {
      // The template's own action logger: typed `AppState` parameters,
      // compared slice by slice. Counted, every field of every slice would
      // read as used, and the dead-field list could never say anything.
      final g = _graphOf({
        '$_redux/app_state.dart': _todosAppState,
        '$_redux/todos/models/todos_state.dart': r'''
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({String? query}) = _TodosState;
}
''',
        '$_redux/store.dart': '''
class _Observer implements StateObserver<AppState> {
  void observe(ReduxAction<AppState> a, AppState prev, AppState next) {
    print(prev.todos != next.todos);
  }
}
''',
      });
      expect(_orphanIds(g), contains('field:todos.query'));
    });
  });

  group("an action's writes", () {
    AppGraph read() => _graphOf({
      '$_redux/app_state.dart': r'''
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required TodosState todos,
    required SessionState session,
  }) = _AppState;
}
''',
      '$_redux/todos/models/todos_state.dart': r'''
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({String? query, String? filter}) = _TodosState;
}
''',
      '$_redux/todos/actions/toggle_action.dart': '''
class ToggleAction extends Action {
  ToggleAction(this.payload, this.flag);
  final Payload payload;
  final bool flag;
  @override
  AppState? reduce() {
    // A local value built first: not a write of AppState.
    final t = payload.todo.copyWith(done: true);
    if (flag) {
      return state.copyWith.session(token: null);
    }
    return state.copyWith.todos(query: t.title);
  }
}
''',
    });

    test('are every write, not the first copyWith met', () {
      final g = read();
      final writes = {
        for (final e in _edges(g, from: 'action:todos.ToggleAction'))
          if (e.kind == EdgeKind.writes) e.via,
      };
      expect(writes, {'session.token', 'todos.query'});
    });

    test('mark the field written, and nothing else', () {
      final dead = {
        for (final o in read().orphans)
          if (o.node.kind == NodeKind.field) o.node.id: o.why,
      };
      expect(dead['field:todos.query'], 'written, nothing reads it');
      expect(dead['field:todos.filter'], 'nothing reads it');
    });
  });
}
