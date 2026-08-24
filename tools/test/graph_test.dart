import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/ast/source_index.dart';
import 'package:tools/src/flow/route_map.dart';
import 'package:tools/src/graph/graph_model.dart';
import 'package:tools/src/graph/graph_reader.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// A workspace built around the things that only break once the readers are
/// joined: a class name that is not unique, a dispatcher that is not a page,
/// and a reference that is a type argument rather than a call.
FrxWorkspace _workspace() {
  final root = Directory.systemTemp.createTempSync('frx_graph_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) {
    File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  put('business/lib/redux/app_state.dart', '''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required LogInState logIn,
    required RegistrationState registration,
    required SessionState session,
    required Wait wait,
  }) = _AppState;
}
''');

  put('business/lib/redux/selectors.dart', '''
extension type SelectLogIn(AppState _state) implements Selector {
  bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();
  String? get email => _state.logIn.email;
  String? get password => _state.logIn.password;
}

extension type SelectSession(AppState _state) implements Selector {
  String? get token => _state.session.token;
  bool get isAvailable => token != null;
}

// A composite: reads other selectors rather than the state. Nothing reads it,
// which is what makes everything it alone reads dead too.
extension SelectComposites on Select {
  bool get canEnterApp => session.isAvailable && !logIn.isWaiting;
}
''');

  // The same class name in two substates — the reason a bare class name cannot
  // be a node id.
  for (final substate in ['log_in', 'registration']) {
    put('business/lib/redux/$substate/actions/set_email_action.dart', '''
class SetEmailAction extends Action {
  SetEmailAction(this.value);
  final String? value;
  @override
  AppState reduce() => state.copyWith.${substate == 'log_in' ? 'logIn' : 'registration'}(email: value);
}
''');
  }

  put('business/lib/redux/log_in/actions/log_in_action.dart', '''
import '../../session/actions/set_token_action.dart';

class LogInAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    dispatch(SetTokenAction(value: 'x'));
    return state.copyWith(logIn: const LogInState());
  }
}
''');

  // Reached only from a reducer, never from a page.
  put('business/lib/redux/session/actions/set_token_action.dart', '''
class SetTokenAction extends Action {
  SetTokenAction({required this.value});
  final String value;
  @override
  AppState reduce() => state.copyWith.session(token: value);
}
''');

  // Reached only from a service dispatcher.
  put('business/lib/redux/session/actions/expire_action.dart', '''
class ExpireAction extends Action {
  @override
  AppState reduce() => state.copyWith.session(token: null);
}
''');

  // Reached by nobody at all.
  put('business/lib/redux/registration/actions/reset_form_action.dart', '''
class ResetFormAction extends Action {
  @override
  AppState reduce() => state.copyWith.registration(email: null);
}
''');

  // A service: dispatches through a held store, and imports its action with a
  // relative uri because it lives inside `business` itself.
  put('business/lib/redux/services/session/session_dispatcher.dart', '''
import '../../session/actions/expire_action.dart';

class SessionDispatcher {
  SessionDispatcher({required this.store});
  final Store<AppState> store;

  void onExpired() => store.dispatchSync(ExpireAction());
}
''');

  // Changes state without dispatching anything: it rebuilds substates from
  // storage on boot and reads them back to save.
  put('business/lib/persistor.dart', '''
class AppPersistor extends Persistor<AppState> {
  @override
  Future<AppState?> readState() async => AppState.initial().copyWith(
    session: SessionState(token: await _storage.get('token')),
    registration: const RegistrationState(),
  );

  @override
  Future<void> persistDifference({
    required AppState newState,
    AppState? lastPersistedState,
  }) async {
    if (lastPersistedState?.session != newState.session) {
      await _storage.put('token', newState.session.token);
    }
  }
}
''');

  // Not a persistor — must not be mistaken for one just by naming the type.
  put('business/lib/storage_notes.dart', '''
/// Talks about a Persistor in prose, and holds a field typed like one.
class StorageNotes {
  Persistor<AppState>? persistor;
}
''');

  // Two action classes in one file, and it is the *first* that dispatches. The
  // reader visited every `reduce()` in the unit and assigned — not appended —
  // so the last class's dispatches replaced the first's, and the cascade
  // vanished. Nothing about it involves a page or a mixin, which is why it
  // survived every test here.
  put('business/lib/redux/session/actions/refresh_action.dart', '''
import 'expire_action.dart';
import 'stamp_action.dart';

class RefreshAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatch(StampAction());
    return null;
  }
}

class _RefreshStarted extends Action {
  @override
  AppState reduce() => state;
}
''');

  put('business/lib/redux/session/actions/stamp_action.dart', '''
class StampAction extends Action {
  @override
  AppState reduce() => state.copyWith.session(token: 'stamped');
}
''');

  // Dispatched from `after()`, never from the reducer — the shape a mixin's
  // required override takes.
  put('business/lib/redux/session/actions/audit_action.dart', '''
import 'sweep_action.dart';

class AuditAction extends Action {
  @override
  AppState reduce() => state;

  @override
  void after() => dispatch(SweepAction());
}
''');

  put('business/lib/redux/session/actions/sweep_action.dart', '''
class SweepAction extends Action {
  @override
  AppState reduce() => state.copyWith.session(token: null);
}
''');

  // Dispatched from an unrouted connector — the tree `MaterialApp.builder`
  // wraps everything in. The page walk starts at `@RoutePage` connectors, so
  // nothing here was ever read for dispatches.
  put('app/lib/connectors/boot_overlay_connector.dart', '''
import 'package:business/redux/session/actions/audit_action.dart';

class _Factory extends VmFactory<AppState, BootOverlayConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() => _Vm(onDismiss: () => dispatch(AuditAction()));
}
''');

  // Dispatches, reads a selector, and is constructed by nobody — the shape the
  // orphan list used to report one action at a time.
  put('app/lib/connectors/orphan_panel_connector.dart', '''
import 'package:business/redux/registration/actions/discard_draft_action.dart';

class OrphanPanelConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    vm: () => _Factory(this),
    builder: (context, vm) => const Placeholder(),
  );
}

class _Factory extends VmFactory<AppState, OrphanPanelConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() => _Vm(onDiscard: () => dispatch(DiscardDraftAction()));
}
''');

  // Dispatched only from the connector nothing builds. It is *not* an orphan:
  // something does dispatch it. The dead thing is one level up, which is the
  // whole reason a connector needs a node.
  put('business/lib/redux/registration/actions/discard_draft_action.dart', '''
class DiscardDraftAction extends Action {
  @override
  AppState reduce() => state.copyWith.registration(email: null);
}
''');

  // Builds the root widget, and is not a connector itself — so composition
  // read through `*_connector.dart` imports cannot see it.
  put('app/lib/run_env.dart', '''
Widget runEnv(RouterConfig<Object> routerConfig) =>
    Provider(child: AppConnector(routerConfig: routerConfig));
''');

  put('app/lib/navigation/app_router.dart', '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LogInRoute.page, path: '/login', initial: true),
  ];
}
''');

  put('app/lib/connectors/log_in_page_connector.dart', '''
import 'package:business/redux/log_in/actions/log_in_action.dart';
import 'package:business/redux/log_in/actions/set_email_action.dart';
import 'package:business/redux/session/actions/refresh_action.dart';
import 'package:business/redux/session/actions/stamp_action.dart';

class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() => _Vm(
    email: FieldVm(value: logIn.email, onChanged: (v) => dispatchSync(SetEmailAction(v))),
    onPressedLogIn: () => dispatchAndWait(LogInAction()),
    onPressedMystery: () => dispatch(SomethingElse()),
  );
}

class LogInPageConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    vm: () => _Factory(this),
    // Belongs to no interaction, so to no view-model field — and a dispatch
    // read only out of `_Vm(...)` arguments is a dispatch this never was.
    onInit: (store) => store.dispatch(RefreshAction()),
    builder: (context, vm) => LogInPage(
      // The store-ful form: the action is the *second* argument, and reading
      // the first named `context` as the thing dispatched.
      onEscape: () => StoreProvider.dispatch<AppState>(context, StampAction()),
      overlay: const BootOverlayConnector(),
    ),
  );
}
''');

  // A StoreConnector no route registers — reached through MaterialApp.builder,
  // and the only reader of `session.token`. Reaches it through the `Select`
  // facade rather than the mixin, the other of the two call shapes.
  put('app/lib/app.dart', '''
class AppConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Text(context.state.select.session.token ?? '');
}
''');

  return FrxWorkspace.locate(startDir: root.path);
}

AppGraph _read() => GraphReader(_workspace()).read();

Iterable<GraphEdge> _edges(
  AppGraph g, {
  String? from,
  String? to,
  EdgeKind? kind,
}) => g.edges.where(
  (e) =>
      (from == null || e.from == from) &&
      (to == null || e.to == to) &&
      (kind == null || e.kind == kind),
);

void main() {
  group('reading a selector call', () {
    // `<substate>.<getter>` → id, plus a composite reached by a bare name.
    const index = {
      'logIn.email': 'selector:SelectLogIn.email',
      'session.token': 'selector:SelectSession.token',
      'canEnterApp': 'selector:SelectComposites.canEnterApp',
    };

    /// The selectors a statement reads, judged on its AST.
    Set<String> uses(String statement) => selectorUsesIn(
      parseString(
        content: 'class _T { void f() { $statement } }',
        throwIfDiagnostics: false,
      ).unit,
      index,
    );

    test('the mixin shape', () {
      expect(uses('FieldVm(value: logIn.email);'), {
        'selector:SelectLogIn.email',
      });
    });

    test('the facade shape, however long the receiver in front of it', () {
      for (final src in [
        'select.logIn.email;',
        'state.select.logIn.email;',
        'context.state.select.logIn.email;',
        '_store.state.select.logIn.email;',
      ]) {
        expect(uses(src), {'selector:SelectLogIn.email'}, reason: src);
      }
    });

    test('a selector deep in a chain, behind the facade', () {
      // The shape a widget uses. A pair-at-a-time text scan consumed
      // `context.state` and never saw the pair behind it.
      expect(uses('Text(context.state.select.session.token);'), {
        'selector:SelectSession.token',
      });
    });

    test('`this` is transparent', () {
      // Legal inside a class mixing in `Selectors`, and the same read as the
      // bare form — refusing it would report a live selector as dead.
      expect(uses('final a = this.logIn.email;'), {
        'selector:SelectLogIn.email',
      });
    });

    test('the state behind a selector is not the selector', () {
      // How every selector body names its own substate. Counting it would
      // report all of them as read, which is the same as reporting none.
      expect(uses('final a = _state.logIn.email;'), isEmpty);
      expect(uses('final a = state.logIn.email;'), isEmpty);
    });

    test('a field that merely shares the name is not the selector', () {
      // `vm.logIn` is a view-model field. Only a receiver that heads the chain
      // or sits behind the facade is the `Selectors` one.
      expect(uses('final a = vm.logIn.email;'), isEmpty);
      expect(uses('final a = context.session.token;'), isEmpty);
    });

    test('a mention in a comment is not a read', () {
      // Text scanning counted it, which made "something reads this" untrue in
      // the direction that hides dead code.
      expect(uses('// logIn.email\n    final a = 1;'), isEmpty);
    });

    test('a name quoted in a string is not a read', () {
      expect(uses("final a = 'logIn.email';"), isEmpty);
      expect(uses("final a = 'canEnterApp';"), isEmpty);
    });

    test('a composite is reached by a bare name', () {
      expect(uses('if (canEnterApp) go();'), {
        'selector:SelectComposites.canEnterApp',
      });
      expect(uses('if (state.select.canEnterApp) go();'), {
        'selector:SelectComposites.canEnterApp',
      });
    });

    test('a name that merely ends in the facade is not the facade', () {
      // `mySelect.` must not read as the `select.` hop.
      expect(uses('final a = mySelect.logIn.email;'), isEmpty);
    });

    test('a cascade does not run the reader out of stack', () {
      // A cascade section is a PropertyAccess with no target. Recursing on the
      // node itself instead of its receiver loops forever, and one idiomatic
      // `controller..text = ''` anywhere under app/business/ui took `graph`,
      // `doctor` and the editor's tree down with it.
      expect(uses("thing..field = 1; other..a = logIn.email;"), {
        'selector:SelectLogIn.email',
      });
    });

    test('a chain frx cannot root is not guessed at', () {
      // `of(context)` and `items[0]` are values frx cannot follow; attributing
      // the read to whatever the names happen to spell would be a guess.
      expect(uses('final a = of(context).logIn.email;'), isEmpty);
    });
  });

  group('node identity', () {
    test('qualifies an action with its substate', () {
      final g = _read();
      final ids = g.nodes
          .where((n) => n.name == 'SetEmailAction')
          .map((n) => n.id);
      // Two files, two nodes. Keyed by class name they would have collapsed
      // into one, and every edge to either would have pointed at whichever won.
      expect(
        ids,
        containsAll([
          'action:logIn.SetEmailAction',
          'action:registration.SetEmailAction',
        ]),
      );
    });

    test('a substate carries the state file worth opening', () {
      final g = _read();
      final session = g.nodes.firstWhere((n) => n.id == 'substate:session');
      // The reader's only consumer that can act on it is the editor's tree,
      // which opens this on a click — a node without it is a dead row.
      expect(session.file, endsWith('session/models/session_state.dart'));
    });

    test('a framework substate has no file of ours', () {
      final g = _read();
      // async_redux's `wait` is composed into AppState but owns no folder here;
      // pointing at one would send a click to a file that does not exist.
      final wait = g.nodes.firstWhere((n) => n.id == 'substate:wait');
      expect(wait.file, isNull);
    });

    test('a selector belongs to the substate its facade type names', () {
      final g = _read();
      final email = g.nodes.firstWhere(
        (n) => n.id == 'selector:SelectLogIn.email',
      );
      expect(email.substate, 'logIn');
    });

    test('a selector\'s owner is the facade type, not what its body reads', () {
      final g = _read();
      // `SelectLogIn.isWaiting` reads `wait`, not `logIn` — attributing by the
      // reads-edge would file it under async_redux's own substate, and a
      // composite selector reading several would land wherever it read first.
      final isWaiting = g.nodes.firstWhere(
        (n) => n.id == 'selector:SelectLogIn.isWaiting',
      );
      expect(isWaiting.substate, 'logIn');
    });

    test('the page dispatches the setter its own import resolves to', () {
      final g = _read();
      final targets = _edges(
        g,
        from: 'page:logIn',
        kind: EdgeKind.dispatches,
      ).map((e) => e.to);
      expect(targets, contains('action:logIn.SetEmailAction'));
      expect(targets, isNot(contains('action:registration.SetEmailAction')));
    });
  });

  group('edges', () {
    test('an action writes the substate its copyWith names', () {
      final g = _read();
      final e = _edges(
        g,
        from: 'action:session.SetTokenAction',
        kind: EdgeKind.writes,
      ).single;
      expect(e.to, 'substate:session');
      expect(e.via, 'session.token');
    });

    test('a service is a dispatcher, even without a page', () {
      final g = _read();
      expect(g.node('service:SessionDispatcher'), isNotNull);
      // Both halves matter: `store.dispatchSync(...)` is a targeted call, and
      // the action arrives through a relative import.
      expect(
        _edges(
          g,
          from: 'service:SessionDispatcher',
          kind: EdgeKind.dispatches,
        ).map((e) => e.to),
        ['action:session.ExpireAction'],
      );
    });

    test('an action dispatching another is an edge too', () {
      final g = _read();
      expect(
        _edges(
          g,
          from: 'action:logIn.LogInAction',
          kind: EdgeKind.dispatches,
        ).map((e) => e.to),
        ['action:session.SetTokenAction'],
      );
    });

    test('a selector waiting on an action records the reference', () {
      final g = _read();
      // `isWaitingForType<LogInAction>` is a type argument, so nothing else in
      // the graph would show that deleting the action breaks this selector.
      expect(
        _edges(g, kind: EdgeKind.waitsFor).map((e) => '${e.from}->${e.to}'),
        ['selector:SelectLogIn.isWaiting->action:logIn.LogInAction'],
      );
    });

    test('a selector reading a sibling getter inherits what it reads', () {
      final g = _read();
      // `isAvailable => token != null` touches no state itself, but `token`
      // beside it does. Left unresolved it would be a false blind spot — and a
      // list that cries wolf is the one thing that makes the real gaps invisible.
      expect(
        _edges(
          g,
          from: 'selector:SelectSession.isAvailable',
          kind: EdgeKind.reads,
        ).map((e) => e.to),
        ['substate:session'],
      );
      expect(g.unresolved.map((u) => u.kind), isNot(contains('selector-body')));
    });

    test('a field access is not mistaken for a sibling reference', () {
      final g = _read();
      // `String? get email => _state.logIn.email` — the trailing `.email` must
      // not read as the getter referring to itself.
      expect(
        _edges(
          g,
          from: 'selector:SelectLogIn.email',
          kind: EdgeKind.reads,
        ).map((e) => e.to),
        ['substate:logIn'],
      );
    });

    test('a selector reading state points at the substate', () {
      final g = _read();
      expect(
        _edges(
          g,
          from: 'selector:SelectSession.token',
          kind: EdgeKind.reads,
        ).map((e) => e.to),
        ['substate:session'],
      );
    });
  });

  group('the persistor', () {
    test('restores every substate its readState rebuilds', () {
      final g = _read();
      // Not just the first named argument: `copyWith(session:, registration:)`
      // puts both back, and reporting one would understate what boot changes.
      expect(
        _edges(
          g,
          from: 'persistor:AppPersistor',
          kind: EdgeKind.restores,
        ).map((e) => e.to).toList()..sort(),
        ['substate:registration', 'substate:session'],
      );
    });

    test('is a writer of state, alongside the actions', () {
      final g = _read();
      // The question the graph exists to answer. Following dispatches alone
      // would name only the action and sound complete.
      expect(
        _edges(g, to: 'substate:session')
            .where((e) => e.kind != EdgeKind.reads)
            .map((e) => '${e.kind.name} ${e.from}')
            .toList()
          ..sort(),
        [
          'restores persistor:AppPersistor',
          'writes action:session.ExpireAction',
          'writes action:session.SetTokenAction',
          'writes action:session.StampAction',
          'writes action:session.SweepAction',
        ],
      );
    });

    test('reads what persistDifference compares', () {
      final g = _read();
      expect(
        _edges(
          g,
          from: 'persistor:AppPersistor',
          kind: EdgeKind.reads,
        ).map((e) => e.to),
        ['substate:session'],
      );
    });

    test('a class that merely mentions Persistor is not one', () {
      final g = _read();
      expect(
        g.nodes.where((n) => n.kind == NodeKind.persistor).map((n) => n.name),
        ['AppPersistor'],
      );
    });
  });

  group('blind spots', () {
    test('an unreadable dispatch target is reported, not dropped', () {
      final g = _read();
      final node = g.node('action:SomethingElse');
      expect(node, isNotNull, reason: 'the edge must still have a target');
      expect(node!.resolved, isFalse);
      expect(
        g.unresolved.map((u) => u.expr),
        contains('SomethingElse'),
        reason: 'silently missing is the one failure a reader cannot detect',
      );
    });

    test('only actions nothing dispatches are orphans', () {
      final g = _read();
      // The registration twin is dead while the logIn one is live — the whole
      // point of qualifying ids. Keyed by class name this pair would have been
      // one node, reachable, and the dead file would never have surfaced.
      expect(
        g.orphans
            .where((o) => o.node.kind == NodeKind.action)
            .map((o) => o.node.id)
            .toList()
          ..sort(),
        [
          'action:registration.ResetFormAction',
          'action:registration.SetEmailAction',
        ],
      );
    });

    test('an action reached only from onInit is not an orphan', () {
      // `onInit:` is a `StoreConnector` argument, not a `_Vm(...)` one, so the
      // page walk counted it in `PageFlow.untraced` and drew no edge. The
      // orphan list is the one place frx says "you can delete this", and it
      // named an action the connector dispatches on open.
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.RefreshAction')),
      );
    });

    test('an action reached only from an unrouted connector is not an '
        'orphan', () {
      // The same file class `NodeKind.consumer` was invented for, and which
      // the selector half of this reader already sweeps for reads.
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.AuditAction')),
      );
    });

    test('an action reached only through StoreProvider.dispatch is not an '
        'orphan', () {
      // Recognised as a dispatch all along; it was the *target* that was read
      // off argument zero, which is the `BuildContext`.
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.StampAction')),
      );
    });

    test('an action reached only from after() is not an orphan', () {
      // Dispatches were read from `reduce()` alone, so a cascade out of any
      // other member — `before`, `after`, a method a mixin requires — was
      // invisible.
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.SweepAction')),
      );
    });

    test('a second action class in a file does not erase the first\'s '
        'dispatches', () {
      // Assignment, not accumulation: every `reduce()` in the unit was visited
      // and the last one won. Measured on a real project, this alone accounted
      // for two of the reported orphans.
      final g = _read();
      expect(
        _edges(g, from: 'action:session.RefreshAction').map((e) => e.to),
        contains('action:session.StampAction'),
      );
    });

    test('a connector no file constructs is reported, with its own reason', () {
      // The verdict the orphan list could not reach. On a real project six of
      // eleven reported orphan actions were dispatched only from a connector
      // nothing builds: the answer "nothing reaches these six" was right and
      // the reason — one dead connector, not six dead actions — was missing.
      final g = _read();
      expect(
        g.orphans
            .where((o) => o.node.kind == NodeKind.consumer)
            .map((o) => '${o.node.id} ${o.why}'),
        ['consumer:OrphanPanelConnector no file constructs it'],
      );
    });

    test('a connector a page builds is not reported', () {
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('consumer:BootOverlayConnector')),
      );
    });

    test('a connector built from a file that is not itself one is not '
        'reported', () {
      // `AppConnector` lives in `app.dart` and is constructed in `run_env.dart`
      // — neither file is named `*_connector.dart`. Resolving composition
      // through that import pattern, which is what the page walk does, called
      // the app's own root widget unbuilt.
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('consumer:AppConnector')),
      );
    });

    test('an action reached only from a reducer is not an orphan', () {
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.SetTokenAction')),
      );
    });

    test('an action reached only from a service is not an orphan', () {
      final g = _read();
      expect(
        g.orphans.map((o) => o.node.id),
        isNot(contains('action:session.ExpireAction')),
      );
    });

    test('a selector a connector reads is not dead', () {
      final g = _read();
      expect(
        g.deadSelectors.map((o) => o.node.id),
        isNot(contains('selector:SelectLogIn.email')),
      );
    });

    test('a selector nothing reads is dead', () {
      final g = _read();
      final dead = g.deadSelectors.singleWhere(
        (o) => o.node.id == 'selector:SelectLogIn.password',
      );
      expect(dead.why, 'nothing reads it');
    });

    test('reading the state behind a selector is not reading the selector', () {
      final g = _read();
      // `SelectLogIn.password` is spelled `_state.logIn.password` inside the
      // facade. Counting that would report every selector as read — each one
      // names its own substate in its body.
      expect(
        _edges(g, to: 'selector:SelectLogIn.password', kind: EdgeKind.uses),
        isEmpty,
      );
    });

    test('a getter reading its own sibling reads it', () {
      // `bool get isAvailable => token != null;` inside `SelectSession`. Bare,
      // because a sibling on the same type needs no facade hop in front of it —
      // and so not a call shape the facade-keyed index can match. Counting it is
      // what stops `token` reading as touched by nobody.
      expect(
        _edges(
          _read(),
          from: 'selector:SelectSession.isAvailable',
          to: 'selector:SelectSession.token',
          kind: EdgeKind.uses,
        ),
        isNotEmpty,
      );
    });

    test('a chain read only by a dead composite is dead too', () {
      final g = _read();
      final dead = {for (final o in g.deadSelectors) o.node.id: o.why};
      // Nothing reads `canEnterApp`, so the two selectors only it reads are
      // dead as well — in-degree alone would call them healthy.
      expect(dead['selector:SelectComposites.canEnterApp'], 'nothing reads it');
      expect(
        dead['selector:SelectSession.isAvailable'],
        'read only by selectors nothing reads',
      );
      expect(
        dead['selector:SelectLogIn.isWaiting'],
        'read only by selectors nothing reads',
      );
    });

    test('a reader with no node of its own still keeps a selector alive', () {
      final g = _read();
      // `AppConnector` is a StoreConnector no route registers. Scanning only
      // the files that already have a node would report `session.token` as
      // dead — the one mistake here that costs working code.
      expect(
        g.deadSelectors.map((o) => o.node.id),
        isNot(contains('selector:SelectSession.token')),
      );
      expect(
        _edges(
          g,
          to: 'selector:SelectSession.token',
          kind: EdgeKind.uses,
        ).map((e) => e.from),
        contains('consumer:AppConnector'),
      );
    });
  });

  group('focus', () {
    test('keeps the neighbourhood and drops the rest', () {
      final g = _read().focusOn('substate:session', depth: 1);
      expect(
        g.nodes.map((n) => n.id),
        containsAll([
          'substate:session',
          'action:session.SetTokenAction',
          'selector:SelectSession.token',
        ]),
      );
      expect(
        g.nodes.map((n) => n.id),
        isNot(contains('substate:registration')),
      );
    });

    test('another hop reaches the dispatchers', () {
      final g = _read().focusOn('substate:session', depth: 2);
      expect(
        g.nodes.map((n) => n.id),
        containsAll(['action:logIn.LogInAction', 'service:SessionDispatcher']),
      );
    });

    test('the blind spots are scoped to the subgraph', () {
      final whole = _read();
      final focused = whole.focusOn('substate:session', depth: 1);
      // Kept whole, a gap belonging to an unrelated page was reported against
      // whatever you focused — which misattributes it, and misattribution is
      // worse than silence from a list whose only job is to say where the
      // answer is incomplete.
      expect(whole.unresolved, isNotEmpty);
      expect(
        focused.unresolved.length,
        lessThan(whole.unresolved.length),
        reason: 'the whole project\'s gaps are not this subgraph\'s',
      );
      for (final u in focused.unresolved) {
        expect(focused.nodes.map((n) => n.id), contains(u.owner));
      }
    });

    test('every gap is attributed to a node that exists', () {
      // The `owner` field is what makes scoping possible; an unattributable gap
      // would silently vanish from every focused read.
      final whole = _read();
      final ids = whole.nodes.map((n) => n.id).toSet();
      for (final u in whole.unresolved) {
        expect(ids, contains(u.owner), reason: '${u.kind} ${u.expr}');
      }
    });
  });

  group('direction', () {
    test('an undirected walk joins unrelated substates through the hub', () {
      // Not a bug being pinned — the behaviour `both` has always had, and the
      // reason `inbound` had to exist. The persistor touches every substate, so
      // a walk that turns around inside it comes back out somewhere else.
      final g = _read().focusOn('substate:session', depth: 2);
      expect(g.nodes.map((n) => n.id), contains('persistor:AppPersistor'));
      expect(g.nodes.map((n) => n.id), contains('substate:registration'));
    });

    test('an inbound walk stops at the hub instead of passing through', () {
      final g = _read().focusOn(
        'substate:session',
        depth: null,
        direction: GraphDirection.inbound,
      );
      expect(
        g.nodes.map((n) => n.id),
        contains('persistor:AppPersistor'),
        reason: 'the persistor does write session — it belongs in the answer',
      );
      expect(
        g.nodes.map((n) => n.id),
        isNot(contains('substate:registration')),
        reason: 'nothing about registration depends on session',
      );
    });

    test('inbound reaches the whole chain that would break', () {
      // The question the direction exists for: changing the session token
      // reaches a selector, then the composite that reads it.
      final g = _read().focusOn(
        'substate:session',
        depth: null,
        direction: GraphDirection.inbound,
      );
      expect(
        g.nodes.map((n) => n.id),
        containsAll([
          'selector:SelectSession.token',
          'selector:SelectSession.isAvailable',
          'selector:SelectComposites.canEnterApp',
        ]),
      );
    });

    test('outbound follows only what the node reaches', () {
      final g = _read().focusOn(
        'selector:SelectComposites.canEnterApp',
        depth: null,
        direction: GraphDirection.outbound,
      );
      expect(
        g.nodes.map((n) => n.id),
        contains('selector:SelectSession.isAvailable'),
      );
      expect(
        g.nodes.map((n) => n.id),
        isNot(contains('consumer:AppConnector')),
        reason: 'a reader of it is not something it reaches',
      );
    });

    test('a bound that cut the walk short says so', () {
      final short = _read().focusOn('substate:session', depth: 1);
      expect(short.focus!.truncated, isTrue);
      expect(short.focus!.depth, 1);

      final whole = _read().focusOn('substate:session', depth: null);
      expect(
        whole.focus!.truncated,
        isFalse,
        reason: 'an unbounded walk cannot have been cut short',
      );
      expect(whole.focus!.depth, isNull);
    });

    test('the focus is described in the json, bound and all', () {
      final json = _read()
          .focusOn(
            'substate:session',
            depth: 2,
            direction: GraphDirection.inbound,
          )
          .toJson();
      expect(json['focus'], {
        'node': 'substate:session',
        'direction': 'inbound',
        'depth': 2,
        'truncated': isA<bool>(),
      });
    });

    test('an unfocused graph describes no focus', () {
      expect(_read().toJson().keys, isNot(contains('focus')));
    });
  });

  test('the json form round-trips every section', () {
    final json = _read().toJson();
    expect(json.keys, containsAll(['nodes', 'edges', 'unresolved', 'orphans']));
    expect(json['nodes'], isNotEmpty);
    expect(json['orphans'], isNotEmpty);
  });

  group('a composite declared on a substate selector', () {
    // The reader used to match a composite only as `on Select` or `on Selector`
    // exactly, so `extension … on SelectLogIn` was invisible: no node, and — the
    // part that costs working code — its reads did not count, so a selector only
    // it read was reported as read by nobody.
    AppGraph read() {
      final root = Directory.systemTemp.createTempSync('frx_graph_ext_');
      addTearDown(() => root.deleteSync(recursive: true));
      void put(String rel, String content) {
        File(p.join(root.path, rel))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      put('business/lib/redux/app_state.dart', '''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required LogInState logIn,
    required Wait wait,
  }) = _AppState;
}
''');
      put('business/lib/redux/selectors.dart', '''
