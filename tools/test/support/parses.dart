import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

/// Fails unless [source] is syntactically valid Dart.
///
/// Every other assertion frx makes about generated code is a substring match,
/// which checks that some text is present but never that the whole is
/// well-formed. That gap is not theoretical: `AppStateSource.wireSubstate`
/// spliced a parameter onto its neighbour (`logInrequired ProfileState`) and
/// every test kept passing, because each one only asked whether its own
/// fragment appeared.
///
/// This is the generic property those matches approximate. It catches fused
/// tokens, unbalanced delimiters and dropped separators in any generator at
/// once — including the ones nobody has written a test for yet.
///
/// Syntax only: a missing import or a wrong base class still needs its own
/// assertion.
void expectParses(String source, {String? reason}) {
  final errors = parseString(content: source, throwIfDiagnostics: false).errors;
  expect(
    errors,
    isEmpty,
    reason: [
      if (reason != null) reason,
      if (errors.isNotEmpty) errors.map((e) => '  $e').join('\n'),
      source,
    ].join('\n'),
  );
}
