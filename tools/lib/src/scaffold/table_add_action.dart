import 'package:analyzer/dart/analysis/utilities.dart';

import '../ast/directives.dart';
import '../redux/ast_edit.dart';

/// The `Add<Pascal>Action` a table substate is scaffolded with, retyped to
/// what its table now holds.
///
/// `add-substate -k table` writes the table as `IMap<int, Object>` and the
/// action that fills it in the same placeholder, and the way to name the model
/// is `add-field <slice> 'table:IMap<int, Task>' --force`. That retyped the
/// state and the facade and left the action building an `IMap<int, Object>`
/// to `addAll` into an `IMap<int, Task>` — which does not compile, while
/// doctor said ✓. The action is scaffolding frx wrote in a shape it knows, so
/// it follows; one that no longer has that shape is somebody's, and is left.
abstract final class TableAddAction {
  const TableAddAction._();

  /// `IMap<K, V>` split into its key and value types, or null for anything
  /// else — a table typed some other way has no action shape to follow.
  static ({String key, String value})? tableTypes(String type) {
    final m = _map.firstMatch(type.trim());
    return m == null ? null : (key: m[1]!.trim(), value: m[2]!.trim());
  }

  /// [source] with its placeholders retyped to [key] and [value], and
  /// [imports] added where missing — or null when [source] carries none of the
  /// scaffold's placeholders any more.
  static String? retype(
    String source, {
    required String key,
    required String value,
    List<String> imports = const [],
  }) {
    if (!_placeholders.any((p) => p.hasMatch(source))) {
      return null;
    }

    final retyped = source
        .replaceAll(_items, 'IList<$value> _items')
        .replaceAll(_byId, 'IMap<$key, $value>.fromValues')
        .replaceAll(_idOf, '$key _idOf($value item)')
        .replaceAll(
          '// TODO(frx): replace `Object` with your model type and return its '
              'int id.',
          '// TODO(frx): return the $key id of a $value.',
        );

    final existing = importsOf(
      parseString(content: retyped, throwIfDiagnostics: false).unit,
    );
    final edits = [
      for (final uri in {...imports})
        if (importNamed(existing, uri) == null) importInsertion(existing, uri),
    ];
    return applyEdits(retyped, edits);
  }

  static final _map = RegExp(r'^IMap<\s*([^,<>]+?)\s*,\s*(.+)>$');
  static final _items = RegExp(r'IList<\s*Object\s*>\s+_items');
  static final _byId = RegExp(r'IMap<\s*int\s*,\s*Object\s*>\s*\.fromValues');
  static final _idOf = RegExp(r'int\s+_idOf\(\s*Object\s+item\s*\)');
  static final List<RegExp> _placeholders = [_items, _byId, _idOf];
}
