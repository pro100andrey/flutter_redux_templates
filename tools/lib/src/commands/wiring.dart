import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../redux/ast_edit.dart';
import '../util/console.dart';

/// One file a wiring command edits, and what happened to it.
///
/// The six commands that scaffold an artifact *and* wire it into existing
/// source each derived two things from the same three facts, by hand:
///
/// ```dart
/// // the change — fifteen sites across the tier
/// wire.alreadyWired ? null : EditFile(f.path, before: f.readAsStringSync(), after: wire.source)
///
/// // the report — nine near-verbatim closures
/// console.out.writeln('Router (${p.relative(f.path)}):');
/// if (wire.alreadyWired) { console.out.writeln('  • … already registered — wiring skipped.'); }
/// else { for (final c in wire.changes) console.out.writeln('  + $c'); }
/// ```
///
/// Both are derived from [EditOutcome], which every source module in the AST
/// tier already returns. What stays at the call site is only what genuinely
/// differs: how this command names the file, and what it says when there was
/// nothing to do.
class Wiring {
  const Wiring(
    this.file,
    this.outcome, {
    required this.heading,
    this.skipped,
    this.headingWhenSkipped = true,
    this.way = WiringWay.wired,
  });

  /// A wiring headed by the file's own path, relative to the working directory.
  ///
  /// What the commands that edit *one named file* print — `add-field` and
  /// `add-selector` — and the reason the convention is here rather than in each
  /// of them: three call sites spelled out `p.relative`, the trailing colon and
  /// nothing else, so the trailing colon was a thing three files agreed on by
  /// having been written on the same afternoon.
  /// No `way`, unlike [Wiring.of]: nothing unwires a file named by its bare
  /// path. `remove` names all three of its files by what they are.
  Wiring.at(File file, EditOutcome outcome, {String? skipped})
    : this(
        file,
        outcome,
        heading: '${p.relative(file.path)}:',
        skipped: skipped,
      );

  /// A wiring headed by what the file *is*, with its path in brackets —
  /// `Router (app/lib/navigation/app_router.dart):`.
  ///
  /// The form the commands that edit a *facade* print, where the path alone
  /// would not say which of the three it is.
  Wiring.of(
    String label,
    File file,
    EditOutcome outcome, {
    String? skipped,
    WiringWay way = WiringWay.wired,
  }) : this(
         file,
         outcome,
         heading: '$label (${p.relative(file.path)}):',
         skipped: skipped,
         way: way,
       );

  /// The file [outcome] edits.
  final File file;

  /// What the source module made of it.
  final EditOutcome outcome;

  /// The line above the change list.
  ///
  /// Two shapes cover eight of the nine blocks, and each has a constructor —
  /// [Wiring.at] for a file named by its path, [Wiring.of] for one named by
  /// what it is. Given directly only by `add-nav`, which prints paths relative
  /// to the repo root where every other command prints them relative to the
  /// working directory.
  final String heading;

  /// What to say when there was nothing to do.
  ///
  /// Null prints nothing at all — `add-nav`'s page half is silent when the page
  /// already has the callback, because its connector half has just said so.
  final String? skipped;

  /// Whether [skipped] comes under [heading].
  ///
  /// False for a skip line that names the artifact rather than a member of it —
  /// `add-nav` says "LogInPage already has `onTapHome` — nothing to do.", where
  /// the path above would add nothing. The other eight say "field \"logIn\"
  /// already present", which is only readable with the file named above it.
  final bool headingWhenSkipped;

  /// Which way this wiring goes, and so which bullet its changes carry.
  final WiringWay way;

  /// Whether this wiring has nothing to write and nothing to say.
  bool get silent => outcome.unchanged && skipped == null;

  /// The change this outcome implies, or null when the file already said it.
  EditFile? get edit => outcome.editTo(file);

  /// Prints the block, with no blank line after it.
  ///
  /// The spacing is the caller's because the callers disagree: four separate
  /// their blocks with a blank line (see [WiringList.narrate]), `add-field`
  /// interleaves notes between them, and `add-nav` runs its two together.
  void narrate() {
    if (outcome.unchanged) {
      if (silent) return;
      if (headingWhenSkipped) console.out.writeln(heading);
      console.out.writeln('  • $skipped');
      return;
    }
    console.out.writeln(heading);
    for (final change in outcome.changes) {
      console.out.writeln('  ${way.bullet} $change');
    }
  }
}

/// Which way a wiring goes, and so which bullet its report uses.
///
/// One character apart, and that was enough for `remove` to grow its own copy
/// of the block: the heading, the change list and the "nothing to do" line are
/// otherwise identical to the six that add.
enum WiringWay {
  /// Something was added to the file.
  wired('+'),

  /// Something was taken away from it.
  unwired('-');

  const WiringWay(this.bullet);

  final String bullet;
}

/// The change an outcome implies for the file it was computed from.
///
/// Below [Wiring], because not every caller has a block to print: the audit's
/// orphan fixer writes files and says one line about the folder, never a block
/// per file, and had spelled the construction out for want of anywhere to get
/// it from.
///
/// Reading the file here rather than at the call site is what keeps `before:`
/// honest — it is read at plan time, from the same file `after:` was computed
/// from.
extension OutcomeAsChange on EditOutcome {
  EditFile? editTo(File file) => unchanged
      ? null
      : EditFile(file.path, before: file.readAsStringSync(), after: source);
}

/// A whole command's wiring: its changes, and its report.
extension WiringList on List<Wiring> {
  /// The edits to apply, in declared order, skipping what was already wired.
  Iterable<EditFile> get edits sync* {
    for (final w in this) {
      final edit = w.edit;
      if (edit != null) yield edit;
    }
  }

  /// Narrates every block, each followed by a blank line.
  ///
  /// A [Wiring.silent] one gets no blank line either, so a wiring with nothing
  /// to say leaves no gap where its report would have been.
  void narrate() {
    for (final w in this) {
      if (w.silent) continue;
      w.narrate();
      console.out.writeln();
    }
  }
}