extension type SelectLogIn(AppState _state) implements Selector {
  String? get email => _state.logIn.email;
  String? get password => _state.logIn.password;
}

extension SelectLogInExtras on SelectLogIn {
  bool get canSubmit => email != null && password != null;
}
''');
      put('app/lib/navigation/app_router.dart', '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LogInRoute.page, path: '/login', initial: true),
  ];
}
''');
      put('app/lib/connectors/log_in_page_connector.dart', '''
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() => _Vm(canSubmit: logIn.canSubmit);
}
''');
      return GraphReader(FrxWorkspace.locate(startDir: root.path)).read();
    }

    test('is a node of its own', () {
      expect(read().node('selector:SelectLogInExtras.canSubmit'), isNotNull);
    });

    test('belongs to the substate it extends, not to its own name', () {
      // `SelectLogInExtras` would read as a substate called `logInExtras`. What
      // decides is the type it extends, because that is what its getters are
      // reached through.
      expect(
        read().node('selector:SelectLogInExtras.canSubmit')!.substate,
        'logIn',
      );
    });

    test('its reads keep the selectors it reads alive', () {
      final dead = {for (final o in read().deadSelectors) o.node.id};
      expect(dead, isNot(contains('selector:SelectLogIn.email')));
      expect(dead, isNot(contains('selector:SelectLogIn.password')));
    });

    test('is reached through the substate it extends', () {
      // `select.logIn.canSubmit`, not `select.canSubmit` — the connector reads
      // it that way, and nothing else in this workspace reads it.
      final dead = {for (final o in read().deadSelectors) o.node.id};
      expect(dead, isNot(contains('selector:SelectLogInExtras.canSubmit')));
    });
  });

  group('a selector declared outside the facade', () {
    // The graph read declarations from `selectors.dart` and nothing else, while
    // the placement rules sweep all three lib trees for them — so a hand-written
    // selector elsewhere was reported by `doctor` and absent here. Absent is the
    // direction that costs working code: what it reads counts as read by nobody,
    // and the dead-selector list is the one place frx says "you can delete this".
    AppGraph read({required bool stray}) {
      final root = Directory.systemTemp.createTempSync('frx_graph_stray_');
      addTearDown(() => root.deleteSync(recursive: true));
      void put(String rel, String content) {
        File(p.join(root.path, rel))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      put('business/lib/redux/app_state.dart', '''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required LogInState logIn,
    required Wait wait,
  }) = _AppState;
}
''');
      put('business/lib/redux/selectors.dart', '''
extension type SelectLogIn(AppState _state) implements Selector {
  String? get email => _state.logIn.email;
}
''');
      put('app/lib/navigation/app_router.dart', '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [];
}
''');
      if (stray) {
        put('business/lib/redux/log_in/stray_selectors.dart', '''
extension type SelectStray(AppState _state) implements Selector {
  String? get email => _state.logIn.email;
}
''');
      }
      return GraphReader(FrxWorkspace.locate(startDir: root.path)).read();
    }

    test('is declared as a blind spot, naming the file', () {
      final gaps = read(
        stray: true,
      ).unresolved.where((u) => u.kind == 'misplaced-selector');
      expect(gaps, hasLength(1));
      expect(gaps.single.why, contains('stray_selectors.dart'));
    });

    test('is not a node, and draws no edge', () {
      // A graph that drew it would make the misplacement look like ordinary
      // wiring — the opposite of what the audit is for.
      final g = read(stray: true);
      expect(g.nodes.where((n) => n.name.contains('Stray')), isEmpty);
      expect(
        g.edges.where((e) => '\${e.from}\${e.to}'.contains('Stray')),
        isEmpty,
      );
    });

    test('a workspace without one gains no entry', () {
      expect(
        read(
          stray: false,
        ).unresolved.where((u) => u.kind == 'misplaced-selector'),
        isEmpty,
      );
    });
  });

  group('reading each file once', () {
    // The property the source index exists for. Before it, one `frx graph` run
    // parsed an action file four times — to learn its class name, to read it,
    // to read it again with its imports, and once more in the consumer sweep —
    // and walked business/lib twice over.
    //
    // Asserted per file, not on the total: a reader that regressed to parsing a
    // file itself would make the *total* go down, so only the per-file count
    // can say "once".
    test('every file a graph read touches is parsed once', () {
      final ix = SourceIndex();
      final ws = _workspace();
      withSourceIndex(ix, () => GraphReader(ws).read());

      final touched = [
        for (final dir in [
          ws.businessLib,
          ws.uiLib,
          Directory(p.join(ws.root.path, 'app', 'lib')),
        ])
          for (final f in ix.filesUnder(dir))
            if (ix.parsesOf(f) > 0) f,
      ];
      expect(touched, isNotEmpty);
      expect({for (final f in touched) ix.parsesOf(f)}, {1});
    });

    test('the action files in particular, which used to cost four each', () {
      final ix = SourceIndex();
      final ws = _workspace();
      withSourceIndex(ix, () => GraphReader(ws).read());

      final actions = ix
          .filesUnder(ws.businessLib)
          .where((f) => f.path.endsWith('_action.dart'))
          .toList();
      expect(actions, hasLength(11));
      for (final f in actions) {
        expect(ix.parsesOf(f), 1, reason: p.basename(f.path));
      }
    });

    test('the router is parsed once per route-map read, not twice', () {
      // `readAuthArea()` and `readRoutes()` each re-read and re-parsed it.
      final ix = SourceIndex();
      final ws = _workspace();
      withSourceIndex(ix, () => RouteMapReader(ws).read());
      final router = File(
        p.join(ws.root.path, 'app', 'lib', 'navigation', 'app_router.dart'),
      );
      expect(ix.parsesOf(router), 1);
    });

    test('a read that runs inside another shares its snapshot', () {
      // A graph read runs a route-map read inside it. Two scopes would mean two
      // parses of the router and two walks of the same trees.
      final ix = SourceIndex();
      final ws = _workspace();
      withSourceIndex(ix, () => GraphReader(ws).read());
      expect(
        ix.parsesOf(
          File(
            p.join(ws.root.path, 'app', 'lib', 'navigation', 'app_router.dart'),
          ),
        ),
        1,
      );
    });
  });

  group('a selector body is code, not text', () {
    // Three regexes over `body.toSource()` derived what a getter touched, and
    // text cannot tell a string literal from code. Reproduced with the product's
    // own commands: `frx add-selector session label -t String -e "'token'"` on a
    // fresh project made the graph report `label` — whose whole body is the
    // *string* `'token'` — as reading the session slice, because the bare-name
    // scrape matched inside the quotes and the sibling fold handed it the
    // neighbouring getter's reads.
    AppGraph read() {
      final root = Directory.systemTemp.createTempSync('frx_graph_text_');
      addTearDown(() => root.deleteSync(recursive: true));
      void put(String rel, String content) {
        File(p.join(root.path, rel))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      put('business/lib/redux/app_state.dart', '''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required SessionState session,
    required Wait wait,
  }) = _AppState;
}
''');
      put('business/lib/redux/selectors.dart', '''
mixin Selectors {
  AppState get state;
  SelectSession get session => SelectSession(state);
}

extension SelectComposites on Selectors {
  bool get isBusy => state.wait.isWaitingAny;
}

extension type SelectSession(AppState _state) {
  String? get token => _state.session.token;

  /// The body is the string 'token' — not the getter declared beside it.
  String get label => 'token';
}
''');
      put('app/lib/navigation/app_router.dart', '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [];
}
''');
      return GraphReader(FrxWorkspace.locate(startDir: root.path)).read();
    }

    test('a getter quoting a sibling reads nothing', () {
      expect(
        read().edges.where((e) => e.from == 'selector:SelectSession.label'),
        isEmpty,
      );
    });

    test('the getter it quotes still reads its own slice', () {
      // The other direction, so the fix cannot be "stop resolving anything":
      // `token` genuinely reads `_state.session`.
      expect(
        read().edges.any(
          (e) =>
              e.from == 'selector:SelectSession.token' &&
              e.to == 'substate:session',
        ),
        isTrue,
      );
    });

    test('a composite reaches state through `state`, not only `_state`', () {
      // `extension SelectComposites on Selectors` has no `_state` to reach — it
      // has the mixin's `state` getter. A pattern keyed on the extension-type
      // spelling made every composite that reads state directly a blind spot,
      // which `reality_test` caught the moment one was written.
      expect(
        read().edges.any(
          (e) =>
              e.from == 'selector:SelectComposites.isBusy' &&
              e.to == 'substate:wait',
        ),
        isTrue,
      );
    });
  });
}
