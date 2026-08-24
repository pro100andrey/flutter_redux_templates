import 'package:test/test.dart';

import 'support/fixture.dart';

/// `frx remove --kind selector` — the other half of `add-selector`.
///
/// The asymmetry this closes: `add-selector` writes a computed getter into the
/// facade and nothing took one out, while `selectors.dart` sits under the
/// placement guard — so the only way out was a hand edit to a file frx
/// complains about being hand-edited. The splice itself already existed; the
/// field path has used it since `--kind field` shipped, to remove the getter it
/// wrote beside a field.
void main() {
  late Fixture fx;
  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  String selectors() => fx.read('business/lib/redux/selectors.dart');

  test('removes the getter, addressed the way graph prints it', () async {
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
      '--apply',
      '--no-format',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), isNot(contains('get email')));
    expect(
      selectors(),
      contains('SelectConnectivity'),
      reason: 'the rest of the facade is untouched',
    );
  });

  test('takes the bare name with --state', () async {
    final res = await runFrx(fx, [
      'remove',
      'email',
      '--kind',
      'selector',
      '--state',
      'log_in',
      '--apply',
      '--no-format',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), isNot(contains('get email')));
  });

  test('previews without --apply', () async {
    final before = selectors();
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
    ]);

    expect(res.exitCode, 0, reason: '${res.stderr}');
    expect(selectors(), before);
    expect(res.stdout, contains('SelectLogIn.email'));
  });

  test('refuses while another getter on the facade reads it', () async {
    // The same refusal the field path makes, for the same reason: the reader is
    // in the file being spliced, and a selector body is the author's to
    // rewrite. Writing the splice anyway would leave a file that cannot
    // compile and report success.
    fx
        .file('business/lib/redux/selectors.dart')
        .writeAsStringSync(
          selectors().replaceFirst(
            'String? get email => _state.logIn.email;',
            'String? get email => _state.logIn.email;\n'
                '  bool get hasEmail => email != null;',
          ),
        );

    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.email',
      '--kind',
      'selector',
      '--apply',
    ]);

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('SelectLogIn.hasEmail'));
    expect(selectors(), contains('get email'));
  });

  test('refuses a getter the facade does not declare', () async {
    final res = await runFrx(fx, [
      'remove',
      'SelectLogIn.nope',
      '--kind',
      'selector',
      '--apply',
    ]);

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('has no "nope" getter'));
  });

  /// The imports the facade was carrying for one getter.
  ///
  /// `add-selector` writes an import for what the getter names; nothing took one
  /// out, so removing
  ///
  ///     bool get isWaiting => _state.wait.isWaitingForType<LoadContactsAction>();
  ///
  /// left the action file imported by a file that no longer names it. On a real
  /// project the facade imports one write-layer file per waiting getter — eighteen
  /// of them — so this is the ordinary case, not the corner one.
  group('the imports the getter was the last reason for', () {
    late Fixture fx;
    setUp(() => fx = Fixture.create());
    tearDown(() => fx.dispose());

    String selectors() => fx.read('business/lib/redux/selectors.dart');

    /// Rewrites the facade around [body], with [imports] above it.
    void facade(String body, {List<String> imports = const []}) {
      fx.file('business/lib/redux/selectors.dart').writeAsStringSync('''
  import 'app_state.dart';
  ${imports.map((i) => "import '$i';").join('\n')}

  mixin Selectors {
    AppState get state;

    SelectLogIn get logIn => SelectLogIn(state);
  }

  extension type SelectLogIn(AppState _state) {
  $body}
  ''');
    }

    /// A file under `business/lib/redux` declaring [declarations].
    void put(String rel, String declarations) {
      fx.file('business/lib/redux/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(declarations);
    }

    Future<void> remove(String selector) async {
      final res = await runFrx(fx, [
        'remove',
        selector,
        '--kind',
        'selector',
        '--apply',
        '--no-format',
      ]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
    }

    test('goes with it', () async {
      put('log_in/actions/log_in_action.dart', 'class LogInAction {}\n');
      facade(
        '''
    String? get email => _state.logIn.email;
    bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();
  ''',
        imports: ['log_in/actions/log_in_action.dart'],
      );

      await remove('SelectLogIn.isWaiting');

      expect(selectors(), isNot(contains('log_in_action.dart')));
      expect(
        selectors(),
        contains("import 'app_state.dart'"),
        reason: 'the import the rest of the facade still needs',
      );
    });

    test('stays when another getter still names it', () async {
      put('log_in/actions/log_in_action.dart', 'class LogInAction {}\n');
      facade(
        '''
    bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();
    bool get isBusy => _state.wait.isWaitingForType<LogInAction>();
  ''',
        imports: ['log_in/actions/log_in_action.dart'],
      );

      await remove('SelectLogIn.isBusy');

      expect(
        selectors(),
        contains("import 'log_in/actions/log_in_action.dart'"),
      );
    });

    test('a name in prose is not a reason to keep it', () async {
      // The use is read off the tree, not scanned out of the text. A facade whose
      // comment says the word was a facade whose import could never be removed.
      put('log_in/actions/log_in_action.dart', 'class LogInAction {}\n');
      facade(
        '''
    /// Waiting is keyed on LogInAction, which is why the read layer imports it.
    String? get email => _state.logIn.email;
    bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();
  ''',
        imports: ['log_in/actions/log_in_action.dart'],
      );

      await remove('SelectLogIn.isWaiting');

      expect(selectors(), isNot(contains("import 'log_in/actions")));
    });

    test('an import that shares its names with one that stays goes', () async {
      // Two imports supplying `Token`, which is ordinary rather than an error: a
      // generated client re-exports the package beside it. Keeping every import
      // that still names something means the second can never be removed, so what
      // decides is whether an import that is *staying* answers for the name.
      put('log_in/models/token.dart', 'class Token {}\n');
      put('log_in/models/extras.dart', '''
  export 'token.dart';

  class Extra {}
  ''');
      facade(
        '''
    Token? get token => _state.logIn.token;
    Extra? get extra => _state.logIn.extra;
  ''',
        imports: ['log_in/models/token.dart', 'log_in/models/extras.dart'],
      );

      await remove('SelectLogIn.extra');

      expect(selectors(), isNot(contains('extras.dart')));
      expect(
        selectors(),
        contains("import 'log_in/models/token.dart'"),
        reason: 'the one still answering for `Token`',
      );
    });

    test('an import that cannot be read is left alone', () async {
      // A package no `package_config.json` here resolves. Unknown is not "unused":
      // erring wide leaves a lint, erring narrow leaves a build.
      facade(
        '''
    String? get email => _state.logIn.email;
    Mystery? get mystery => _state.logIn.mystery;
  ''',
        imports: ['package:nowhere/nowhere.dart'],
      );

      await remove('SelectLogIn.mystery');

      expect(selectors(), contains("import 'package:nowhere/nowhere.dart'"));
    });
  });
}
