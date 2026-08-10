import 'dart:io';

import 'package:tools/src/flow/flow_model.dart';
import 'package:tools/src/flow/flow_reader.dart';
import 'package:tools/src/flow/mermaid.dart';
import 'package:tools/src/workspace/frx_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A minimal workspace holding one realistic connector + the action it reaches.
({Directory root, File connector}) _workspace() {
  final root = Directory.systemTemp.createTempSync('frx_flow_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) {
    final f = File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    expect(f.existsSync(), isTrue);
  }

  // The marker FrxWorkspace.locate() looks for.
  put('app/lib/navigation/app_router.dart', '// router\n');

  put('business/lib/redux/registration/actions/registration_action.dart', '''
class RegistrationAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _signUp();
    return state.copyWith(registration: const RegistrationState());
  }
}

Future<void> _signUp() async {
  throw const UserException('nope');
}
''');

  // The deep `copyWith.<substate>()` form — what frx's own setter templates
  // emit, so it is the shape most actions in a generated repo have.
  put('business/lib/redux/registration/actions/set_email_action.dart', '''
class SetEmailAction extends Action {
  SetEmailAction(this.value);
  final String? value;
  @override
  AppState reduce() => state.copyWith.registration(email: value);
}
''');

  put('app/lib/connectors/registration_page_connector.dart', '''
import 'package:business/redux/registration/actions/registration_action.dart';
import 'package:business/redux/registration/actions/set_email_action.dart';

@RoutePage()
class RegistrationPageConnector extends StatelessWidget {}

class _Factory extends VmFactory<AppState, RegistrationPageConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() {
    return _Vm(
      email: FieldVm(
        value: registration.email,
        onChanged: (v) => dispatchSync(SetEmailAction(v)),
      ),
      onPressedRegister: () async {
        final status = await dispatchAndWait(RegistrationAction());
        if (status.isCompletedOk) {
          dispatch(GoAction.pop());
        }
      },
      onPressedLogin: () => dispatch(GoAction.push(const LogInRoute())),
      title: 'not a callback',
    );
  }
}
''');

  return (
    root: root,
    connector: File(
      p.join(root.path, 'app/lib/connectors/registration_page_connector.dart'),
    ),
  );
}

PageFlow _read() {
  final ws = _workspace();
  return FlowReader(FrxWorkspace.locate(startDir: ws.root.path)).read(
    connectorFile: ws.connector,
    page: 'registration',
    connectorClass: 'RegistrationPageConnector',
    pageClass: 'RegistrationPage',
  );
}

