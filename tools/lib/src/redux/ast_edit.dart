import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// The outcome of an idempotent edit to one file: the whole edited source, what
/// changed, and whether anything did.
///
/// Nine result types in this tier carried exactly these three facts, under four
/// spellings of the boolean — `alreadyWired` for a registration,
/// `alreadyPresent` for a member, `found` for a removal, and `alreadyPresent &&
/// !retyped` for an edit that rewrites what it finds. Nothing named the shape,
/// so every command holding one wrote the same two derivations by hand: the
/// change to apply (fifteen sites) and the block that reports it (nine). Named,
/// both are derived once, in `commands/wiring.dart`.
///
/// Four of the nine are gone, measured against their callers rather than
/// assumed: see [Edited]. Three survive, and each earns it — `RouteWireResult`
/// and `RouteUnwireResult` carry `warnings`, which reaches the editor through
/// `plan_view.ts`, and `SelectorsAddResult` carries `alreadyPresent`, which two
/// commands read and which is *not* `unchanged`: a retyped selector is present
/// and changed at once.
abstract interface class EditOutcome {
  /// The full source after the edit — byte-identical to the original when
  /// [unchanged].
  String get source;

  /// Human-readable descriptions of the edits made. Empty when [unchanged].
  List<String> get changes;

  /// True when the file already said what the edit would have said, so there is
  /// nothing to write.
  ///
  /// The one name for what the results spell four ways. Which word is right
  /// depends on what the edit was doing — a route is *wired*, a getter is
  /// *present*, and an unwiring's is *found* — and no caller deriving a change
  /// from it cares which. Each result keeps its own word, because that is the
  /// one its producer knows; this is the one its consumers need.
  bool get unchanged;
}

/// An [EditOutcome] with nothing to add to the three facts.
///
/// The results that predate [EditOutcome] each named their boolean after what
/// they were adding — `alreadyWired`, `alreadyPresent`, `found` — because each
/// was the only outcome its module returned, and its callers read that word. A
/// module whose callers do not returns this instead of making another class for
/// the same three fields.
///
/// **The criterion was stated here and never checked against the callers.**
/// Measured: `.found` had no production reader across three classes, `.retyped`
/// none at all, and `.alreadyWired` exactly one — `add_nav_command`, reading it
/// to pick a closing line, where `unchanged` says the same thing. Four classes
/// were repeating [Edited] verbatim. Re-measure before adding a fifth.
class Edited implements EditOutcome {
  /// [changes] is required and not defaulted: a changed outcome with nothing to
  /// report is a block in the report with no lines under it, which reads as a
  /// file edited for no reason.
  const Edited({required this.source, required this.changes})
    : unchanged = false;

  /// The file already said it: [source] is what it says now, and nothing is to
  /// be written.
  const Edited.nothing(this.source) : changes = const [], unchanged = true;

  @override
  final String source;

  @override
  final List<String> changes;

  @override
  final bool unchanged;
}

/// An [EditOutcome] that took something away rather than adding it.
///
/// A mixin and not one-line getters on each result because this is the one of
/// the four spellings that inverts, and inverting it back is a silent bug of the
/// worst kind: `unchanged => found` skips the edit in exactly the case that
/// needed one, and the report says "nothing to unwire" about a field that is
/// still there. Written once, no unwire result can get it wrong.
mixin Unwiring implements EditOutcome {
  /// True when what was to be removed was there.
  bool get found;

  @override
  bool get unchanged => !found;
}

/// An [Unwiring] with nothing to add to the three facts — what [Edited] is for
/// a wiring.
///
/// It exists rather than folding the unwirings into [Edited] because `found` is
/// the word their tests are written in, and `expect(unwired.found, isTrue)` says
/// what happened where `expect(unwired.unchanged, isFalse)` makes the reader
/// invert it in their head. Tests are callers too, so the criterion on [Edited]
/// — does anything read the specific word — does not stop applying just because
/// the caller is a test.
class Unwired with Unwiring {
  /// What was named was there, and [changes] describe taking it out.
  const Unwired({required this.source, required this.changes}) : found = true;

  /// Nothing of that name was there, so there was nothing to remove and
  /// [source] is the file as it stands.
  const Unwired.absent(this.source) : changes = const [], found = false;

  @override
  final String source;

  @override
  final List<String> changes;

  @override
  final bool found;
}

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
/// `valueString? nickname`, `LogInRoute.nameHomeRoute.name`. The result does not
/// parse, and nothing downstream of the splice notices. Appending *after* the
/// last element with a leading comma is correct in both shapes; only an empty
/// list has to insert before [closer].
///
/// Pass [before] to insert ahead of a particular element instead, for a list
/// with a member that has to stay last (`wait` on `AppState`).
///
/// This rule was discovered independently three times and missed twice before it
/// lived here; [removeListItem] is its inverse.
Edit insertIntoList({
  required Iterable<AstNode> elements,
  required Token closer,
  required String element,
  AstNode? before,
}) {
  if (before != null) return Edit.insert(before.offset, '$element, ');
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
  var lineStart = start;
  while (lineStart > 0 &&
      (source[lineStart - 1] == ' ' || source[lineStart - 1] == '\t')) {
    lineStart--;
  }
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
    if (lineEnd < source.length && source[lineEnd] == '\r') lineEnd++;
    if (lineEnd < source.length && source[lineEnd] == '\n') lineEnd++;
    return Edit.replace(lineStart, lineEnd, '');
  }
  return Edit.replace(start, end, '');
}

/// Removes a whole top-level [directive] (e.g. an `import`), consuming the line
/// break that follows so no blank line is left behind.
Edit removeDirective(String source, Directive directive) {
  var end = directive.end;
  if (end < source.length && source[end] == '\r') end++;
  if (end < source.length && source[end] == '\n') end++;
  return Edit.replace(directive.offset, end, '');
}

/// Removes a whole declaration [node] (a class member or a top-level
/// declaration) along with the indentation before it on its line and the line
/// break after it, so it lifts out without leaving a blank line.
Edit removeDeclaration(String source, AstNode node) {
  var start = node.offset;
  while (start > 0 && (source[start - 1] == ' ' || source[start - 1] == '\t')) {
    start--;
  }
  var end = node.end;
  if (end < source.length && source[end] == '\r') end++;
  if (end < source.length && source[end] == '\n') end++;
  return Edit.replace(start, end, '');
}

/// Where to splice a new `import '$uri';`, keeping it sorted within its section:
/// `dart:`/`package:` imports sort together above relative ones.
///
/// Note: sorting is by `String.compareTo` (UTF-16 code units), which matches
/// `directives_ordering` for the lowercase `package:`/snake_case paths this tool
/// generates; a pre-existing import with uppercase/digit segments could be
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
  // Section empty: no imports at all → start of file; a package import leads the
  // existing (relative-only) block; a relative import starts a new block below.
  if (imports.isEmpty) return Edit.insert(0, "import '$uri';\n");
  return incomingIsPackage
      ? Edit.insert(imports.first.offset, "import '$uri';\n")
      : Edit.insert(imports.last.end, "\n\nimport '$uri';");
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
/// `package:freezed_annotation/…` put both before `freezed_annotation` at offset
/// 0, and emitted `fast_immutable_collections` above `collection`.
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
    final directives = parseString(
      content: result,
      throwIfDiagnostics: false,
    ).unit.directives.whereType<ImportDirective>().toList();
    if (directives.any((d) => d.uri.stringValue == uri)) continue;
    result = applyEdits(result, [importInsertion(directives, uri)]);
    changes.add("import '$uri';");
  }
  return (source: result, changes: changes);
}
