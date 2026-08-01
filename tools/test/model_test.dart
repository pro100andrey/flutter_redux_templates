import 'dart:io';

import 'package:test/test.dart';
import 'package:tools/src/model/page_artifact.dart';
import 'package:tools/src/model/substate_artifact.dart';
import 'package:tools/src/model/target_resolver.dart';
import 'package:tools/src/redux/app_state_source.dart';
import 'package:tools/src/routing/routes_source.dart';
import 'package:tools/src/util/casing.dart';

void main() {
  group('SubstateArtifact', () {
    final a = SubstateArtifact.parse('forgot password');

    test('derives the naming conventions from the name', () {
      expect(a.field, 'forgotPassword');
      expect(a.stateType, 'ForgotPasswordState');
      expect(a.selectorType, 'SelectForgotPassword');
      expect(a.waitingEnum, 'ForgotPasswordWaiting');
      expect(a.actionClass, 'ForgotPasswordAction');
      expect(a.addActionClass, 'AddForgotPasswordAction');
      expect(a.retrieveActionClass, 'RetrieveForgotPasswordAction');
      expect(a.folder, 'forgot_password');
      expect(
        a.stateImportPath,
        'forgot_password/models/forgot_password_state.dart',
      );
    });

    test('substateOfSelectorType inverts selectorType', () {
      expect(SubstateArtifact.substateOfSelectorType(a.selectorType), a.field);
    });

    test('substateOfSelectorType declines what is not a selector type', () {
      // A type that merely starts with the prefix, and the bare prefix itself:
      // both would otherwise file rows under a substate that does not exist.
      expect(SubstateArtifact.substateOfSelectorType('Select'), isNull);
      expect(SubstateArtifact.substateOfSelectorType('LogInState'), isNull);
      // The facade's own mixin — `Select` + a lowercase tail is not a substate.
      expect(SubstateArtifact.substateOfSelectorType('Selectors'), isNull);
    });

    test('absolute file paths hang off the redux dir', () {
      final redux = Directory('/repo/business/lib/redux');
      expect(
        a.stateFile(redux).path,
        '/repo/business/lib/redux/forgot_password/models/forgot_password_state.dart',
      );
      expect(a.dir(redux).path, '/repo/business/lib/redux/forgot_password');
    });

    test('renamableBasenames maps only the generated basenames', () {
      final to = SubstateArtifact.parse('reset_password');
      expect(a.renamableBasenames(to), {
        'forgot_password_state.dart': 'reset_password_state.dart',
        'forgot_password_action.dart': 'reset_password_action.dart',
        'add_forgot_password_action.dart': 'add_reset_password_action.dart',
        'retrieve_forgot_password_action.dart':
            'retrieve_reset_password_action.dart',
      });
    });
  });

  group('PageArtifact', () {
    final a = PageArtifact.parse('log in');

    test('derives the naming conventions from the name', () {
      expect(a.routeType, 'LogInRoute');
      expect(a.pageClass, 'LogInPage');
      expect(a.connectorClass, 'LogInPageConnector');
      expect(a.connectorImport, '../connectors/log_in_page_connector.dart');
      expect(a.defaultPath, '/log-in');
    });

    test('fromRouteType round-trips a <Pascal>Route', () {
      final p = PageArtifact.fromRouteType('LogInRoute');
      expect(p, isNotNull);
      expect(p!.routeType, 'LogInRoute');
      expect(p.name.snake, 'log_in');
    });

    test('fromRouteType returns null for a non-route type', () {
      expect(PageArtifact.fromRouteType('LogInPage'), isNull);
      expect(PageArtifact.fromRouteType('Anything'), isNull);
    });
  });

  group('TargetResolver.resolve', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('frx_resolver_'));
    tearDown(() => dir.deleteSync(recursive: true));

    AppStateSource appStateWith(String body) {
      final f = File('${dir.path}/app_state.dart')..writeAsStringSync(body);
      return AppStateSource(f);
    }

    RoutesSource routesWith(String body) {
      final f = File('${dir.path}/app_router.dart')..writeAsStringSync(body);
      return RoutesSource(f);
    }

    const appState = '''
@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required LogInState logIn,
    required Wait wait,
  }) = _AppState;
  factory AppState.initial() => const AppState(logIn: LogInState(), wait: Wait.empty);
}
''';

    const appRouter = '''
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LogInRoute.page, path: '/log-in'),
  ];
}
''';

    test('both sources missing → not-in-project (70)', () {
      final r = const TargetResolver(
        null,
        null,
      ).resolve(Casing.parse('log_in'));
      expect(r.ok, isFalse);
      expect(r.code, 70);
    });

    test('a wired substate resolves to substate', () {
      final r = TargetResolver(
        appStateWith(appState),
        null,
      ).resolve(Casing.parse('log_in'));
      expect(r.ok, isTrue);
      expect(r.kind, ArtifactKind.substate);
    });

    test('a name matching neither → not wired (70)', () {
      final r = TargetResolver(
        appStateWith(appState),
        null,
      ).resolve(Casing.parse('nope'));
      expect(r.ok, isFalse);
      expect(r.code, 70);
    });

    test('a name matching both substate and page → ambiguous (64)', () {
      final r = TargetResolver(
        appStateWith(appState),
        routesWith(appRouter),
      ).resolve(Casing.parse('log_in'));
      expect(r.ok, isFalse);
      expect(r.code, 64);
    });

    test('--kind forces the kind without checking wiring', () {
      final r = TargetResolver(
        appStateWith(appState),
        null,
      ).resolve(Casing.parse('whatever'), forced: 'page');
      expect(r.ok, isTrue);
      expect(r.kind, ArtifactKind.page);
    });
  });
}
