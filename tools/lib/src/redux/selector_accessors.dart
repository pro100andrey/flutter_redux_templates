/// The methods a selector facade derives from one of its getters, and how a
/// change to the getter is carried into them.
///
/// `add-substate -k table` writes two members out of one fact:
///
/// ```dart
/// IMap<int, Object> get table => _state.tasks.table;
/// Object byId(int id) => table[id]!;
/// ```
///
/// The second is an *accessor* of the first: it exists because the getter
/// does, its types are the getter's type arguments, and it stops compiling
/// the moment the getter goes. So a retype of `table` reaches `byId`, and a
/// removal of `table` takes `byId` with it — both by the same rule, stated
/// here once so the two edits cannot disagree about which methods are the
/// getter's own.
///
/// **Derived from the body, not from the name.** A method qualifies when it
/// indexes the getter — `<getter>[…]` — which is the shape the scaffolder
/// writes and the only one whose element type is knowable without resolution.
/// A `byId` that reads something else is somebody's own, and is left alone.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'ast_edit.dart';

/// The non-getter methods of [ext] written from [getter] — the ones that
/// index it.
Iterable<MethodDeclaration> derivedAccessorsOf(
  ExtensionTypeDeclaration ext,
  String getter,
) => ext.body.members.whereType<MethodDeclaration>().where(
  (m) => !m.isGetter && !m.isSetter && indexesGetter(m.body.toSource(), getter),
);

/// Edits that carry a retyped getter's type into the methods derived from it.
///
/// Retyping `table` to `IMap<int, Task>` left `byId` returning `Object`. It
/// compiles — everything is an `Object` — so nothing failed; every caller
/// simply had to cast, and the facade said the element type was unknown when
/// the field above it said otherwise. `--force` promises "its selector getter
/// to match", and a method that is that getter's own accessor is inside the
/// promise however the sentence was worded.
List<Edit> accessorRetypeEdits(
  ExtensionTypeDeclaration ext,
  String getterName, {
  required String from,
  required String to,
}) {
  final before = typeArgumentsOf(from);
  final after = typeArgumentsOf(to);
  // Both sides have to be the same shape of generic for a positional
  // correspondence between their arguments to mean anything.
  if (before == null || after == null || before.length != after.length) {
    return const [];
  }

  // A map, and only a map: the correspondence below is positional by *role*,
  // which is a fact about `IMap<K, V>` and not about generics in general.
  if (before.length != 2) {
    return const [];
  }
  final (oldKey, oldValue) = (before[0], before[1]);
  final (newKey, newValue) = (after[0], after[1]);

  final edits = <Edit>[];
  for (final member in derivedAccessorsOf(ext, getterName)) {
    // By role, never by value. Looking the old type up in the argument list
    // maps both of them to the first match when a map's key and value types
    // are the same: `IMap<int, int>` retyped to `IMap<String, Task>` turned
    // `int byId(int id)` into `String byId(String id)` over a `Task`-valued
    // map. The return type is the value; what indexes it is the key.
    void carry(TypeAnnotation? annotation, String from, String to) {
      if (annotation == null || from == to) {
        return;
      }
      if (annotation.toSource() != from) {
        return;
      }
      edits.add(Edit.replace(annotation.offset, annotation.end, to));
    }

    carry(member.returnType, oldValue, newValue);
    final params = member.parameters?.parameters ?? const <FormalParameter>[];
    // Optional and named parameters are `RegularFormalParameter` here too —
    // this analyzer carries the default on a `defaultClause` rather than in
    // a wrapper node — so `byId({required int id})` is reached like any
    // other, and is not left half-migrated with its key type behind.
    for (final parameter in params.whereType<RegularFormalParameter>()) {
      carry(parameter.type, oldKey, newKey);
    }

    // The doc line names the type too — `/// Returns [Object] value by id`.
    final doc = member.documentationComment;
    if (doc == null) {
      continue;
    }

    for (final (from, to) in [(oldValue, newValue), (oldKey, newKey)]) {
      if (from == to) {
        continue;
      }
      edits.addAll(docRetypeEdits(doc, from: from, to: to, bracketed: true));
    }
  }

  return edits;
}

/// Edits that rewrite the first [from] on each line of [doc] to [to] — the
/// `[from]` reference when [bracketed], the bare text otherwise.
///
/// The doc line `add-substate` writes names the type — `/// Returns
/// [IMap<int, Object>] table`, `/// Returns [Object] value by id`. Left alone
/// after a retype it says the opposite of the signature under it, which is
/// worse than saying nothing.
List<Edit> docRetypeEdits(
  Comment doc, {
  required String from,
  required String to,
  bool bracketed = false,
}) {
  final needle = bracketed ? '[$from]' : from;
  final inset = bracketed ? 1 : 0;
  final edits = <Edit>[];
  for (final token in doc.tokens) {
    final at = token.lexeme.indexOf(needle);
    if (at < 0) {
      continue;
    }

    final start = token.offset + at + inset;
    edits.add(Edit.replace(start, start + from.length, to));
  }
  return edits;
}

/// Whether [source] indexes [getter] *itself* — a bare `getter[…]`, not
/// `subgetter[…]` and not `something.getter[…]`.
///
/// The substring test this replaces matched any name *ending* in the
/// getter's, so a hand-written `_state.tasks.subtable[id]` counted as an
/// accessor of `table` and was retyped over a collection that never changed.
///
/// **A leading `.` disqualifies it too**, and that is not the same rule as
/// the one above. `Object? labelFor(int id) => _state.labels.table[id];`
/// written inside `SelectTasks` indexes *another slice's* identically-named
/// collection; it survives `SelectTasks.table` and must not be judged by it.
/// The cost of getting this wrong is asymmetric: in [accessorRetypeEdits] a
/// false positive rewrites a type annotation, in a removal it deletes a
/// hand-written method and reports it as intended.
bool indexesGetter(String source, String getter) {
  for (
    var at = source.indexOf('$getter[');
    at >= 0;
    at = source.indexOf('$getter[', at + 1)
  ) {
    if (at == 0) {
      return true;
    }

    final before = source.codeUnitAt(at - 1);
    final isIdentifierChar =
        (before >= 0x30 && before <= 0x39) ||
        (before >= 0x41 && before <= 0x5A) ||
        (before >= 0x61 && before <= 0x7A) ||
        before == 0x5F || // _
        before == 0x24 || // $
        before == 0x2E; // . — a member of something else, not this getter
    if (!isIdentifierChar) {
      return true;
    }
  }

  return false;
}

/// `IMap<int, Task>` → `['int', 'Task']`; null when [type] is not generic.
///
/// Split on depth, not on every comma: `IMap<int, IList<Task>>` has two
/// arguments and three commas' worth of nesting between them.
List<String>? typeArgumentsOf(String type) {
  final open = type.indexOf('<');
  if (open < 0 || !type.trimRight().endsWith('>')) {
    return null;
  }

  final inner = type.substring(open + 1, type.lastIndexOf('>'));
  final args = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  for (final rune in inner.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '<') {
      depth++;
    }

    if (ch == '>') {
      depth--;
    }

    if (ch == ',' && depth == 0) {
      args.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }

    buffer.write(ch);
  }
  args.add(buffer.toString().trim());

  return args;
}
