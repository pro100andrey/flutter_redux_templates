import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../model/selector_shape.dart';
import '../ast/import_supply.dart';
import '../ast/source_index.dart';
import '../scaffold/type_imports.dart';
import 'ast_edit.dart';

/// The outcome of adding a getter to a `Select<Pascal>` extension type.
class SelectorsAddResult implements EditOutcome {
  const SelectorsAddResult({
    required this.source,
    required this.changes,
    required this.alreadyPresent,
    this.retyped = false,
  });

  /// The full edited `selectors.dart` source (unchanged if [alreadyPresent]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a getter of that name already existed on the type.
  final bool alreadyPresent;

  /// True when that getter's return type was rewritten — [alreadyPresent] is
  /// also true, and the file *did* change.
  final bool retyped;

  @override
  bool get unchanged => alreadyPresent && !retyped;
}

/// Reads and edits `business/lib/redux/selectors.dart` via the analyzer AST.
///
/// This repo exposes every substate's selectors through the `Selectors` mixin
/// in `selectors.dart` — a consumer mixes it in and reads `login.email` —
/// rather than through free functions. Wiring a substate means two edits here: a
/// `Select<Pascal> get <field>` on the mixin, and the new `extension type
/// Select<Pascal>` appended at the end, plus any imports the getters need.
///
/// It was three, against a `Select` extension type that carried the same getter
/// list and that nothing called. That type is gone from what `create` writes;
/// [wire] still extends one when it finds it, because a project made before the
/// collapse may read `state.select.<field>` in code frx did not write.
class SelectorsSource {
  SelectorsSource(this.file);

  final File file;

  /// The `selectors.dart` sitting next to [appState] in the redux directory.
  static SelectorsSource beside(File appState) =>
      SelectorsSource(File(p.join(appState.parent.path, 'selectors.dart')));

  bool get exists => file.existsSync();

  /// Wires a `Select<pascal>` selector type (given as [block], with its needed
  /// [imports]) into the facade for the substate field [field].
  ///
  /// Idempotent when a `Select<pascal>` type already exists — unless [force],
  /// in which case the stale block is replaced in place (the facade getters
  /// reference it by name and need no change), so a regenerated substate whose
  /// kind changed doesn't leave a now-incompatible selector behind.
  Edited wire({
    required String field,
    required String pascal,
    required String block,
    required List<String> imports,
    bool force = false,
  }) {
    final content = sourceIndex.sourceOf(file);
    final type = SelectorShape.typeFor(pascal);
    final unit = sourceIndex.unitFor(file);

    final existing = _extensionType(unit, type);
    if (existing != null && !force) {
      return Edited.nothing(content);
    }

    // One spine, so one getter. There used to be two — an `extension type
    // Select` carrying the same list as the mixin — and wiring a substate meant
    // keeping both in step. Nothing called the first: no consumer constructed a
    // `Selector` or read `.select`, so half of every substate's facade cost was
    // a list only this writer ever touched.
    //
    // A project scaffolded before that collapse still has the extension type,
    // and its screens may read `state.select.<field>` — one of the three ways
    // in that this repository documented until the collapse. So it is extended
    // when it is there: skipping it would leave `add-substate` reporting
    // success while `state.select.cart` did not exist, and the developer
    // meeting a compile error in code the tool had just claimed to wire.
    //
    // Nothing new grows one; `create` no longer writes it.
    final select = _extensionType(unit, SelectorShape.facadeType);
    final selectors = _mixin(unit, SelectorShape.mixinType);
    if (selectors == null) {
      throw StateError(
        'selectors.dart is missing the `${SelectorShape.mixinType}` mixin — '
        'cannot wire selectors automatically (${file.path}).',
      );
    }

    final edits = <Edit>[];
    final changes = <String>[];

    if (existing != null) {
      // force: swap the stale extension type body in place. The `Selectors`
      // getter already points at this type name, so it is left untouched.
      // (Imports the old kind needed but the new one doesn't are left as-is
      // rather than pruned.)
      edits.add(Edit.replace(existing.offset, existing.end, block.trimRight()));
      changes.add('extension type $type (replaced)');
    } else {
      // Fresh: add the facade getter just before the mixin's closing `}`
      // (node.end - 1, so we don't depend on a `rightBracket` accessor), and
      // append the new extension type at end of file.
      edits.add(
        Edit.insert(selectors.end - 1, '  $type get $field => $type(state);\n'),
      );
      changes.add('${SelectorShape.mixinType}.$field => $type(state)');
      if (select != null) {
        edits.add(
          Edit.insert(select.end - 1, '  $type get $field => $type(_state);\n'),
        );
        changes.add('${SelectorShape.facadeType}.$field => $type(_state)');
      }
      edits.add(Edit.insert(content.length, '\n$block'));
      changes.add('extension type $type');
    }

    // Imports the getters need, each inserted in sorted position within its
    // section (package/dart vs relative) so `directives_ordering` stays happy.
    final added = addImports(applyEdits(content, edits), imports);
    return Edited(
      source: added.source,
      changes: [...added.changes, ...changes],
    );
  }

