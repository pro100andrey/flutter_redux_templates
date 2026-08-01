import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
import '../workspace/frx_workspace.dart';
import 'ast_edit.dart';

/// One line of the persistor's change log: the field it compares, and the name
/// it prints when that field moved.
class ChangedEntry {
  const ChangedEntry({
    required this.field,
    required this.label,
    required this.node,
  });

  /// The `AppState` field the condition tests — `prev.logIn != next.logIn`.
  final String field;

  /// The string beside it, which is what the log line actually says.
  final String label;

  /// Where it sits, so it can be removed or relabelled.
  final CollectionElement node;

  /// Whether the line prints the name of the field it is about.
  ///
  /// False is the shape a rename used to leave behind: the field renamed by the
  /// sweep, the string beside it not, because a string literal is exactly what
  /// the sweep is careful not to touch.
  bool get agrees => field == label;
}

/// Reads and edits the substate change log in `business/lib/redux/store.dart`.
///
/// The block is one line per `AppState` field:
///
/// ```dart
/// pending.changed = <String>[
///   if (prev.connectivity != next.connectivity) 'connectivity',
///   if (prev.logIn != next.logIn) 'logIn',
/// ];
/// ```
///
/// The same parallel list as the `AppState` field and the selectors facade
/// getter — and frx wired both of those and did not know this one existed, so
/// `frx add-substate cart` left it eight entries long and the audit said
/// nothing. A substate added by frx was invisible to the trace from the moment
/// it was created.
///
/// **A developer-facing trace, not behaviour.** The list feeds one log line
/// (`Δ connectivity, logIn`). Getting it wrong costs nobody a crash; it costs
/// the person reading the log a wrong answer, which is the failure this
/// repository already treats as worth catching everywhere else.
///
/// **Opt-in, like the docs export.** A project that deleted the block, or never
/// had it, gets no findings and no edits: [changed] returns null and every edit
/// is a no-op.
class StoreSource {
  StoreSource(this.file);

  final File file;

  /// Path of `store.dart` relative to the repo root.
  static const _relativePath = 'business/lib/redux/store.dart';

  /// Whether [path] is the store of the monorepo at [root].
  ///
  /// Asked rather than reconstructed: `rename` sweeps every file and needs to
  /// know when it is holding this one, and having it rebuild the path from a
  /// constant would put "where the store lives" in two places.
  static bool owns(String path, {required String root}) =>
      p.equals(path, p.join(root, _relativePath));

  /// The `store.dart` of an already-resolved workspace.
  ///
  /// No `locate`: nothing looks for a project *by* its store, and walking up
  /// from a root already resolved is how a reader ends up outside the repo it
  /// was pointed at.
  static StoreSource of(FrxWorkspace repo) =>
      StoreSource(File(p.join(repo.root.path, _relativePath)));

  bool get exists => file.existsSync();

  /// The block, or null when this project has none frx can act on.
  ///
  /// Recognised by shape rather than by the names around it — a list literal
  /// whose *every* element is `if (a.<field> != b.<field>) '<label>'`, assigned
  /// to something. Keying on `pending.changed` or on `prev`/`next` would tie frx
  /// to identifiers a clone is free to rename.
  ///
  /// **Two candidates is no candidate.** Shape alone is not a unique key: a
  /// helper elsewhere in the file can rhyme with it, and taking the first in
  /// traversal order is a coin flip that loses silently — measured, a decoy
  /// declared above the observer took `add-substate`'s entry and turned the
  /// audit into nine bogus findings. Ambiguity is reported by
  /// [checkChangeLog], not resolved by position.
  ///
  /// An empty list is not the block either: there is nothing in it to
  /// recognise, and a monorepo with no substates has nothing to trace.
  List<ChangedEntry>? changed() {
    final blocks = _blocks();
    return blocks.length == 1 ? _entriesOf(blocks.single) : null;
  }

  /// Whether more than one list in the file has the block's shape.
  ///
  /// The state in which frx does nothing and says why, rather than guessing.
  bool get ambiguous => _blocks().length > 1;

  List<ListLiteral> _blocks() =>
      exists ? _blocksIn(sourceIndex.unitFor(file)) : const [];

  /// Adds an entry for [field], after the last one.
  ///
  /// Last is `AppState` order: the factory keeps `wait` at the end and appends
  /// every substate before it, so a new field is always the newest of the ones
  /// this list tracks.
  EditOutcome wire({required String field}) => _edit((entries, source, list) {
    if (entries.any((e) => e.field == field)) return null;
    final (prev, next) = _operandsOf(entries.first);
    return (
      edits: [
        insertIntoList(
          elements: [for (final e in entries) e.node],
          closer: list.rightBracket,
          element: "if ($prev.$field != $next.$field) '$field'",
        ),
      ],
      changes: ["changed: '$field'"],
    );
  });

  /// Takes the entry for [field] away, matching on either half.
  ///
  /// Either half, because a stale label is exactly the state this list gets
  /// into: removing `logIn` should also take away the line still *printing*
  /// `logIn` after its field was renamed.
  EditOutcome unwire({required String field}) => _edit((entries, source, list) {
    final gone = entries
        .where((e) => e.field == field || e.label == field)
        .toList();
    if (gone.isEmpty) return null;
    return (
      edits: [for (final e in gone) removeListItem(source, e.node)],
      changes: [for (final e in gone) "changed: '${e.label}'"],
    );
  });

