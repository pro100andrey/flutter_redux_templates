import 'package:path/path.dart' as p;

import '../../util/console.dart';

/// Names the files a removal leaves still saying the word it took away.
///
/// Both halves of a removal that edit a declaration — a field's, a selector's
/// — leave code elsewhere naming it, and neither rewrites that code: a reducer
/// that assigns the field, a connector that reads the getter, are somebody's
/// to fix. Named in the preview, at the moment of the decision, rather than
/// left to "run the audit" in the closing line, which does not say which
/// files.
///
/// [still] is the clause that says how — `Still names "tags"`, `Still reads
/// ".isWaiting"`. Silent when [files] is empty, so the block after it is not
/// followed by a gap where nothing was said.
void narrateLeftInPlace(String still, List<String> files) {
  if (files.isEmpty) {
    return;
  }
  console.out.writeln('$still (left in place, will not compile):');
  for (final f in files) {
    console.out.writeln('  ! ${p.relative(f)}');
  }
  console.out.writeln();
}
