import '../util/console.dart';

/// The two-column table `list-substates` and `list-routes` print.
///
/// One layout, because the two are the same command asked of two facades: a
/// heading naming the file, the rows padded to the widest key, and a count.
/// Each had its own copy, and the copies agreed only because they were written
/// on the same afternoon.
///
/// [rows] pair the padded left column with the right one; [unit] is what the
/// count counts — `3 route(s).`.
void printInventory({
  required String title,
  required (String, String) columns,
  required List<(String, String)> rows,
  required String unit,
}) {
  console.out
    ..writeln(title)
    ..writeln();

  if (rows.isEmpty) {
    console.out.writeln('  (none found)');
    return;
  }

  final (left, right) = columns;
  final width = rows.fold(
    left.length,
    (w, r) => w > r.$1.length ? w : r.$1.length,
  );

  console.out
    ..writeln('  ${left.padRight(width)}  $right')
    ..writeln('  ${'-' * width}  ${'-' * 20}');
  for (final (key, value) in rows) {
    console.out.writeln('  ${key.padRight(width)}  $value');
  }
  console.out
    ..writeln()
    ..writeln('${rows.length} $unit(s).');
}
