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

void main() {
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
