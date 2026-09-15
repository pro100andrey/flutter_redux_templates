/// Where an offset falls, as an editor counts.
///
/// The audit's findings anchored on a file and nothing finer, so the editor
/// squiggled every one of them on line 1 — a route with no connector, a
/// duplicate getter, a `with` clause in the wrong order, all at the top of a
/// file that might be four hundred lines long. The trees the checks read carry
/// the offsets already; this is the one conversion, so no check does it its
/// own way.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

/// A 1-based line and column, the way `file:line:column` is read.
typedef Position = ({int line, int column});

/// The position of [offset] in the text [unit] was parsed from.
Position positionIn(CompilationUnit unit, int offset) =>
    _at(unit.lineInfo, offset);

/// The position of [offset] in [source], for a caller holding text and no
/// tree.
Position positionInSource(String source, int offset) =>
    _at(LineInfo.fromContent(source), offset);

Position _at(LineInfo lines, int offset) {
  final at = lines.getLocation(offset);
  return (line: at.lineNumber, column: at.columnNumber);
}
