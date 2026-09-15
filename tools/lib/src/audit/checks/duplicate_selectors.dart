import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../redux/selectors_source.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Two getters on one facade computing the same thing.
///
/// **The residue of a refusal frx makes correctly.** `add-selector` will not
/// overwrite a name that is taken:
///
///     ⚠ SelectInvite.isWaiting is taken — left as it is. Add a reader by
///     hand under a name of your own.
///
/// — and doing exactly that leaves two getters with one body. Neither is wrong;
/// together they are a fact with two spellings, and the next change to the
/// state behind them has to remember both. Nothing recorded the pair, so
/// nothing said so.
///
/// A warning, and character-for-character: two getters that compute the same
/// thing by different routes are a judgement call frx has no business making,
/// and this project is a template people diverge from — a facade may
/// deliberately offer one reader under two names. What it must not do is offer
/// it twice by accident.
void checkDuplicateSelectors(FrxWorkspace repo, List<Finding> into) {
  final selectors = SelectorsSource(repo.selectorsFile);
  if (!selectors.exists) {
    return;
  }

  final where = p.relative(selectors.file.path);

  for (final entry in selectors.duplicateGetters().entries) {
    for (final names in entry.value) {
      // Anchored on the one the sentence says to remove.
      final offset = selectors.getterOffset(entry.key, names.last);
      final at = offset == null ? null : positionIn(selectors.unit, offset);
      into.add(
        Finding.warn(
          '$where — ${entry.key}: '
          '${names.map((n) => '`$n`').join(' and ')} have the same body, so '
          'they are one fact under ${names.length} names and a change to it '
          'has to find all of them. Usually what is left after `add-selector` '
          'declined a taken name and the reader was added by hand — keep the '
          'one the callers use and `frx remove ${entry.key}.${names.last} '
          '--kind selector`.',
          file: selectors.file.path,
          line: at?.line,
          column: at?.column,
        ),
      );
    }
  }
}
