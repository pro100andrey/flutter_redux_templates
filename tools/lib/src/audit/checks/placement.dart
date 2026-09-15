import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../ast/source_index.dart';
import '../../ast/vm_reader.dart';
import '../../model/placement.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Code that is wired, compiles, and sits in the wrong place.
///
/// **Warnings, never errors, and silenceable per rule.** False positives here
/// are guaranteed by construction rather than by accident: this template is
/// cloned and diverged from on purpose, and a check that can be wrong about
/// someone else's project must not fail their build. That keeps faith with the
/// posture the audit already takes — reporting non-defects buries the real
/// findings.
///
/// **No automatic fix.** A placement fix is a move, and a deliberately placed
/// file is exactly the false positive being accepted here — an automatic move
/// would "fix" somebody's decision.
void checkPlacement(FrxWorkspace repo, List<Finding> into) {
  for (final f in placementFindings(repo, silenced: _silencedIn(repo))) {
    into.add(
      Finding.warn(
        f.message,
        file: f.file,
        rule: f.rule.id,
        line: f.line,
        column: f.column,
      ),
    );
  }
}

/// The rules the project turned off in its `.frxrc`.
Set<PlacementRule> _silencedIn(FrxWorkspace repo) => {
  for (final e in repo.config.placement.entries)
    if (!e.value) ?PlacementRule.byId(e.key),
};

/// A view-model that compares on fewer fields than it holds.
///
/// A value field outside equality is a lie in `==`: two view-models with
/// different values compare equal, so the connector's rebuild never reaches the
/// widget and the screen shows the old value. The reader for this existed for
/// months with no consumer, reading `equatable`'s `props` getter while every
/// view-model here states its equality in `super(equals: […])` — so it read an
/// empty list eight times out of eight and could never have fired.
///
/// **Nothing in this template is reported, and that is expected.** All eight
/// were written correctly, once, by somebody who knew: ten of the eleven fields
/// outside equality are callbacks, which the idiom excludes on purpose, and the
/// eleventh is a dialog that writes its own `==` and says why. The check is for
/// the app grown from the clone, where a field added six months later is not
/// added to the list beside it.
///
/// **A warning with no fix.** Which field belongs in equality is the author's
/// call — a deliberately excluded one is a real design, and a remedy that
/// guessed would be editing an intention.
void checkViewModels(FrxWorkspace repo, List<Finding> into) {
  const rule = PlacementRule.fieldOutsideEquality;
  if (_silencedIn(repo).contains(rule)) {
    return;
  }
  for (final dir in [repo.appLib, repo.uiLib]) {
    if (!dir.existsSync()) {
      continue;
    }
    for (final file in sourceIndex.filesUnder(dir)) {
      // Same bargain the placement sweep strikes: a textual pre-filter decides
      // whether to look, never what to report. A file with neither shape cannot
      // hold a view-model that states an equality.
      final source = sourceIndex.sourceOf(file);
      if (!source.contains('equals:') && !source.contains('get props')) {
        continue;
      }
      final unit = sourceIndex.unitFor(file);
      for (final vm in viewModelsOfFile(file)) {
        for (final field in vm.fieldsOutsideEquality) {
          final at = field.offset == null
              ? null
              : positionIn(unit, field.offset!);
          // Two ways to be uncompared, and telling a reader which one saves the
          // argument. A field absent from the list is an oversight; a field
          // present only as `ids.length` is a decision that does not do what it
          // looks like — and calling that one "outside the equality" when it is
          // spelled right there reads as the tool not having looked.
          final how = vm.comparedOnlyDerived(field)
              ? 'is compared only through something derived from it, so two of '
                    'them differing in it but not in that derived value '
                    'compare '
                    'equal and the rebuild is lost.'
              : 'is outside the equality it declares, so two of them differing '
                    'only in it compare equal and the rebuild is lost.';
          into.add(
            Finding.warn(
              '${p.relative(file.path)} — ${vm.className}.${field.name} '
              '(${field.type}) $how',
              file: file.path,
              rule: rule.id,
              line: at?.line,
              column: at?.column,
            ),
          );
        }
      }
    }
  }
}
