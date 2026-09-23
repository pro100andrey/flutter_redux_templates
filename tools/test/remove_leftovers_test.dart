import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// What every kind of `remove` says about the code it leaves naming what it
/// takes away.
///
/// Each removal used to answer that for itself or not at all, and most said
/// nothing: the preview listed the files to delete, the closing line said "run
/// `frx doctor`", and the persistor importing a deleted state, the connector
/// dispatching a deleted action, the home page pushing a deleted route were
/// found by the analyzer afterwards. The previews here are only previews —
/// what is asserted is that the plan names them before anything is done.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  void put(String relative, String content) => fx.file(relative)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  Future<String> preview(List<String> args) async {
    final res = await runInProcess(fx, ['remove', ...args]);
    expect(res.exitCode, 0, reason: res.stderr);
    return res.stdout;
  }

  Matcher leaves(String file, String names) => allOf(
    contains('Still names what is removed'),
    contains('$file — $names'),
  );

  test('a substate: its importers, and the readers of its slot', () async {
    put(
      'business/lib/persistor.dart',
      "import 'redux/log_in/models/log_in_state.dart';\n"
          'final s = LogInState();\n',
    );
    // Imports nothing of the substate; reads it through the facade.
    put(
      'app/lib/app.dart',
      'class F with Selectors { String? get e => logIn.email; }\n',
    );
    // A local of the same name is not the slot.
    put('ui/lib/x.dart', 'void f() { final logIn = 1; print(logIn); }\n');

    final out = await preview(['log_in', '--kind', 'substate']);
    expect(out, leaves('business/lib/persistor.dart', 'log_in_state.dart'));
    expect(out, contains('app/lib/app.dart — .logIn'));
    expect(out, isNot(contains('ui/lib/x.dart')));
  });

  test('a page: the hop add-nav wrote to it', () async {
    // `onTapTasks` dispatching `GoAction.push(TasksRoute())` — the route is
    // generated from the connector being deleted.
    put(
      'app/lib/connectors/log_in_page_connector.dart',
      '@RoutePage()\nclass LogInPageConnector {\n'
          '  void onTapHome() => push(const HomeRoute());\n}\n',
    );
    final out = await preview(['home', '--kind', 'page']);
    expect(
      out,
      leaves('app/lib/connectors/log_in_page_connector.dart', 'HomeRoute'),
    );
  });

  test('a model: the state field typed with it', () async {
    put('models/lib/task.dart', 'class Task {}\n');
    put(
      'business/lib/redux/log_in/models/extra.dart',
      "import 'package:models/task.dart';\nTask? current;\n",
    );
    final out = await preview(['task', '--kind', 'model']);
    expect(
      out,
      leaves('business/lib/redux/log_in/models/extra.dart', 'task.dart, Task'),
    );
  });

  test('a file nothing names says nothing extra', () async {
    put('models/lib/task.dart', 'class Task {}\n');
    final out = await preview(['task', '--kind', 'model']);
    expect(out, isNot(contains('Still names what is removed')));
  });
}
