/// Character-offset splices over a source string, and the list, declaration
/// and import edits every editor in this tier is built from.
///
/// The outcomes those editors return live in `edit_outcome.dart` and are
/// exported from here, because that is where every caller found them.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../ast/directives.dart';
import 'app_state_source.dart' show AppStateSource;
import 'selectors_source.dart' show SelectorsSource;

export 'edit_outcome.dart';

/// A text edit over a source string: replace `[start, end)` with [text].
/// An insertion is the degenerate case where `start == end`.
///
/// Shared by [AppStateSource] and [SelectorsSource] so the splice invariant
/// (apply highest-offset-first) lives in exactly one place.
class Edit {
  const Edit.insert(int at, this.text) : start = at, end = at;
  const Edit.replace(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

/// Applies [edits] to [source], highest `start` first so earlier offsets stay
/// valid as later ones are spliced. Edits must not overlap.
String applyEdits(String source, List<Edit> edits) {
  final sorted = [...edits]..sort((a, b) => b.start.compareTo(a.start));
  var result = source;
  for (final e in sorted) {
    result = result.replaceRange(e.start, e.end, e.text);
  }
  return result;
}

/// Splices [element] into a comma-separated list — formal parameters, arguments
/// or collection elements — at an offset that stays valid whether or not the
/// list already carries a trailing comma.
///
/// Inserting *at* [closer] is the trap this exists to close. A list whose last
/// element has no trailing comma — `{String? value}`, or a single-element set
/// that `dart format` collapsed onto one line — fuses with the new text:
/// `valueString? nickname`, `LogInRoute.nameHomeRoute.name`. The result does
/// not parse, and nothing downstream of the splice notices. Appending *after*
/// the last element with a leading comma is correct in both shapes; only an
/// empty list has to insert before [closer].
///
/// Pass [before] to insert ahead of a particular element instead, for a list
/// with a member that has to stay last (`wait` on `AppState`).
///
/// This rule was discovered independently three times and missed twice before
/// it lived here; [removeListItem] is its inverse.
Edit insertIntoList({
  required Iterable<AstNode> elements,
  required Token closer,
  required String element,
  AstNode? before,
}) {
  if (before != null) {
    return Edit.insert(before.offset, '$element, ');
  }
  final last = elements.isEmpty ? null : elements.last;
  return last == null
      ? Edit.insert(closer.offset, '$element,')
      : Edit.insert(last.end, ', $element');
}

/// Removes [node] from a comma-separated list (formal parameters, arguments, or
/// collection/set elements), taking one adjacent comma with it so the list
/// stays syntactically valid. Prefers the trailing comma; falls back to a
/// leading one; a lone element is removed on its own. When the item occupied a
/// line by itself (as formatted multi-line lists put each element), the leading
/// indentation and trailing line break go too, so no blank line is left behind.
/// The inverse of the list insertions done by the `wire*` methods.
Edit removeListItem(String source, AstNode node) {
  var start = node.offset;
  var end = node.end;
  final after = node.endToken.next;
  final before = node.beginToken.previous;
  if (after != null && after.lexeme == ',') {
    end = after.end;
  } else if (before != null && before.lexeme == ',') {
    start = before.offset;
  }

  // If nothing but whitespace precedes [start] and follows [end] on their
  // lines, the element stood alone — swallow that whole line.
  final lineStart = indentationStart(source, start);
  final atLineStart = lineStart == 0 || source[lineStart - 1] == '\n';
  var lineEnd = end;
  while (lineEnd < source.length &&
      (source[lineEnd] == ' ' || source[lineEnd] == '\t')) {
    lineEnd++;
  }
  final atLineEnd =
      lineEnd >= source.length ||
      source[lineEnd] == '\n' ||
      source[lineEnd] == '\r';
  if (atLineStart && atLineEnd) {
    return Edit.replace(lineStart, pastLineBreak(source, lineEnd), '');
  }
  return Edit.replace(start, end, '');
}

/// Removes a whole top-level [directive] (e.g. an `import`), consuming the line
/// break that follows so no blank line is left behind.
Edit removeDirective(String source, Directive directive) =>
    Edit.replace(directive.offset, pastLineBreak(source, directive.end), '');

/// Removes a whole declaration [node] (a class member or a top-level
/// declaration) along with the indentation before it on its line and the line
/// break after it, so it lifts out without leaving a blank line.
Edit removeDeclaration(String source, AstNode node) => Edit.replace(
  indentationStart(source, node.offset),
  pastLineBreak(source, node.end),
  '',
);

/// The offset where the spaces and tabs running up to [at] begin — [at] itself
/// when nothing but text precedes it.
///
/// What a removal backs over so the line's indentation goes with the thing it
/// indented; four removals in this tier each wrote the loop.
int indentationStart(String source, int at) {
  var start = at;
  while (start > 0 && (source[start - 1] == ' ' || source[start - 1] == '\t')) {
    start--;
  }
  return start;
}

/// The offset just past the line break at [at], if one is there — `\r\n` as
/// one — or [at] itself.
int pastLineBreak(String source, int at) {
  var end = at;
  if (end < source.length && source[end] == '\r') {
    end++;
  }
  if (end < source.length && source[end] == '\n') {
    end++;
  }
  return end;
}

/// Where to splice a new `import '$uri';`, keeping it sorted within its
/// section: `dart:`/`package:` imports sort together above relative ones.
///
/// Note: sorting is by `String.compareTo` (UTF-16 code units), which matches
/// `directives_ordering` for the lowercase `package:`/snake_case paths this
/// tool generates; a pre-existing import with uppercase/digit segments could be
/// ordered slightly differently.
Edit importInsertion(List<ImportDirective> imports, String uri) {
  bool isPackage(String u) => u.startsWith('dart:') || u.startsWith('package:');
  final incomingIsPackage = isPackage(uri);

  final section = imports
      .where((d) => isPackage(d.uri.stringValue ?? '') == incomingIsPackage)
      .toList();

  // Before the first same-section import that sorts after us.
  for (final d in section) {
    if ((d.uri.stringValue ?? '').compareTo(uri) > 0) {
      return Edit.insert(d.offset, "import '$uri';\n");
    }
  }
  // Otherwise after the last import already in our section.
  if (section.isNotEmpty) {
    return Edit.insert(section.last.end, "\nimport '$uri';");
  }
  // Section empty: no imports at all → start of file; a package import leads
  // the existing (relative-only) block; a relative import starts a new block
  // below.
  if (imports.isEmpty) {
    return Edit.insert(0, "import '$uri';\n");
  }
  return incomingIsPackage
      ? Edit.insert(imports.first.offset, "import '$uri';\n")
      : Edit.insert(imports.last.end, "\n\nimport '$uri';");
}

/// Whether an import is still needed by the source it was pruned from, given
/// that source with its own import block blanked out.
///
/// A predicate rather than a pattern because the two questions it answers are
/// not the same shape. "Does anything still say `IList`" is a regex; "does
/// anything still name a type that lives in `result.dart`" is a lookup against
/// the project — a sealed union's cases sit in the file its union names, and no
/// pattern derived from the URI alone knows that.
typedef ImportProbe = bool Function(String body);

/// Removes each import [probes] names that nothing outside the import block
/// still needs — the inverse of [addImports], for an edit that took the last
/// user of a type away.
///
/// An import with no entry in [probes] is left alone, so this can only ever
/// prune what a caller has claimed to understand — pruning by "does the name
/// appear" alone would take `freezed_annotation` out of every file, since
/// nothing spells `FreezedAnnotation`.
///
/// The probe runs against [source] with its import directives blanked out: an
/// import line names its own type, and matching that would keep every import
/// alive forever. Every removal is computed against one parse and applied in
/// one batch, because [applyEdits] splices highest-offset-first and a
/// per-import apply loop would carry stale offsets after the first splice.
({String source, List<String> changes}) pruneImports(
  String source,
  Map<String, ImportProbe> probes,
) {
  if (probes.isEmpty) {
    return (source: source, changes: const []);
  }

  final imports = importsOf(
    parseString(content: source, throwIfDiagnostics: false).unit,
  );
  final body = applyEdits(source, [
    for (final imp in imports) Edit.replace(imp.offset, imp.end, ''),
  ]);

  final edits = <Edit>[];
  final changes = <String>[];
  for (final imp in imports) {
    final uri = imp.uri.stringValue ?? '';
    final probe = probes[uri];
    if (probe == null || probe(body)) {
      continue;
    }
    edits.add(removeDirective(source, imp));
    changes.add("import '$uri'");
  }

  return edits.isEmpty
      ? (source: source, changes: const [])
      : (source: applyEdits(source, edits), changes: changes);
}

/// Adds every one of [uris] that [source] does not already import, and reports
/// the ones it added.
///
/// One re-parse per import, which is the whole point. [importInsertion] places
/// an import among the ones it can see, so two insertions computed against the
/// same parse can name the same offset — and then which of them lands first is
/// whatever tie [applyEdits] happened to break, not sorted order. Adding
/// `package:collection/collection.dart` and
/// `package:fast_immutable_collections/…` to a file importing only
/// `package:freezed_annotation/…` put both before `freezed_annotation` at
/// offset 0, and emitted `fast_immutable_collections` above `collection`.
///
/// `NavSource` and `RoutesSource` each learned this and re-parse in place; four
/// other call sites did not. This is that rule, stated once.
///
/// Runs *after* the structural edits, never before: every structural offset in
/// this tier points into a body below the import block, and an import spliced
/// in first moves it.
({String source, List<String> changes}) addImports(
  String source,
  Iterable<String> uris,
) {
  var result = source;
  final changes = <String>[];
  for (final uri in uris) {
    final directives = importsOf(
      parseString(content: result, throwIfDiagnostics: false).unit,
    );
    if (importNamed(directives, uri) != null) {
      continue;
    }
    result = applyEdits(result, [importInsertion(directives, uri)]);
    changes.add("import '$uri';");
  }
  return (source: result, changes: changes);
}