  /// Edits that carry a retyped getter's type into the methods derived from it.
  ///
  /// `add-substate -k table` writes two members out of one fact:
  ///
  /// ```dart
  /// IMap<int, Object> get table => _state.tasks.table;
  /// Object byId(int id) => table[id]!;
  /// ```
  ///
  /// Retyping `table` to `IMap<int, Task>` left `byId` returning `Object`. It
  /// compiles — everything is an `Object` — so nothing failed; every caller
  /// simply had to cast, and the facade said the element type was unknown when
  /// the field above it said otherwise. `--force` promises "its selector getter
  /// to match", and a method that is that getter's own accessor is inside the
  /// promise however the sentence was worded.
  ///
  /// **Derived from the body, not from the name.** A method qualifies when it
  /// indexes the getter — `<getter>[…]` — which is the shape the scaffolder
  /// writes and the only one whose element type is knowable without resolution.
  /// A `byId` that reads something else is somebody's own, and is left alone.
  List<Edit> _accessorEdits(
    ExtensionTypeDeclaration ext,
    String getterName, {
    required String from,
    required String to,
  }) {
    final before = _typeArgsOf(from);
    final after = _typeArgsOf(to);
    // Both sides have to be the same shape of generic for a positional
    // correspondence between their arguments to mean anything.
    if (before == null || after == null || before.length != after.length) {
      return const [];
    }

    // A map, and only a map: the correspondence below is positional by *role*,
    // which is a fact about `IMap<K, V>` and not about generics in general.
    if (before.length != 2) return const [];
    final (oldKey, oldValue) = (before[0], before[1]);
    final (newKey, newValue) = (after[0], after[1]);

    final body = ext.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];

    final edits = <Edit>[];
    for (final member in members.whereType<MethodDeclaration>()) {
      if (member.isGetter || member.isSetter) continue;
      if (!_indexes(member.body.toSource(), getterName)) continue;

      // By role, never by value. Looking the old type up in the argument list
      // maps both of them to the first match when a map's key and value types
      // are the same: `IMap<int, int>` retyped to `IMap<String, Task>` turned
      // `int byId(int id)` into `String byId(String id)` over a `Task`-valued
      // map. The return type is the value; what indexes it is the key.
      void carry(TypeAnnotation? annotation, String from, String to) {
        if (annotation == null || from == to) return;
        if (annotation.toSource() != from) return;
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
      if (doc == null) continue;
      for (final token in doc.tokens) {
        for (final (from, to) in [(oldValue, newValue), (oldKey, newKey)]) {
          if (from == to) continue;
          final at = token.lexeme.indexOf('[$from]');
          if (at < 0) continue;
          edits.add(
            Edit.replace(
              token.offset + at + 1,
              token.offset + at + 1 + from.length,
              to,
            ),
          );
        }
      }
    }
    return edits;
  }

