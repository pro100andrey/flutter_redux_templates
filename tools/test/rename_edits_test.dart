import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';
import 'package:tools/src/ast/rename_edits.dart';
import 'package:tools/src/redux/ast_edit.dart';

/// Renaming a file's contents off the parse tree. See [RenameEdits] for what it
/// replaced; these are the cases that decide whether it is right.
void main() {
  String rename(
    String source, {
    Map<String, String> identifiers = const {},
    Map<String, String> paths = const {},
    Map<String, String> literals = const {},
  }) {
    final edits = RenameEdits(
      identifiers: identifiers,
      paths: paths,
      literals: literals,
    ).of(parseString(content: source, throwIfDiagnostics: false).unit);
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
      // `\\b` is what put `_LogInState` and `_\$LogInState` on different footings
      // in the first place; a comment should not be where that accident lives on.
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
    test('a folder segment and a basename both move', () {
      expect(
        rename(
          "import 'log_in/models/log_in_state.dart';\n"
          "part 'log_in_state.freezed.dart';\n",
          paths: {'log_in': 'sign_in', 'log_in_state': 'sign_in_state'},
        ),
        "import 'sign_in/models/sign_in_state.dart';\n"
        "part 'sign_in_state.freezed.dart';\n",
      );
    });

    test('a segment that merely starts with the token does not', () {
      expect(
        rename(
          "import 'log_input/thing.dart';\n",
          paths: {'log_in': 'sign_in'},
        ),
        "import 'log_input/thing.dart';\n",
      );
    });

    test('a URI written with double quotes keeps them', () {
      expect(
        rename('import "log_in/x.dart";\n', paths: {'log_in': 'sign_in'}),
        'import "sign_in/x.dart";\n',
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
        rename('import r"log_in/x.dart";\n', paths: {'log_in': 'sign_in'}),
        'import r"sign_in/x.dart";\n',
      );
    });

    test('a directive URI is not also read as one of them', () {
      // Two rules over one literal would splice it twice at overlapping offsets.
      expect(
        rename(
          "import 'log_in/x.dart';\n",
          paths: {'log_in': 'sign_in'},
          literals: {'log_in/x.dart': 'nonsense'},
        ),
        "import 'sign_in/x.dart';\n",
      );
    });
  });
}
