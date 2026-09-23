import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// `rename` over a fixture that has what the template has around a substate: a
/// service folder sharing its name, code holding a same-named member of its
/// own, tests, and generated output. What a rename must reach is the substate;
/// what it must leave is everything that merely spells it.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  void put(String relative, String content) => fx.file(relative)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  test(
    'renaming a substate moves its references and nothing that shares its name',
    () async {
      // The template's own shape: `redux/services/connectivity/` holds the
      // service, and `dependencies.dart` keeps it in a field called
      // `connectivity`. The token rewrite pointed both imports at
      // `services/network/` — never created — and renamed the field.
      put(
        'business/lib/redux/services/connectivity/connectivity.dart',
        'class ConnectivityService { bool get isConnected => true; }\n',
      );
      const dependencies = '''
import 'redux/services/connectivity/connectivity.dart';

class Dependencies {
  late final connectivity = ConnectivityService();

  bool get online => connectivity.isConnected;
}
''';
      put('business/lib/dependencies.dart', dependencies);
      // Tests import the moved files and read the field as lib/ does; the sweep
      // skipped them, so `business/test` stopped compiling.
      put('business/test/state_test.dart', '''
import 'package:business/redux/app_state.dart';
import 'package:business/redux/connectivity/models/connectivity_state.dart';

void main() {
  final state = AppState.initial();
  print(state.connectivity.value);
  print(const ConnectivityState());
}
''');
      // flutter_gen output is generated, and was swept as source.
      const generated =
          '// connectivity\nclass Assets { static const connectivity = 1; }\n';
      put('ui/lib/generated/assets.gen.dart', generated);

      final res = await runInProcess(fx, [
        'rename',
        'connectivity',
        'network',
        '--apply',
        '--no-format',
      ]);
      expect(res.exitCode, 0, reason: res.stderr);

      expect(fx.read('business/lib/dependencies.dart'), dependencies);
      expect(fx.read('ui/lib/generated/assets.gen.dart'), generated);
      expect(
        fx.read('business/lib/redux/app_state.dart'),
        allOf(
          contains("import 'network/models/network_state.dart';"),
          contains('required NetworkState network,'),
          contains('network: NetworkState(),'),
        ),
      );
      expect(
        fx.read('business/test/state_test.dart'),
        allOf(
          contains(
            "import 'package:business/redux/network/models/network_state.dart';",
          ),
          contains('state.network.value'),
          contains('const NetworkState()'),
        ),
      );
    },
  );

  test('renaming a page with no ui page moves only what is there', () async {
    // A tab shell: `add-tabs` writes a connector hosting an `AutoTabsRouter`
    // and no screen in `ui`. The plan moved the missing page anyway, previewed
    // it, and the apply's pre-flight aborted on it.
    fx.file('ui/lib/pages/home_page.dart').deleteSync();

    final res = await runInProcess(fx, [
      'rename',
      'home',
      'dashboard',
      '--apply',
      '--no-format',
    ]);
    expect(res.exitCode, 0, reason: res.stderr);
    expect(res.stdout, isNot(contains('home_page.dart →')));
    expect(
      fx.file('app/lib/connectors/dashboard_page_connector.dart').existsSync(),
      isTrue,
    );
    expect(fx.file('ui/lib/pages/dashboard_page.dart').existsSync(), isFalse);
  });
}
