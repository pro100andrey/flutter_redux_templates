import 'package:path/path.dart' as p;

import '../../ast/source_index.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Files the analyzer could only recover a tree from.
///
/// The reader tier is tolerant of unparseable source on purpose: one broken
/// file in somebody's repo must not take a whole audit down. The tolerance was
/// silent, and silence is the worse half of that bargain — every check before
/// it answers from whatever tree it was handed, and a file with a missing brace
/// has no `@RoutePage` as far as the route check can tell. So a broken file
/// used to make the audit *more* confident, not less: `✓ No issues found.`
///
/// **Bounded by what the audit read, and that is the accurate scope rather than
/// a compromise.** Sweeping the three lib trees to parse everything was tried:
/// it does report the broken action file that motivated this, and it costs 448
/// → 510 ms on the live monorepo *and* undoes the property `doctor_test`'s "the
/// pre-filter keeps most of the tree unparsed" pins — the placement sweep's
/// whole point. It is also answering a question that is not this one. A file no
/// check read cannot have corrupted a finding, the editor's Dart plugin already
/// flags syntax errors where the author is typing, and `frx graph` — which does
/// read every action file — reports the same file as an unresolved entry. What
/// frx uniquely knows is which of *its own* answers came from a guess.
///
/// **A warning, so the exit code stays 0.** One broken file in a cloned project
/// is the author's to fix, not a reason to fail their build.
void checkRecoveredFiles(FrxWorkspace repo, List<Finding> into) {
  for (final file in sourceIndex.recovered) {
    into.add(
      Finding.warn(
        '${p.relative(file.path)} does not parse — what this audit says about '
        'it was read off a recovered tree.',
        file: file.path,
      ),
    );
  }
}
