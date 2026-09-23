import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';
import 'package:tools/src/ast/field_rename.dart';
import 'package:tools/src/ast/relocation.dart';
import 'package:tools/src/ast/rename_edits.dart';
import 'package:tools/src/redux/ast_edit.dart';

/// Renaming a file's contents off the parse tree. See [RenameEdits] for what it
/// replaced; these are the cases that decide whether it is right.
void main() {
  /// The folder a substate rename moves, `/r/lib/redux/log_in` →
  /// `/r/lib/redux/sign_in`, with its state file renamed on the way. Paths are
  /// POSIX-shaped strings; nothing here touches a disk.
  String? moveLogIn(String path) {
    const from = '/r/lib/redux/log_in/';
    if (!path.startsWith(from)) {
      return null;
    }
    final rest = path.substring(from.length);
    return '/r/lib/redux/sign_in/${rest.replaceAll('log_in_state', 'sign_in_state')}';
  }

  String rename(
    String source, {
    Map<String, String> identifiers = const {},
    FieldRename? field,
    String? Function(String)? moveOf,
    String path = '/r/lib/redux/app_state.dart',
    Map<String, String> literals = const {},
  }) {
    final edits =
        RenameEdits(
          identifiers: identifiers,
          field: field,
          relocation: moveOf == null
              ? null
              : Relocation(moveOf: moveOf, packages: {'r': '/r/lib'}),
          literals: literals,
        ).of(
          parseString(content: source, throwIfDiagnostics: false).unit,
          path: path,
        );
    return applyEdits(source, edits);
  }

  group('identifiers', () {
    test('a whole token moves, a token that contains it does not', () {
      expect(
        rename(
          'class LogInState {}\nclass MyLogInStateThing {}\n',
          identifiers: {'LogInState': 'SignInState'},
        ),
        'class SignInState {}\nclass MyLogInStateThing {}\n',
      );
    });

    test('a generated-code prefix comes along', () {
      // freezed writes `_$LogInState`, and it is one identifier. The old sweep
      // reached it by accident — `$` is not a word character — and needed a
      // hand-written second pattern for `_LogInState`, where `_` is one.
      expect(
        rename(
          'abstract class LogInState with _\$LogInState {}\n'
          'class _LogInState {}\n',
          identifiers: {'LogInState': 'SignInState'},
        ),
        'abstract class SignInState with _\$SignInState {}\n'
        'class _SignInState {}\n',
      );
    });

    test('a string literal is left alone', () {
      // The whole point: a persistence key that happens to spell the name must
      // survive a rename.
      expect(
        rename(
          "const key = 'logIn';\nfinal x = logIn;\n",
          identifiers: {'logIn': 'signIn'},
        ),
        "const key = 'logIn';\nfinal x = signIn;\n",
      );
    });

    test('an l10n key is left alone', () {
      // `S.current.logIn` is a translation getter that happens to share a word
      // with the substate. The old sweep said so with a lookbehind *and* by
      // refusing to touch `ui/lib` at all.
      expect(
        rename(
          'final a = S.current.logIn;\nfinal b = state.logIn;\n',
          identifiers: {'logIn': 'signIn'},
        ),
        'final a = S.current.logIn;\nfinal b = state.signIn;\n',
      );
    });

    test('a comment reference carries its generated-code prefix too', () {
      // `\\b` is what put `_LogInState` and `_\$LogInState` on different
      // footings in the first place; a comment should not be where that
      // accident lives on.
      expect(
        rename(
          '/// [LogInState], [_LogInState] and [_\$LogInState].\nclass X {}\n',
          identifiers: {'LogInState': 'SignInState'},
        ),
        '/// [SignInState], [_SignInState] and [_\$SignInState].\nclass X {}\n',
      );
    });

    test('a comment at the end of the file is reached', () {
      // It hangs off the end-of-file token, where a loop stopping *at* EOF
      // never looks.
      expect(
        rename(
          'class X {}\n// trailing: LogInState\n',
          identifiers: {'LogInState': 'SignInState'},
        ),
        'class X {}\n// trailing: SignInState\n',
      );
    });

    test('a dartdoc reference follows the class it names', () {
      // The one place a token walk would not reach, and dropping it would leave
      // the comment pointing at a class that no longer exists.
      expect(
        rename(
          '/// Reads [LogInState] for the page.\nclass X {}\n',
          identifiers: {'LogInState': 'SignInState'},
        ),
        '/// Reads [SignInState] for the page.\nclass X {}\n',
      );
    });
  });

  group('directive URIs', () {
    test('a URI naming a moved file follows it, and its part too', () {
      expect(
        rename(
          "import 'log_in/models/log_in_state.dart';\n",
          moveOf: moveLogIn,
        ),
        "import 'sign_in/models/sign_in_state.dart';\n",
      );
      // The part is generated, not moved — it follows the rule its file does.
      expect(
        rename(
          "part 'log_in_state.freezed.dart';\n",
          moveOf: moveLogIn,
          path: '/r/lib/redux/log_in/models/log_in_state.dart',
        ),
        "part 'sign_in_state.freezed.dart';\n",
      );
    });

    test('a folder that merely shares the name stays', () {
      // `redux/services/connectivity/` is not the `connectivity` substate. The
      // token rewrite pointed dependencies.dart at `services/network/`, a
      // folder the rename never made.
      expect(
        rename(
          "import 'services/log_in/log_in.dart';\n"
          "import 'package:r/theme/log_in/x.dart';\n",
          moveOf: moveLogIn,
        ),
        "import 'services/log_in/log_in.dart';\n"
        "import 'package:r/theme/log_in/x.dart';\n",
      );
    });

    test('a package URI into the moved folder follows it', () {
      expect(
        rename(
          "import 'package:r/redux/log_in/actions/go_action.dart';\n",
          moveOf: moveLogIn,
          path: '/r/test/actions_test.dart',
        ),
        "import 'package:r/redux/sign_in/actions/go_action.dart';\n",
      );
    });

    test('a moved file keeps its imports of what stayed', () {
      // From `redux/services/log_in/`, the moved action is two levels up; from
      // inside the moved folder, the facade is where it always was.
      expect(
        rename(
          "import '../../log_in/actions/go_action.dart';\n",
          moveOf: moveLogIn,
          path: '/r/lib/redux/services/log_in/dispatcher.dart',
        ),
        "import '../../sign_in/actions/go_action.dart';\n",
      );
      expect(
        rename(
          "import '../../app_state.dart';\n",
          moveOf: moveLogIn,
          path: '/r/lib/redux/log_in/actions/go_action.dart',
        ),
        "import '../../app_state.dart';\n",
      );
    });

    test('a URI written with double quotes keeps them', () {
      expect(
        rename('import "log_in/x.dart";\n', moveOf: moveLogIn),
        'import "sign_in/x.dart";\n',
      );
    });
  });

  group('the field', () {
    const field = FieldRename(
      from: 'theme',
      to: 'look',
      ownerTypes: {'ThemeState', 'SelectTheme'},
    );

    test('the slot moves where it is declared and read', () {
      expect(
        rename(
          'class AppState {\n'
          '  factory AppState({required ThemeState theme}) = _A;\n'
          '  factory AppState.initial() => AppState(theme: ThemeState());\n'
          '}\n'
          'mixin Selectors {\n'
          '  SelectTheme get theme => SelectTheme(state);\n'
          '}\n'
          'AppState r(AppState state) =>\n'
          '    state.copyWith(theme: state.theme.copyWith(x: 1));\n'
          'Object f() => theme.mode;\n',
          field: field,
        ),
        'class AppState {\n'
        '  factory AppState({required ThemeState look}) = _A;\n'
        '  factory AppState.initial() => AppState(look: ThemeState());\n'
        '}\n'
        'mixin Selectors {\n'
        '  SelectTheme get look => SelectTheme(state);\n'
        '}\n'
        'AppState r(AppState state) =>\n'
        '    state.copyWith(look: state.look.copyWith(x: 1));\n'
        'Object f() => look.mode;\n',
      );
    });

    test("somebody else's parameter, local or field of that name stays", () {
      // `MaterialApp(theme:)` names Flutter's parameter; the local is a
      // widget's `Theme.of(context)`. `rename theme appearance` renamed both.
      const source =
          'Widget a() => MaterialApp(theme: lightTheme());\n'
          'Widget b(BuildContext context) {\n'
          '  final theme = Theme.of(context);\n'
          '  return Text(style: theme.textTheme.body);\n'
          '}\n';
      expect(rename(source, field: field), source);
    });

    test('a view-model field of that name wins its file', () {
      // `vm.theme` and `theme.mode` sit in one connector; only the second is
      // the selector getter, and the view-model's field says which.
      expect(
        rename(
          'class F { Vm fromStore() => Vm(theme: theme.mode); }\n'
          'class Vm {\n'
          '  Vm({required this.theme});\n'
          '  final ThemeMode theme;\n'
          '}\n'
          'Widget build(Vm vm) => X(vm.theme);\n',
          field: field,
        ),
        'class F { Vm fromStore() => Vm(theme: look.mode); }\n'
        'class Vm {\n'
        '  Vm({required this.theme});\n'
        '  final ThemeMode theme;\n'
        '}\n'
        'Widget build(Vm vm) => X(vm.theme);\n',
      );
    });

    test('a class member of that name shadows it for the class', () {
      // dependencies.dart holds the connectivity *service* as `connectivity`.
      const source =
          'class Deps {\n'
          '  late final theme = ThemeService();\n'
          '  Future<void> start() => theme.start();\n'
          '}\n';
      expect(rename(source, field: field), source);
    });

    test('a comment reference follows, prose does not', () {
      expect(
        rename(
          '/// Reads [theme] and [theme.mode]; the theme is dark.\nclass X {}\n',
          field: field,
        ),
        '/// Reads [look] and [look.mode]; the theme is dark.\nclass X {}\n',
      );
    });
  });

  group('the strings a rename owns', () {
    test('a whole literal moves, one that contains it does not', () {
      // The narrowing: the old sweep rewrote the class name anywhere inside any
      // string, so a sentence mentioning it moved too.
      expect(
        rename(
          "const a = 'HomePage';\nconst b = 'Go to HomePage now';\n",
          literals: {'HomePage': 'LandingPage'},
        ),
        "const a = 'LandingPage';\nconst b = 'Go to HomePage now';\n",
      );
    });

    test('a route path carries its parameters', () {
      expect(
        rename(
          "const a = '/home';\nconst b = '/home/:id';\nconst c = '/homepage';\n",
          literals: {'/home': '/landing'},
        ),
        "const a = '/landing';\nconst b = '/landing/:id';\n"
        "const c = '/homepage';\n",
      );
    });

    test('a raw string keeps its r, a triple-quoted one its quotes', () {
      // Splicing past a one-character quote wrote `r/landing'` — source that
      // does not parse, out of a command whose whole promise is that it either
      // lands or does not.
      expect(
        rename(
          "const a = r'/home';\nconst b = '''HomePage''';\n",
          literals: {'/home': '/landing', 'HomePage': 'LandingPage'},
        ),
        "const a = r'/landing';\nconst b = '''LandingPage''';\n",
      );
      expect(
        rename('import r"log_in/x.dart";\n', moveOf: moveLogIn),
        'import r"sign_in/x.dart";\n',
      );
    });

    test('a directive URI is not also read as one of them', () {
      // Two rules over one literal would splice it twice at overlapping
      // offsets.
      expect(
        rename(
          "import 'log_in/x.dart';\n",
          moveOf: moveLogIn,
          literals: {'log_in/x.dart': 'nonsense'},
        ),
        "import 'sign_in/x.dart';\n",
      );
    });
  });
}
