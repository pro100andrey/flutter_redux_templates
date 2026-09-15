import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ast/positions.dart';
import '../../ast/source_index.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';
import '../text_bytes.dart';

/// A source file that search tools skip.
///
/// **Why the audit reports this and not the compiler.** A NUL byte is legal
/// Dart, invisible in an editor, and survives `dart format`. What it destroys
/// is findability: `grep`, `git grep` and ripgrep classify the file as binary
/// and skip it, so every symbol declared in it returns no hits — not a wrong
/// answer, an empty one, which reads as "this does not exist".
///
/// Measured, in this repository, on the CLI's own source: one NUL written as a
/// memo-key separator made `frx_workspace.dart` unsearchable, and
/// `notSubstateDirs`, `isSubstateDir`, `packageRootOf` and `_marker` returned
/// nothing anywhere. `dart analyze` was clean and 690 tests passed.
///
/// **This check would not have caught that one**, and saying so is the point:
/// `tools/` is the CLI's own source and no audited project contains it. The
/// repository-wide guard is [test/source_text_test.dart]. This check is the
/// half that serves a *created* project, where the same byte can arrive by a
/// paste from a terminal, a bad merge, or a generator that writes raw bytes.
///
/// Generated output is left out, and not for the usual reason. Asking for it
/// is a different listing key, so it would walk each package's `lib/` a second
/// time — the exact cost `doctor_test`'s "each package lib is walked once" was
/// written to hold. The repository-wide test covers generated files anyway,
/// because it enumerates git rather than the tree.
///
/// **It reads through the index, so the tree is read once.** The first version
/// took every file's bytes on top of the string `SourceIndex` hands the checks
/// after it — a second full read of the project on a path the editor re-runs on
/// every debounced event. Running first, it is the one that pays for the read,
/// and the checks after it get the cached string; the NUL is found in that
/// string at no extra cost.
///
/// Bytes are still read for the one file that cannot be decoded, because that
/// is the only way to say *where*. A file no editor will show you the problem
/// in is one you need an offset for, and it is at most one file per audit.
void checkSourceText(FrxWorkspace repo, List<Finding> into) {
  void report(
    File file,
    Unsearchable kind,
    int offset, {
    Position? at,
  }) => into.add(
    Finding.warn(
      '${p.relative(file.path, from: repo.root.path)} '
      '${describeUnsearchable(kind, offset)}',
      file: file.path,
      line: at?.line,
      column: at?.column,
    ),
  );

  for (final (:lib, package: _) in repo.sourceLibs()) {
    for (final file in sourceIndex.filesUnder(lib)) {
      final String source;
      try {
        source = sourceIndex.sourceOf(file);
      } on FileSystemException {
        // Not valid UTF-8, so there is no string to search. Now — and only now
        // — the bytes are worth reading, to name the offset.
        final bad = unsearchableIn(file.readAsBytesSync());
        report(file, bad?.kind ?? Unsearchable.notUtf8, bad?.offset ?? 0);
        continue;
      }

      // Written as an escape. Typing the byte itself is the very defect
      // this check reports, and doing it by accident is how it reached the
      // repository to begin with — three times now, counting the two while
      // this module was being written. The guard catches it every time.
      final at = source.indexOf('\u0000');
      if (at < 0) {
        continue;
      }
      // A code-unit index is not a byte offset, and the report promises bytes
      // because `xxd -s` is the tool that works on a file like this. Encoding
      // the prefix costs one allocation, on a file that has already failed.
      report(
        file,
        Unsearchable.nulByte,
        utf8.encode(source.substring(0, at)).length,
        // The byte offset is for `xxd`; the line is for the editor. Only the
        // decodable case has a line to name.
        at: positionInSource(source, at),
      );
    }
  }
}