  /// Makes the entry that now tests [field] print [field] rather than [was].
  ///
  /// Takes the source instead of reading it, because its one caller has already
  /// rewritten the file in memory: `rename` sweeps `prev.logIn` → `prev.signIn`
  /// across the tree and hands the result here, where the string beside it is
  /// still the old name. Reading from disk would relabel the pre-sweep text and
  /// throw the sweep away.
  ///
  /// Deliberately narrow — only an entry whose label is exactly [was] moves —
  /// so a line a project labelled something else on purpose is left alone.
  /// Returns [content] unchanged when there is nothing to do, which includes a
  /// project with no such block at all.
  static String relabel(
    String content, {
    required String was,
    required String field,
  }) {
    final blocks = _blocksIn(
      parseString(content: content, throwIfDiagnostics: false).unit,
    );
    if (blocks.length != 1) return content;
    final stale = _entriesOf(
      blocks.single,
    )!.where((e) => e.field == field && e.label == was);
    if (stale.isEmpty) return content;
    return applyEdits(content, [
      for (final e in stale)
        Edit.replace(
          _labelOf(e.node)!.offset,
          _labelOf(e.node)!.end,
          "'$field'",
        ),
    ]);
  }

  /// Runs [plan] against the block, when there is exactly one.
  ///
  /// The two edits that work on disk differ only in what they compute; finding
  /// the block, declining when there is none to act on, and splicing are the
  /// same both times.
  EditOutcome _edit(
    ({List<Edit> edits, List<String> changes})? Function(
      List<ChangedEntry> entries,
      String source,
      ListLiteral list,
    )
    plan,
  ) {
    if (!exists) return const Edited.nothing('');
    final source = sourceIndex.sourceOf(file);
    final blocks = _blocksIn(sourceIndex.unitToEdit(file));
    if (blocks.length != 1) return Edited.nothing(source);
    final list = blocks.single;
    final planned = plan(_entriesOf(list)!, source, list);
    return planned == null
        ? Edited.nothing(source)
        : Edited(
            source: applyEdits(source, planned.edits),
            changes: planned.changes,
          );
  }

  /// Every list literal in [unit] shaped like the change log.
  ///
  /// The one place the recognition rule lives — read, edited and relabelled
  /// through it, so the three can never disagree about what the block is.
  static List<ListLiteral> _blocksIn(CompilationUnit unit) {
    final found = <ListLiteral>[];
    unit.accept(_ChangeLogs(found));
    return found;
  }

  /// The entries of [list], or null when it is not the change log.
  ///
  /// Every element must fit, not merely some: a list that mixes the shape with
  /// anything else is somebody else's list that happens to rhyme.
  static List<ChangedEntry>? _entriesOf(ListLiteral list) {
    if (list.elements.isEmpty) return null;
    final entries = <ChangedEntry>[];
    for (final element in list.elements) {
      final entry = _entryOf(element);
      if (entry == null) return null;
      entries.add(entry);
    }
    return entries;
  }

  static ChangedEntry? _entryOf(CollectionElement element) {
    if (element is! IfElement) return null;
    final test = element.expression;
    if (test is! BinaryExpression || test.operator.lexeme != '!=') return null;
    final left = _fieldOf(test.leftOperand);
    final right = _fieldOf(test.rightOperand);
    if (left == null || left != right) return null;
    final label = _labelOf(element);
    if (label == null || element.elseElement != null) return null;
    return ChangedEntry(field: left, label: label.value, node: element);
  }

  /// The field named by `prev.logIn`, or null for anything else.
  static String? _fieldOf(Expression e) =>
      e is PrefixedIdentifier ? e.identifier.name : null;

  static SimpleStringLiteral? _labelOf(CollectionElement element) {
    final then = (element as IfElement).thenElement;
    return then is SimpleStringLiteral ? then : null;
  }

  /// The two sides an entry compares — `prev` and `next`, whatever the observer
  /// called them. Read off the block rather than assumed, because the names are
  /// the clone's to choose.
  static (String, String) _operandsOf(ChangedEntry entry) {
    final test = ((entry.node as IfElement).expression) as BinaryExpression;
    return (
      (test.leftOperand as PrefixedIdentifier).prefix.name,
      (test.rightOperand as PrefixedIdentifier).prefix.name,
    );
  }
}

/// Collects the list literals shaped like the change log.
///
/// Being *bound* to something is part of the shape rather than decoration: the
/// block is a value the observer hands over, either straight into the pending
/// record or through a local on the way. A returned one is excluded, which is
/// the form a rhyming helper takes most often.
///
/// Both bindings, and not only the assignment: with only the assignment, a
/// project that wrote `final changed = <String>[…]; pending.changed = changed;`
/// had no block at all — indistinguishable from opting out — and a lone
/// rhyming assignment elsewhere in the file then silently *became* the block
/// and took `add-substate`'s entry.
class _ChangeLogs extends RecursiveAstVisitor<void> {
  _ChangeLogs(this._into);

  final List<ListLiteral> _into;

  void _consider(Expression? bound) {
    if (bound is ListLiteral && StoreSource._entriesOf(bound) != null) {
      _into.add(bound);
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _consider(node.rightHandSide);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _consider(node.initializer);
    super.visitVariableDeclaration(node);
  }
}