  /// Whether [source] indexes [getter] *itself* — a bare `getter[…]`, not
  /// `subgetter[…]` and not `something.getter[…]`.
  ///
  /// The substring test this replaces matched any name *ending* in the getter's,
  /// so a hand-written `_state.tasks.subtable[id]` counted as an accessor of
  /// `table` and was retyped over a collection that never changed.
  ///
  /// **A leading `.` disqualifies it too**, and that is not the same rule as the
  /// one above. `Object? labelFor(int id) => _state.labels.table[id];` written
  /// inside `SelectTasks` indexes *another slice's* identically-named
  /// collection; it survives `SelectTasks.table` and must not be judged by it.
  /// The cost of getting this wrong is asymmetric: in [_accessorEdits] a false
  /// positive rewrites a type annotation, in [removeSelector] it deletes a
  /// hand-written method and reports it as intended.
  static bool _indexes(String source, String getter) {
    for (
      var at = source.indexOf('$getter[');
      at >= 0;
      at = source.indexOf('$getter[', at + 1)
    ) {
      if (at == 0) return true;
      final before = source.codeUnitAt(at - 1);
      final isIdentifierChar =
          (before >= 0x30 && before <= 0x39) ||
          (before >= 0x41 && before <= 0x5A) ||
          (before >= 0x61 && before <= 0x7A) ||
          before == 0x5F || // _
          before == 0x24 || // $
          before == 0x2E; // . — a member of something else, not this getter
      if (!isIdentifierChar) return true;
    }
    return false;
  }

