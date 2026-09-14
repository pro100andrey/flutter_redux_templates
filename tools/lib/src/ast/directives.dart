/// Finding an import in an unresolved parse tree.
///
/// "Is this URI already imported" and "which directive imports it" were spelled
/// out in seven places across the editors — every one of them the same
/// `whereType<ImportDirective>()` over `unit.directives` and the same
/// `uri.stringValue == uri` — and the string-value spelling is the part that
/// matters: a URI written as an adjacent-string concatenation has a value and
/// no single token, and `uri.toSource()` would carry its quotes.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// The `import` directives of [unit], in source order.
List<ImportDirective> importsOf(CompilationUnit unit) =>
    unit.directives.whereType<ImportDirective>().toList();

/// The directive among [imports] whose URI is exactly [uri], or null.
ImportDirective? importNamed(Iterable<ImportDirective> imports, String uri) {
  for (final d in imports) {
    if (d.uri.stringValue == uri) {
      return d;
    }
  }
  return null;
}