/// A page connector that holds no view-model at all, handing each slot to a
/// region connector — the shape a screen takes once its view-model has been
/// split. `frame` builds two regions; one of them takes a third as its own slot.
({Directory root, File connector}) _composed() {
  final root = Directory.systemTemp.createTempSync('frx_regions_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) => File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  put('app/lib/navigation/app_router.dart', '// router\n');

  put('business/lib/redux/console/actions/set_view_action.dart', '''
class SetViewAction extends Action {
  SetViewAction(this.value);
  final String value;
  @override
  AppState reduce() => state.copyWith.console(view: value);
}
''');
  put('business/lib/redux/console/actions/pick_project_action.dart', '''
class PickProjectAction extends Action {
  PickProjectAction(this.id);
  final String id;
  @override
  AppState reduce() => state.copyWith.console(projectId: id);
}
''');

  put('business/lib/redux/console/actions/open_task_action.dart', '''
class OpenTaskAction extends Action {
  OpenTaskAction(this.id);
  final String id;
  @override
  AppState reduce() => state.copyWith.console(openTaskId: id);
}
''');

  put('business/lib/redux/console/actions/reject_task_action.dart', '''
class RejectTaskAction extends Action {
  RejectTaskAction(this.id);
  final String id;
  @override
  AppState reduce() => state.copyWith.console(rejectedId: id);
}
''');

  // The frame: no StoreConnector, no _Vm — just four slots.
  put('app/lib/connectors/console_page_connector.dart', '''
import 'package:ui/pages/console_page.dart';

import 'console_sidebar_connector.dart';
import 'console_content_connector.dart';
import 'task_drawer_connector.dart';
import 'human_queue_connector.dart';

@RoutePage()
class ConsolePageConnector extends StatelessWidget {
  const ConsolePageConnector({super.key});

  @override
  Widget build(BuildContext context) => const ConsolePage(
    sidebar: ConsoleSidebarConnector(),
    content: ConsoleContentConnector(),
    drawer: TaskDrawerConnector(),
    queue: HumanQueueConnector(),
  );
}
''');

  // A region whose rows are built by a helper on the factory.
  //
  // Not an exotic shape: it is what you reach for the moment a list row needs a
  // callback, which is roughly the second thing that happens to a connector
  // after `add-connector` writes it. The dispatch is two hops from the `_Vm`
  // argument — through `_item`, then through the `onTap` closure it returns.
  put('app/lib/connectors/task_drawer_connector.dart', '''
import 'package:business/redux/console/actions/open_task_action.dart';

class TaskDrawerConnector extends StatelessWidget {
  const TaskDrawerConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => TaskDrawer(view: vm.view),
  );
}

class _Factory extends VmFactory<AppState, TaskDrawerConnector, _Vm>
    with Selectors {
  ItemVm _item(TaskView task, int rank) => ItemVm(
    id: task.id.value,
    rank: rank,
    onTap: () => dispatch(OpenTaskAction(task.id.value)),
  );

  @override
  _Vm fromStore() => _Vm(
    view: ViewVm(tasks: [for (final (i, t) in rows.indexed) _item(t, i + 1)]),
  );
}
''');

  // A region that dispatches, and takes a region of its own as a slot.
  put('app/lib/connectors/console_sidebar_connector.dart', '''
import 'package:business/redux/console/actions/set_view_action.dart';

import 'project_selector_connector.dart';

class ConsoleSidebarConnector extends StatelessWidget {
  const ConsoleSidebarConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => ConsoleSidebar(
      projectSelector: const ProjectSelectorConnector(),
      onSelect: vm.onSelectView,
    ),
  );
}

class _Factory extends VmFactory<AppState, ConsoleSidebarConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() =>
      _Vm(onSelectView: (v) => dispatch(SetViewAction(v)));
}
''');

  put('app/lib/connectors/project_selector_connector.dart', '''
import 'package:business/redux/console/actions/pick_project_action.dart';

class ProjectSelectorConnector extends StatelessWidget {
  const ProjectSelectorConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => ProjectSelector(onPick: vm.onPick),
  );
}

class _Factory extends VmFactory<AppState, ProjectSelectorConnector, _Vm>
    with Selectors {
  @override
  _Vm fromStore() => _Vm(onPick: (id) => dispatch(PickProjectAction(id)));
}
''');

  // Reached through a `switch`, the way a content region picks one of N views.
  put('app/lib/connectors/console_content_connector.dart', '''
import 'event_log_connector.dart';

class ConsoleContentConnector extends StatelessWidget {
  const ConsoleContentConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => ConsoleContent(
      child: switch (vm.view) {
        ConsoleView.log => const EventLogConnector(),
      },
    ),
  );
}
''');

  // A region the reader still cannot follow: the callback is held in a *field*
  // of the factory, and the name table only carries functions. Kept in the
  // fixture on purpose — it is the case the report exists for, and if a later
  // change teaches the walk to follow fields, the test below fails and says so
  // rather than the report quietly having nothing left to describe.
  put('app/lib/connectors/human_queue_connector.dart', '''
import 'package:business/redux/console/actions/reject_task_action.dart';

class HumanQueueConnector extends StatelessWidget {
  const HumanQueueConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => HumanQueue(onReject: vm.onReject),
  );
}

class _Factory extends VmFactory<AppState, HumanQueueConnector, _Vm>
    with Selectors {
  late final _reject = (String id) => dispatch(RejectTaskAction(id));

  @override
  _Vm fromStore() => _Vm(onReject: _reject);
}
''');

  // A region that draws state and dispatches nothing.
  put('app/lib/connectors/event_log_connector.dart', '''
class EventLogConnector extends StatelessWidget {
  const EventLogConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => EventLog(lines: vm.lines),
  );
}
''');

  return (
    root: root,
    connector: File(
      p.join(root.path, 'app/lib/connectors/console_page_connector.dart'),
    ),
  );
}

/// A connector where three ordinary names collide with three dispatching
/// methods: a local variable, the left-hand side of a `.`, and a parameter.
///
/// All three are legal Dart that means something else entirely, and all three
/// were read as calls to the method.
({Directory root, File connector}) _shadowed() {
  final root = Directory.systemTemp.createTempSync('frx_shadow_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) => File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  put('app/lib/navigation/app_router.dart', '// router\n');

  put('business/lib/redux/console/actions/reset_action.dart', '''
class ResetAction extends Action {
  @override
  AppState reduce() => state.copyWith.console(view: '');
}
''');

  put('app/lib/connectors/shadowed_connector.dart', '''
import 'package:business/redux/console/actions/reset_action.dart';

@RoutePage()
class ShadowedConnector extends StatelessWidget {
  const ShadowedConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => Shadowed(vm: vm),
  );
}

class _Factory extends VmFactory<AppState, ShadowedConnector, _Vm>
    with Selectors {
  void reset() => dispatch(ResetAction());
  void session() => dispatch(ResetAction());
  void refresh() => dispatch(ResetAction());
  void pair() => dispatch(ResetAction());
  void matched() => dispatch(ResetAction());
  void arm() => dispatch(ResetAction());

  String _row(String refresh) => refresh;

  @override
  _Vm fromStore() {
    final reset = 'Reset';
    final (pair, _) = ('Pair', 0);
    final label = state.console.label;
    return _Vm(
      caption: reset,
      user: session.userName,
      row: _row('now'),
      destructured: pair,
      // The pattern variables are read *inside* the argument, which is the
      // subtree the walk actually visits — bound in a `switch` arm and behind a
      // `when` guard, and both spelled like a method that dispatches.
      armed: switch (label) {
        String arm => arm,
        _ => '',
      },
      guarded: switch (label) {
        String matched when matched.isNotEmpty => matched,
        _ => '',
      },
    );
  }
}
''');

  return (
    root: root,
    connector: File(
      p.join(root.path, 'app/lib/connectors/shadowed_connector.dart'),
    ),
  );
}

/// One helper answering for two `_Vm` fields, beside a dispatch nothing
/// reaches — the pair that made counting go wrong.
({Directory root, File connector}) _sharedHelper() {
  final root = Directory.systemTemp.createTempSync('frx_shared_');
  addTearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) => File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  put('app/lib/navigation/app_router.dart', '// router\n');
  put('business/lib/redux/console/actions/a_action.dart', '''
class AAction extends Action {
  @override
  AppState reduce() => state.copyWith.console(a: 1);
}
''');
  put('business/lib/redux/console/actions/b_action.dart', '''
class BAction extends Action {
  @override
  AppState reduce() => state.copyWith.console(b: 1);
}
''');

  put('app/lib/connectors/shared_connector.dart', '''
import 'package:business/redux/console/actions/a_action.dart';
import 'package:business/redux/console/actions/b_action.dart';

@RoutePage()
class SharedConnector extends StatelessWidget {
  const SharedConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    builder: (context, vm) => Shared(vm: vm),
  );
}

class _Factory extends VmFactory<AppState, SharedConnector, _Vm>
    with Selectors {
  VoidCallback _open() => () => dispatch(AAction());

  late final _hidden = () => dispatch(BAction());

  @override
  _Vm fromStore() => _Vm(
    onPrimary: _open(),
    onSecondary: _open(),
    onHidden: _hidden,
  );
}
''');

  return (
    root: root,
    connector: File(
      p.join(root.path, 'app/lib/connectors/shared_connector.dart'),
    ),
  );
}

PageFlow _readShared() {
  final ws = _sharedHelper();
  return FlowReader(FrxWorkspace.locate(startDir: ws.root.path)).read(
    connectorFile: ws.connector,
    page: 'shared',
    connectorClass: 'SharedConnector',
    pageClass: 'Shared',
  );
}

PageFlow _readShadowed() {
  final ws = _shadowed();
  return FlowReader(FrxWorkspace.locate(startDir: ws.root.path)).read(
    connectorFile: ws.connector,
    page: 'shadowed',
    connectorClass: 'ShadowedConnector',
    pageClass: 'Shadowed',
  );
}

PageFlow _readComposed() {
  final ws = _composed();
  return FlowReader(FrxWorkspace.locate(startDir: ws.root.path)).read(
    connectorFile: ws.connector,
    page: 'console',
    connectorClass: 'ConsolePageConnector',
    pageClass: 'ConsolePage',
  );
}

void main() {
  group('a page composed of regions', () {
    test('finds the callbacks the frame does not hold', () {
      final flow = _readComposed();

      expect(
        flow.isEmpty,
        isFalse,
        reason:
            'the frame holds no _Vm, which used to read as "this page '
            'dispatches nothing" rather than "look in the regions"',
      );
      expect(
        flow.useCases.map((u) => u.name),
        ['onSelectView', 'onPick', 'view'],
        reason: 'depth-first, in the order the slots are written',
      );
    });

    test('says which region each one belongs to', () {
      final flow = _readComposed();
      expect(
        {for (final u in flow.useCases) u.name: u.owner},
        {
          'onSelectView': 'ConsoleSidebarConnector',
          'onPick': 'ProjectSelectorConnector',
          'view': 'TaskDrawerConnector',
        },
      );
    });

    test('follows a region reached through a switch, and one nested twice', () {
      final flow = _readComposed();
      expect(
        flow.regions,
        [
          'ConsoleSidebarConnector',
          'ProjectSelectorConnector',
          'ConsoleContentConnector',
          'EventLogConnector',
          'TaskDrawerConnector',
          'HumanQueueConnector',
        ],
        reason:
            'EventLogConnector is only reachable through a switch expression '
            'inside another region, and dispatches nothing itself',
      );
    });

    test('reads the actions through each region\'s own imports', () {
      final flow = _readComposed();
      expect(
        flow.actions.keys,
        containsAll(['SetViewAction', 'PickProjectAction']),
      );
      expect(flow.actions['SetViewAction']!.writesLabel, 'console.view');
      expect(
        flow.actions['PickProjectAction']!.writesLabel,
        'console.projectId',
      );
    });

    test('gives every dispatching region a lane of its own', () {
      final out = renderSequence(_readComposed());

      expect(out, contains('participant R1 as ConsoleSidebarConnector'));
      expect(out, contains('participant R2 as ProjectSelectorConnector'));
      expect(
        out,
        isNot(contains('as ConsolePageConnector')),
        reason:
            'the frame holds no view-model — its lane would be an empty column '
            'captioned with the one class in the drawing that does nothing',
      );
      expect(out, contains('UI->>R1: onSelectView()'));
      expect(out, contains('UI->>R2: onPick()'));
    });

    test('names the region above the lane, not only in it', () {
      // Eight regions with an `onOpen` each rendered eight identical user
      // lines, told apart only by which lane the next arrow landed in.
      final out = renderSequence(_readComposed());

      expect(out, contains('User->>UI: ConsoleSidebar ▸ onSelectView'));
      expect(out, contains('User->>UI: ProjectSelector ▸ onPick'));
    });

    test('a region that dispatches nothing gets no lane', () {
      final out = renderSequence(_readComposed());
      expect(out, isNot(contains('EventLogConnector')));
    });

    test('follows a dispatch built by a helper on the factory', () {
      // The walk used to run only the subtree of the `_Vm(...)` named argument,
      // so a callback assembled in a method of the same factory was outside it
      // and the region reported no interactions at all. Nothing said so: a
      // region with no use case gets no lane, and a map missing six of eleven
      // regions reads exactly like a map of a page that has five.
      final flow = _readComposed();

      final drawer = flow.useCases.where(
        (u) => u.owner == 'TaskDrawerConnector',
      );
      expect(
        drawer,
        isNotEmpty,
        reason: 'the dispatch sits in `_item`, two hops from the _Vm argument',
      );
      expect(drawer.single.steps.single.target, 'OpenTaskAction');
      expect(
        drawer.single.steps.single.trigger,
        'onTap',
        reason: 'the trigger is read inside the helper, where the closure is',
      );
    });

    test('the helper-built region gets a lane like any other', () {
      final out = renderSequence(_readComposed());
      expect(out, contains('as TaskDrawerConnector'));
      expect(out, contains('OpenTaskAction'));
    });

    test('a dispatch the walk could not reach is reported, not dropped', () {
      // `HumanQueueConnector` holds its callback in a field, which the name
      // table does not carry. That is allowed to be true — what is not allowed
      // is for it to be invisible. Whatever the reader follows, something will
      // be written in a shape it does not, and the failure mode is a diagram
      // that looks finished.
      final flow = _readComposed();

      expect(
        {for (final u in flow.untraced) u.connectorClass: u.count},
        {'HumanQueueConnector': 1},
        reason:
            'every other connector in the fixture is fully accounted for, so '
            'this also pins that the report does not cry wolf',
      );
    });

    test('the undrawn region is named in the diagram', () {
      final out = renderSequence(_readComposed());
      expect(out, contains('not drawn — HumanQueueConnector: 1 dispatch'));
    });

    test('a name bound nearer than the member is not followed', () {
      // Following by name alone invented interactions. Each of these puts a
      // binding in front of a dispatching method of the same name, and the walk
      // read the binding as a call to the method — a use case for a field that
      // dispatches nothing, which is worse than the omission this whole
      // traversal was added to fix: a short map is checkable against the code,
      // an invented one agrees with nothing.
      final flow = _readShadowed();

      expect(
        flow.useCases.map((u) => '${u.name}: ${u.steps.map((s) => s.target)}'),
        isEmpty,
        reason:
            'a plain local, a destructuring `final (pair, _)`, an `if-case` '
            'variable, a `switch` arm variable, a `session.userName` read and a '
            '`refresh` parameter each collide with a dispatching method, and '
            'none of the six is a call to it',
      );
      // And the methods do dispatch, so the file is not accidentally quiet:
      // they are reported as undrawn instead of attributed to a callback.
      expect(
        {for (final u in flow.untraced) u.connectorClass: u.count},
        {'ShadowedConnector': 6},
      );
    });

    test('one helper answering for two fields still leaves gaps visible', () {
      // The accounting subtracted a tally of attributions from a tally of call
      // sites. `_open()` is one site answering for two fields, so the two totals
      // cancelled and the report concluded nothing was missing — while `BAction`,
      // held in a field, was genuinely undrawn. A silence produced *by* the thing
      // built to break silence.
      final flow = _readShared();

      expect(
        flow.useCases.map((u) => u.name),
        ['onPrimary', 'onSecondary'],
        reason: 'both fields are real interactions, and both go through _open',
      );
      expect(
        {for (final u in flow.untraced) u.connectorClass: u.count},
        {'SharedConnector': 1},
        reason: 'BAction is the one call site no use case reaches',
      );
    });

    test('a fully traced page says nothing about tracing', () {
      // The report has to stay quiet in the ordinary case or it becomes noise
      // that gets filtered out, which is the same as not reporting.
      final flow = _read();
      expect(flow.untraced, isEmpty);
      expect(renderSequence(flow), isNot(contains('not drawn')));
    });
  });

  group('FlowReader', () {
    test(
      'reads one use case per dispatching _Vm callback, skipping the rest',
      () {
        final flow = _read();
        expect(
          flow.useCases.map((u) => u.name),
          ['email', 'onPressedRegister', 'onPressedLogin'],
          reason: 'the plain `title` argument dispatches nothing',
        );
      },
    );

    test('captures the dispatch kind and the awaited round trip', () {
      final flow = _read();
      final register = flow.useCases.firstWhere(
        (u) => u.name == 'onPressedRegister',
      );
      expect(register.steps.first.kind, DispatchKind.dispatchAndWait);
      expect(register.steps.first.target, 'RegistrationAction');
      expect(register.steps.first.awaited, isTrue);
      expect(register.steps.first.kind.isRoundTrip, isTrue);
    });

    test('records the guarding condition so it can be drawn as an alt', () {
      final flow = _read();
      final register = flow.useCases.firstWhere(
        (u) => u.name == 'onPressedRegister',
      );
      final pop = register.steps.last;
      expect(pop.condition, 'status.isCompletedOk');
      expect(pop.isNavigation, isTrue);
    });

    test('sharpens a FieldVm field into `<field>.onChanged`', () {
      final flow = _read();
      final email = flow.useCases.firstWhere((u) => u.name == 'email');
      expect(email.steps.single.trigger, 'onChanged');
      expect(email.label, 'email.onChanged');
    });

    test('extracts the navigation target route', () {
      final flow = _read();
      final login = flow.useCases.firstWhere((u) => u.name == 'onPressedLogin');
      expect(login.steps.single.route, 'LogInRoute');
      expect(login.steps.single.target, 'GoAction.push');
    });

    test('follows the import to read what the action does', () {
      final flow = _read();
      final action = flow.actions['RegistrationAction']!;
      expect(action.mixins, ['WaitingAction']);
      expect(action.isAsync, isTrue);
      expect(action.writesLabel, 'registration');
      expect(
        action.writes,
        [(substate: 'registration', field: null)],
        reason:
            'the label is a rendering of this, not the other way round — '
            'graph_reader used to split the label back apart on the `, ` the '
            'renderer joined it with, so the separator was the only channel '
            'between two readers of one fact',
      );
      expect(action.throwsUserException, isTrue);
      expect(action.file, isNotNull);
    });

    test('navigation dispatches are not mistaken for actions', () {
      final flow = _read();
      expect(flow.actions.keys, isNot(contains('GoAction.push')));
    });
  });

  group('the AppState field an action writes', () {
    /// Reads `writes` out of a lone action file holding [reduceBody].
    String? writesOf(String reduceBody) {
      final root = Directory.systemTemp.createTempSync('frx_writes_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'app/lib/navigation/app_router.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// router\n');
      final file =
          File(p.join(root.path, 'business/lib/redux/x/actions/a.dart'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('''
class SomeAction extends Action {
  @override
  AppState reduce() => $reduceBody;
}
''');
      return FlowReader(
        FrxWorkspace.locate(startDir: root.path),
      ).readAction(file).writesLabel;
    }

    // freezed puts the substate name in a different place in each shape, and
    // reading only the flat one left every generated setter looking inert.
    test('flat form — the substate is the argument', () {
      expect(writesOf('state.copyWith(logIn: const LogInState())'), 'logIn');
    });

    test('deep form — the substate is the method', () {
      expect(writesOf('state.copyWith.logIn(email: value)'), 'logIn.email');
    });

    test('nested form — the substate is the target', () {
      expect(writesOf('state.logIn.copyWith(email: value)'), 'logIn.email');
    });

    test('lists every field, so setting two does not read as setting one', () {
      expect(
        writesOf('state.copyWith.session(token: t, expiresAt: e)'),
        'session.token, session.expiresAt',
      );
    });

    test('the flat form lists every substate too, not only the first', () {
      // What `LogInWithEmailAction` does: the token in and the draft out, in
      // one reduce. Keeping `fields.first` documented it as touching the
      // session alone — the same understatement the deep form is tested
      // against two tests up, in the branch that had no test.
      expect(
        writesOf(
          'state.copyWith(session: SessionState(token: t), '
          'login: const LoginState())',
        ),
        'session, login',
      );
    });

    test('the outermost copyWith wins over the one nested inside it', () {
      // Both are visited; without first-write-wins the inner `email` would
      // shadow the substate the action actually replaces.
      expect(
        writesOf('state.copyWith(logIn: state.logIn.copyWith(email: v))'),
        'logIn',
      );
    });

    test('a call that is not a copyWith writes nothing', () {
      expect(writesOf('state.rebuild(logIn: v)'), isNull);
    });

    test('a copyWith on something that is not state writes nothing', () {
      // Every other shape here names its receiver and the flat one did not, so
      // `task.copyWith(title: t, done: true)` inside a reducer read as a write
      // of two AppState substates called `title` and `done`.
      expect(writesOf('task.copyWith(title: t, done: true)'), isNull);
    });
  });

  group('renderSequence', () {
    test('emits a valid-looking sequenceDiagram with balanced alt/end', () {
      final out = renderSequence(_read());
      expect(out, startsWith('sequenceDiagram'));
      expect(out, contains('participant UI as RegistrationPage'));
      expect(out, contains('participant VM as RegistrationPageConnector'));
      // Anchored to whole lines: a bare substring match would also count the
      // "end" inside an identifier.
      final alts = RegExp(r'^\s*alt ', multiLine: true).allMatches(out).length;
      final ends = RegExp(r'^\s*end$', multiLine: true).allMatches(out).length;
      expect(alts, greaterThan(0));
      expect(ends, alts, reason: 'every alt block is closed');
    });

    test('shows the round trip with activation bars and a status reply', () {
      final out = renderSequence(_read());
      expect(out, contains('VM->>+A'), reason: 'activates on dispatchAndWait');
      expect(out, contains('-->>-VM: ActionStatus'));
    });

    test('annotates the action with its mixins and async-ness', () {
      expect(renderSequence(_read()), contains('WaitingAction · async'));
    });

    test('routes a UserException back to the caller, not to itself', () {
      final out = renderSequence(_read());
      expect(out, contains('--xVM: UserException'));
    });

    test('draws the guarded navigation inside an alt block', () {
      final out = renderSequence(_read());
      expect(out, contains('alt status.isCompletedOk'));
      expect(out, contains('NAV: GoAction.pop'));
    });

    test('names the field interaction with its trigger', () {
      expect(renderSequence(_read()), contains('User->>UI: email.onChanged'));
    });
  });

  group('a push with arguments', () {
    /// The dispatch steps a connector-shaped source yields.
    List<DispatchStep> stepsOf(String body) {
      final root = Directory.systemTemp.createTempSync('frx_flow_args_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'app/lib/navigation/app_router.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class AppRouter {}');
      final file = File(p.join(root.path, 'app/lib/connectors/c.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(body);
      return FlowReader(
        FrxWorkspace.locate(startDir: root.path),
      ).readDispatches(file).steps;
    }

    test('carries what was handed to the route, not just its type', () {
      final steps = stepsOf('''
class _Factory extends VmFactory<AppState, CatalogPageConnector, _Vm> {
  _Vm fromStore() => _Vm(
    onTapItem: (id) => dispatch(GoAction.push(ItemRoute(id: id))),
  );
}
''');
      final step = steps.single;
      expect(step.route, 'ItemRoute');
      // On `/item/:id` this is the half that says *which* item.
      expect(step.routeArgs, 'id: id');
    });

    test('drops the key auto_route adds to every generated route', () {
      final steps = stepsOf('''
class _Factory {
  _Vm fromStore() => _Vm(
    go: () => dispatch(GoAction.push(ItemRoute(id: 1, key: k))),
  );
}
''');
      expect(steps.single.routeArgs, 'id: 1');
    });

    test('a route that takes nothing reads as it always did', () {
      final steps = stepsOf('''
class _Factory {
  _Vm fromStore() => _Vm(
    go: () => dispatch(GoAction.push(const HomeRoute())),
  );
}
''');
      expect(steps.single.route, 'HomeRoute');
      expect(steps.single.routeArgs, isNull);
    });
  });
}
