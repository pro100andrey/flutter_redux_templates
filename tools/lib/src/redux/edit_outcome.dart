/// The outcome of an idempotent edit to one file: the whole edited source, what
/// changed, and whether anything did.
///
/// Nine result types in this tier carried exactly these three facts, under four
/// spellings of the boolean — `alreadyWired` for a registration,
/// `alreadyPresent` for a member, `found` for a removal, and
/// `alreadyPresent && !retyped` for an edit that rewrites what it finds.
/// Nothing named the shape, so every command holding one wrote the same two
/// derivations by hand: the change to apply (fifteen sites) and the block that
/// reports it (nine). Named, both are derived once, in `commands/wiring.dart`.
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
/// the four spellings that inverts, and inverting it back is a silent bug of
/// the worst kind: `unchanged => found` skips the edit in exactly the case that
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
/// the word their tests are written in, and `expect(unwired.found, isTrue)`
/// says what happened where `expect(unwired.unchanged, isFalse)` makes the
/// reader invert it in their head. Tests are callers too, so the criterion on
/// [Edited] — does anything read the specific word — does not stop applying
/// just because the caller is a test.
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