  /// `IMap<int, Task>` → `['int', 'Task']`; null when [type] is not generic.
  ///
  /// Split on depth, not on every comma: `IMap<int, IList<Task>>` has two
  /// arguments and three commas' worth of nesting between them.
  static List<String>? _typeArgsOf(String type) {
    final open = type.indexOf('<');
    if (open < 0 || !type.trimRight().endsWith('>')) return null;

    final inner = type.substring(open + 1, type.lastIndexOf('>'));
    final args = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (final rune in inner.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '<') depth++;
      if (ch == '>') depth--;
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

  /// Adds a `<returnType> get <getterName> => <expr>;` getter to the
  /// `Select<Pascal>` extension type (before its closing `}`) — a computed
  /// selector on an existing substate. Idempotent when a getter of that name is
  /// already present. Throws [StateError] when the type isn't there (the
  /// substate isn't wired).
  ///
  /// [imports] are whatever [returnType] needs to resolve here. A getter is
  /// written into a different library than the state it reads, so a type that
  /// the state file imports — `IList` and friends — is undefined in this one
  /// unless it is brought along.
  SelectorsAddResult addSelector({
    required String selectorType,
    required String getterName,
    required String returnType,
    required String expr,
    List<String> imports = const [],
    bool retype = false,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = sourceIndex.unitFor(file);
    final ext = _extensionType(unit, selectorType);
    if (ext == null) {
      throw StateError(
        '$selectorType not found in ${file.path} — is the substate wired? '
        '(see `frx list-substates`).',
      );
    }
    final existing = _getters(ext.body, getterName).firstOrNull;
    if (existing != null) {
      // Retyping touches the return type and nothing else. The body is the
      // author's — a getter whose expression was hand-written must not be
      // reverted to the generated one just because its field changed type, and
      // the field's own read (`_state.<field>.<name>`) is unaffected anyway.
      final declared = existing.returnType?.toSource();
      if (!retype || declared == null || declared == returnType) {
        return SelectorsAddResult(
          source: content,
          changes: const [],
          alreadyPresent: true,
        );
      }
      final edits = <Edit>[
        Edit.replace(
          existing.returnType!.offset,
          existing.returnType!.end,
          returnType,
        ),
      ];
      // The doc line `add-substate` writes names the type — `/// Returns
      // [IMap<int, Object>] table`. Left alone it says the opposite of the
      // signature above it, which is worse than saying nothing.
      final doc = existing.documentationComment;
      if (doc != null) {
        for (final token in doc.tokens) {
          final at = token.lexeme.indexOf(declared);
          if (at < 0) continue;
          edits.add(
            Edit.replace(
              token.offset + at,
              token.offset + at + declared.length,
              returnType,
            ),
          );
        }
      }
      edits.addAll(
        _accessorEdits(ext, getterName, from: declared, to: returnType),
      );
      final added = addImports(applyEdits(content, edits), imports);
      return SelectorsAddResult(
        source: added.source,
        changes: [
          '$selectorType.$getterName: $declared → $returnType',
          ...added.changes,
        ],
        alreadyPresent: true,
        retyped: true,
      );
    }

    final edits = <Edit>[];
    // Before the type's closing `}` (node.end - 1, matching how [wire] inserts
    // the facade getters), so `dart format` places it among the others.
    //
    // With the `///` line: every other getter in the facade carries one — the
    // four written by hand in the template and every one `add-substate`
    // scaffolds — and a getter arriving bare was this command disagreeing with
    // its own neighbours. No `[…]` reference in it, because `comment_references`
    // is on and a return type like `DateTime?` is not a resolvable one.
    edits.add(
      Edit.insert(
        ext.end - 1,
        '  /// Returns $getterName\n'
        '  $returnType get $getterName => $expr;\n',
      ),
    );

    final added = addImports(applyEdits(content, edits), imports);
    return SelectorsAddResult(
      source: added.source,
      changes: ['$selectorType.$getterName => $expr', ...added.changes],
      alreadyPresent: false,
    );
  }

  /// Shared package imports the selector facade may carry, each with what
  /// proves it is still needed. A block for a `search`/`table` substate pulls in
  /// fast_immutable_collections for its `IList`/`IMap` getters; once the last
  /// such block is gone the import is dead and must be pruned or it trips
  /// `unused_import`. Relative model imports are folder-scoped instead (see
  /// [unwire]).
  ///
  /// Asked of [TypeImports] rather than restated here. It was restated, and the
  /// two copies drifted the moment the second one was written: this file's
  /// pattern dropped the trailing `\b` so `IListConst` and `IMapOfSets` keep the
  /// import alive, the other kept it, and the same `selectors.dart` then got
  /// opposite answers depending on whether a field or a whole substate was
  /// removed. A new shared import needs one entry, in [TypeImports].
  static final Map<String, ImportProbe> _sharedImportProbes = {
    for (final uri in [TypeImports.fastImmutableCollections])
      if (TypeImports.probeFor(uri) case final probe?) uri: probe,
  };

  /// Removes the getter [getterName] from [selectorType], the methods derived
  /// from it, and any import in [prune] it was the last user of. The inverse of
  /// the getter half of [addSelector].
  ///
  /// `found: false` when the type or the getter is not there — a field removed
  /// with `--no-selector`, or one whose facade the project never grew, is not
  /// an error to report.
  ///
  /// [prune] is the caller's because the question is what the *field* needed,
  /// which is read off the declaration in the state file — a getter's own
  /// return type says the same thing here, but only one of the two callers is
  /// holding a repository to resolve a model import against.
  Unwired removeSelector({
    required String selectorType,
    required String getterName,
    Map<String, ImportProbe> prune = const {},
  }) {
    final content = sourceIndex.sourceOf(file);
    // Strict, like every other splice: see [StateSource.removeField].
    final unit = sourceIndex.unitToEdit(file);

    final ext = _extensionType(unit, selectorType);
    if (ext == null) return Unwired.absent(content);
    final getter = _getters(ext.body, getterName).firstOrNull;
    if (getter == null) return Unwired.absent(content);

    final edits = <Edit>[removeDeclaration(content, getter)];
    final changes = <String>['$selectorType.$getterName'];
    // What the removal takes away, read while it is still there: the imports
    // this file no longer needs are the ones whose only reason was one of these
    // names. [prune] answers for the types the caller knows about; this answers
    // for the rest, which on a real facade is most of them — a `wait` selector
    // is keyed on an action *type*, so the read layer imports one file of the
    // write layer per waiting getter, and taking the getter out left the import.
    final removed = {...namesIn(getter)};

    // The accessors derived from it go too: `Object byId(int id) =>
    // table[id]!;` does not compile once `table` is gone, and a facade left
    // like that is the half-job this command exists to avoid. Same rule
    // [_accessorEdits] retypes by — a method qualifies by *indexing* the
    // getter, so a `byId` that reads something else is somebody's own and
    // stays.
    for (final member in _members(ext.body).whereType<MethodDeclaration>()) {
      if (member.isGetter || member.isSetter) continue;
      if (!_indexes(member.body.toSource(), getterName)) continue;
      edits.add(removeDeclaration(content, member));
      changes.add('$selectorType.${member.name.lexeme}()');
      removed.addAll(namesIn(member));
    }

    final pruned = pruneImports(applyEdits(content, edits), prune);
    final unused = pruneUnusedImports(
      pruned.source,
      file: file,
      removedNames: removed,
    );
    return Unwired(
      source: unused.source,
      changes: [...changes, ...pruned.changes, ...unused.changes],
    );
  }

  /// Removes a substate's selectors: the `Select<Pascal>` extension type, the
  /// two facade getters (`Select.<field>` and `Selectors.<field>`), the model
  /// import scoped to that substate's folder ([snake]), and any shared package
  /// import (see [_sharedImportProbes]) left unused once the block is gone. The
  /// inverse of [wire]; `found: false` when no `Select<Pascal>` type exists.
  Unwired unwire({
    required String field,
    required String pascal,
    required String snake,
  }) {
    final content = sourceIndex.sourceOf(file);
    final type = SelectorShape.typeFor(pascal);
    final unit = sourceIndex.unitFor(file);

    final existing = _extensionType(unit, type);
    if (existing == null) {
      return Unwired.absent(content);
    }

    final edits = <Edit>[removeDeclaration(content, existing)];
    final changes = <String>['extension type $type'];
    final removed = {...namesIn(existing)};

    // The facade getter that pointed at the removed type, from wherever it is.
    // The mixin is where one is written now; the `Select` extension type is
    // checked as well because a project scaffolded before the spine collapsed
    // still has one, and unwiring has to leave that project compiling too.
    final select = _extensionType(unit, SelectorShape.facadeType);
    final selectors = _mixin(unit, SelectorShape.mixinType);
    for (final getter in [
      if (select != null) ..._getters(select.body, field),
      if (selectors != null) ..._getters(selectors.body, field),
    ]) {
      edits.add(removeDeclaration(content, getter));
      changes.add('getter $field');
      removed.addAll(namesIn(getter));
    }

    // The model import, scoped to this substate's folder (`<snake>/models/…`).
    // Match the leading folder segment, not any segment — a substate named for a
    // shared directory (`models`, `actions`) would otherwise prune every other
    // substate's `foo/models/…` import. Unique to the substate, so unconditional.
    for (final imp in unit.directives.whereType<ImportDirective>()) {
      final uri = imp.uri.stringValue ?? '';
      if (uri.startsWith('$snake/')) {
        edits.add(removeDirective(content, imp));
        changes.add("import '$uri'");
      }
    }

    // Apply the structural removals, then prune shared package imports that no
    // other selector references anymore. [pruneImports] re-parses, so the
    // "still used?" check runs against the post-removal text.
    final pruned = pruneImports(
      applyEdits(content, edits),
      _sharedImportProbes,
    );
    // And whatever else the block was the only reason for — the action files a
    // waiting getter named, a package that supplied one return type. Same rule
    // the getter path uses, so the two cannot give this file opposite answers.
    final unused = pruneUnusedImports(
      pruned.source,
      file: file,
      removedNames: removed,
    );

    return Unwired(
      source: unused.source,
      changes: [...changes, ...pruned.changes, ...unused.changes],
    );
  }

  Iterable<MethodDeclaration> _getters(ClassBody body, String name) =>
      _members(body).whereType<MethodDeclaration>().where(
        (m) => m.isGetter && m.name.lexeme == name,
      );

  List<ClassMember> _members(ClassBody body) =>
      body is BlockClassBody ? body.members : const <ClassMember>[];

  /// The members of [selectorType] that still read [getterName] and are not the
  /// derived accessors [removeSelector] takes with it.
  ///
  /// The facade is the one file of this architecture the guard *allows* a hand
  /// edit to, precisely because a selector whose body needs statements is
  /// written by hand — so a sibling reading the getter is normal, and it is not
  /// frx's to delete. This repository's own template ships one:
  ///
  /// ```dart
  /// String? get token => _state.session.token;
  /// bool get isAvailable => token != null;
  /// ```
  ///
  /// Removing `token` and reporting success left `isAvailable` reading a
  /// declaration that was gone, and `SelectComposites.canEnterApp` sits on top
  /// of it — so the `business` package stopped compiling, including the
  /// `build_runner` step the plan's own closing line prescribes.
  /// Getters that share a body with another getter on the same facade, grouped
  /// by that body: `{'SelectInvite': [['isWaiting', 'isFinding']]}`.
  ///
  /// **A duplicate is what a *refusal* leaves behind, and the refusal is
  /// right.** `add-selector` will not overwrite a name that is taken — it says
  /// so and stops — and the next move is to add the reader by hand under a name
  /// of your own. Do that and both exist: two spellings of one fact, and
  /// changing the state behind them means remembering there were two. Nothing
  /// in the tree records that they are the same.
  ///
  /// Compared on the body's source text, normalised for whitespace only. That
  /// is narrow on purpose: two getters that compute the same thing differently
  /// are a judgement call, and reporting one would be frx having an opinion
  /// about somebody's code. Two that are character-for-character identical are
  /// not a judgement call.
  Map<String, List<List<String>>> duplicateGetters() {
    final out = <String, List<List<String>>>{};
    for (final ext
        in sourceIndex
            .unitFor(file)
            .declarations
            .whereType<ExtensionTypeDeclaration>()) {
      final byBody = <String, List<String>>{};
      for (final m in _members(ext.body).whereType<MethodDeclaration>()) {
        if (!m.isGetter) continue;
        final body = m.body.toSource().replaceAll(RegExp(r'\s+'), ' ').trim();
        if (body.isEmpty) continue;
        byBody.putIfAbsent(body, () => []).add(m.name.lexeme);
      }
      final groups = [
        for (final names in byBody.values)
          if (names.length > 1) names,
      ];
      if (groups.isNotEmpty) out[ext.namePart.typeName.lexeme] = groups;
    }
    return out;
  }

  List<String> readersOf({
    required String selectorType,
    required String getterName,
  }) {
    final unit = sourceIndex.unitFor(file);
    final ext = _extensionType(unit, selectorType);
    if (ext == null) return const [];

    final names = <String>[];
    for (final member in _members(ext.body).whereType<MethodDeclaration>()) {
      if (member.isGetter && member.name.lexeme == getterName) continue;
      final body = member.body.toSource();
      // The accessors written from the getter go with it; every other reader
      // is somebody's own and is reported instead.
      if (_indexes(body, getterName)) continue;
      if (!_reads(body, getterName)) continue;
      names.add(
        member.isGetter ? member.name.lexeme : '${member.name.lexeme}()',
      );
    }
    return names;
  }

  /// Whether [source] reads [name] as a bare identifier — `token != null`, and
  /// not `_state.session.token`, which names the state's field rather than this
  /// getter and survives the getter's removal.
  static bool _reads(String source, String name) {
    for (final match in RegExp(
      '\\b${RegExp.escape(name)}\\b',
    ).allMatches(source)) {
      if (match.start == 0 || source[match.start - 1] != '.') return true;
    }
    return false;
  }

  ExtensionTypeDeclaration? _extensionType(CompilationUnit unit, String name) {
    for (final d in unit.declarations) {
      if (d is ExtensionTypeDeclaration && d.namePart.typeName.lexeme == name) {
        return d;
      }
    }
    return null;
  }

  MixinDeclaration? _mixin(CompilationUnit unit, String name) {
    for (final d in unit.declarations) {
      if (d is MixinDeclaration && d.name.lexeme == name) return d;
    }
    return null;
  }
}
