import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/model/placement.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

import 'support/fixture.dart';
import 'support/in_process.dart';

/// Code that is wired, compiles, and sits in the wrong place.
///
/// Every rule keys on a folder, a filename convention, or an annotation that is
/// present or absent — the admission test for a rule here is that its syntactic
/// form cannot be wrong in the common case. So the cases worth pinning are the
/// near misses: the file the architecture puts exactly where it belongs, and the
/// prose that mentions an annotation without carrying one.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('frx_placement_'));
  tearDown(() => root.deleteSync(recursive: true));

  void put(String rel, String content) {
    File(p.join(root.path, rel))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  List<PlacementFinding> scan({Set<PlacementRule> silenced = const {}}) =>
      placementFindings(FrxWorkspace(root), silenced: silenced);

  Set<PlacementRule> rulesFrom(List<PlacementFinding> found) =>
      found.map((f) => f.rule).toSet();

  const facadeSource = '''
extension type const Selector(AppState _state) {}

extension type SelectLogIn(AppState _state) implements Selector {
  String? get email => _state.logIn.email;
}
''';

  group('a selector outside the facade', () {
    test('is reported', () {
      put('business/lib/redux/selectors.dart', facadeSource);
      put('business/lib/redux/log_in/extra_selectors.dart', '''
extension type SelectLogInExtra(AppState _state) implements Selector {
  bool get isReady => _state.logIn.email != null;
}
''');
      final found = scan();
      expect(rulesFrom(found), {PlacementRule.selectorOutsideFacade});
      expect(found.single.message, contains('extra_selectors.dart'));
      expect(found.single.message, contains('SelectLogInExtra'));
    });

    test('so is one that forgot to implement Selector', () {
      // The rule used to require the clause, so it went silent in exactly the
      // case it exists for: dropping `implements Selector` is the easiest half
      // to forget, and it is the half that actually puts the getters on the
      // facade. Recognition has to be wider than generation.
      put('business/lib/redux/selectors.dart', facadeSource);
      put('business/lib/redux/log_in/stray_selectors.dart', '''
extension type SelectStray(AppState _state) {
  String? get email => _state.logIn.email;
}
''');
      final found = scan();
      expect(rulesFrom(found), {PlacementRule.selectorOutsideFacade});
      expect(found.single.message, contains('SelectStray'));
    });

    test('so is one on the Selectors mixin', () {
      // The mixin is the facade's reach without the facade — a getter added to
      // it lands on every consumer that mixes it in. Widening the name test
      // once dropped this case, which is the direction that matters least to
      // get right and most to notice.
      put('business/lib/redux/selectors.dart', facadeSource);
      put('app/lib/more.dart', '''
extension MoreSelectors on Selectors {
  bool get ready => true;
}
''');
      expect(rulesFrom(scan()), {PlacementRule.selectorOutsideFacade});
    });

    test('so is a composite on a substate selector, not just on Select', () {
      put('business/lib/redux/selectors.dart', facadeSource);
      put('app/lib/extras.dart', '''
extension SelectLogInExtras on SelectLogIn {
  bool get canSubmit => email != null;
}
''');
      expect(rulesFrom(scan()), {PlacementRule.selectorOutsideFacade});
    });

    test('so is a composite added as an extension on Select', () {
      put('business/lib/redux/selectors.dart', facadeSource);
      put('app/lib/composites.dart', '''
extension SelectComposites on Select {
  bool get canEnterApp => true;
}
''');
      expect(rulesFrom(scan()), {PlacementRule.selectorOutsideFacade});
    });

    test('the facade itself is not reported', () {
      put('business/lib/redux/selectors.dart', facadeSource);
      expect(scan(), isEmpty);
    });

    test('an unrelated extension type is not a selector', () {
      // The bare prefix is not the rule — the rest of the name has to start a
      // new word. `Selectable` is an ordinary Dart name that happens to begin
      // with the same six letters, and `on String` is not a selector however the
      // extension is called.
      put('business/lib/redux/selectors.dart', facadeSource);
      put('ui/lib/widgets/selectable.dart', '''
extension type Selectable(String _s) {
  String get label => _s;
}

extension StringSelectHelpers on String {
  String get selected => this;
}
''');
      expect(scan(), isEmpty);
    });
  });

  group('an action file outside its actions directory', () {
    test('is reported', () {
      put('business/lib/redux/log_in/set_email_action.dart', 'class X {}');
      final found = scan();
      expect(rulesFrom(found), {PlacementRule.actionOutsideActionsDir});
      expect(found.single.message, contains('redux/<substate>/actions/'));
    });

    test('one in the right place is not', () {
      put(
        'business/lib/redux/log_in/actions/set_email_action.dart',
        'class X {}',
      );
      expect(scan(), isEmpty);
    });

    test('one under a non-substate folder is reported', () {
      // `redux/services/actions/` is not a substate's actions directory.
      put('business/lib/redux/services/actions/poll_action.dart', 'class X {}');
      expect(rulesFrom(scan()), {PlacementRule.actionOutsideActionsDir});
    });

    test("the app's own navigation action is left alone", () {
      // `app/lib/navigation/go_action.dart` is a navigation action, not a
      // substate's, and the architecture puts it exactly there. A rule that
      // reported it would be wrong about a correct file — which is the whole
      // reason this one is scoped to the business package.
      put('app/lib/navigation/go_action.dart', 'class GoAction {}');
      expect(scan(), isEmpty);
    });

    test('generated output is nobody\'s placement decision', () {
      put('business/lib/redux/stray_action.freezed.dart', 'class X {}');
      expect(scan(), isEmpty);
    });
  });

  group('an annotated connector outside the connectors package', () {
    test('is reported', () {
      put('ui/lib/pages/stray_page.dart', '''
@RoutePage()
class StrayPageConnector extends StatelessWidget {}
''');
      final found = scan();
      expect(rulesFrom(found), {PlacementRule.connectorOutsideConnectors});
      expect(found.single.message, contains('StrayPageConnector'));
    });

    test('one in the connectors package is not', () {
      put('app/lib/connectors/log_in_page_connector.dart', '''
@RoutePage()
class LogInPageConnector extends StatelessWidget {}
''');
      expect(scan(), isEmpty);
    });

    test('prose that merely names the annotation is not one', () {
      // `app_router.dart`'s own doc comment says `@RoutePage()`. A check that
      // cannot tell prose from code reports the file that is most certainly in
      // the right place.
      put('app/lib/navigation/app_router.dart', '''
/// Generated into `app_router.gr.dart` from the `@RoutePage()` connectors.
class AppRouter extends RootStackRouter {}
''');
      expect(scan(), isEmpty);
    });
  });

  test('each rule can be silenced on its own', () {
    put('business/lib/redux/log_in/set_email_action.dart', 'class X {}');
    put('ui/lib/pages/stray_page.dart', '''
@RoutePage()
class StrayPageConnector {}
''');
    expect(rulesFrom(scan()), hasLength(2));
    expect(rulesFrom(scan(silenced: {PlacementRule.actionOutsideActionsDir})), {
      PlacementRule.connectorOutsideConnectors,
    });
    expect(
      scan(
        silenced: {
          PlacementRule.actionOutsideActionsDir,
          PlacementRule.connectorOutsideConnectors,
        },
      ),
      isEmpty,
    );
  });

  group('through the audit', () {
    late Fixture fx;

    setUp(() => fx = Fixture.create());
    tearDown(() => fx.dispose());

    Future<List<Map<String, Object?>>> audit() async {
      final r = await runInProcess(fx, ['doctor', '--json']);
      return ((jsonDecode(r.stdout) as Map<String, Object?>)['findings']!
              as List)
          .cast<Map<String, Object?>>();
    }

    test('a placement finding is a warning carrying no fix', () async {
      fx.file('business/lib/redux/log_in/set_email_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class SetEmailAction {}\n');

      final placement = (await audit())
          .where((f) => f['rule'] == 'action-outside-actions-dir')
          .toList();
      expect(placement, hasLength(1));
      expect(placement.single['severity'], 'warn');
      expect(
        placement.single['fix'],
        isNull,
        reason:
            'a placement fix is a move, and a deliberate placement is '
            'exactly the false positive being accepted',
      );
    });

    test('it does not change the exit code', () async {
      // A check that can be wrong in someone else's project must not fail their
      // build. Asserted as "the same as before", not "zero" — the fixture has
      // ungenerated parts of its own, which are errors and should stay errors.
      final before = (await runInProcess(fx, ['doctor', '--json'])).exitCode;
      fx.file('business/lib/redux/log_in/set_email_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class SetEmailAction {}\n');
      final after = await runInProcess(fx, ['doctor', '--json']);
      expect(after.exitCode, before);
      expect(
        (jsonDecode(after.stdout) as Map<String, Object?>)['findings'],
        isNotEmpty,
        reason: 'the finding is reported, it just does not fail anything',
      );
    });

    test('.frxrc silences one rule and leaves the others', () async {
      fx.file('business/lib/redux/log_in/set_email_action.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('class SetEmailAction {}\n');
      fx.file('ui/lib/pages/stray_page.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('@RoutePage()\nclass StrayPageConnector {}\n');

      expect(
        (await audit()).map((f) => f['rule']).whereType<String>().toSet(),
        {'action-outside-actions-dir', 'connector-outside-connectors'},
      );

      fx
          .file('.frxrc')
          .writeAsStringSync(
            jsonEncode({
              'placement': {'action-outside-actions-dir': false},
            }),
          );
      expect(
        (await audit()).map((f) => f['rule']).whereType<String>().toSet(),
        {'connector-outside-connectors'},
      );
    });
  });

  test('the live monorepo reports no placement findings', () {
    // The rules describe this repository's own conventions, so any finding here
    // is either a real misplacement or a rule that is wrong.
    final live = Directory('..');
    if (!File(
      p.join(live.path, 'business/lib/redux/selectors.dart'),
    ).existsSync()) {
      return;
    }
    expect(
      placementFindings(FrxWorkspace(live)).map((f) => f.message),
      isEmpty,
    );
  });
}
