import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../model/selector_shape.dart';
import '../ast/source_index.dart';
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
/// This repo exposes every substate's selectors through the `Select` /
/// `Selectors` extension-type facade in `selectors.dart` (so callers reach them
/// as `state.select.<field>`), rather than through free functions. Wiring a
/// substate means three edits here: a `Select<Pascal> get <field>` on the
/// `Select` extension type, the same on the `Selectors` mixin, and the new
/// `extension type Select<Pascal>` appended at the end — plus any imports the
/// getters need.
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

    final select = _extensionType(unit, SelectorShape.facadeType);
    final selectors = _mixin(unit, SelectorShape.mixinType);
    if (select == null || selectors == null) {
      throw StateError(
        'selectors.dart is missing the `Select` extension type or `Selectors` '
        'mixin — cannot wire selectors automatically (${file.path}).',
      );
    }

    final edits = <Edit>[];
    final changes = <String>[];

    // Imports the getters need, each inserted in sorted position within its
    // section (package/dart vs relative) so `directives_ordering` stays happy.
    final importDirs = unit.directives.whereType<ImportDirective>().toList();
    final present = importDirs.map((d) => d.uri.stringValue).toSet();
    for (final uri in imports.where((u) => !present.contains(u))) {
      edits.add(importInsertion(importDirs, uri));
      changes.add("import '$uri';");
    }

    if (existing != null) {
      // force: swap the stale extension type body in place. The `Select` /
      // `Selectors` getters already point at this type name, so they're left
      // untouched. (Imports the old kind needed but the new one doesn't are
      // left as-is rather than pruned.)
      edits.add(Edit.replace(existing.offset, existing.end, block.trimRight()));
      changes.add('extension type $type (replaced)');
    } else {
      // Fresh: add the two facade getters just before each declaration's closing
      // `}` (node.end - 1, so we don't depend on a `rightBracket` accessor), and
      // append the new extension type at end of file.
      edits.add(
        Edit.insert(select.end - 1, '  $type get $field => $type(_state);\n'),
      );
      changes.add('Select.$field => $type(_state)');
      edits.add(
        Edit.insert(selectors.end - 1, '  $type get $field => $type(state);\n'),
      );
      changes.add('Selectors.$field => $type(state)');
      edits.add(Edit.insert(content.length, '\n$block'));
      changes.add('extension type $type');
    }

    return Edited(source: applyEdits(content, edits), changes: changes);
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
      final changes = <String>[
        '$selectorType.$getterName: $declared → $returnType',
      ];
      final importDirs = unit.directives.whereType<ImportDirective>().toList();
      final present = importDirs.map((d) => d.uri.stringValue).toSet();
      for (final uri in imports.where((u) => !present.contains(u))) {
        edits.add(importInsertion(importDirs, uri));
        changes.add("import '$uri';");
      }
      return SelectorsAddResult(
        source: applyEdits(content, edits),
        changes: changes,
        alreadyPresent: true,
        retyped: true,
      );
    }

    final edits = <Edit>[];
    final changes = <String>['$selectorType.$getterName => $expr'];
    final importDirs = unit.directives.whereType<ImportDirective>().toList();
    final present = importDirs.map((d) => d.uri.stringValue).toSet();
    for (final uri in imports.where((u) => !present.contains(u))) {
      edits.add(importInsertion(importDirs, uri));
      changes.add("import '$uri';");
    }
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

    return SelectorsAddResult(
      source: applyEdits(content, edits),
      changes: changes,
      alreadyPresent: false,
    );
  }

  /// Shared package imports the selector facade may carry, mapped to a symbol
  /// that proves one is still needed. A block for a `search`/`table` substate
  /// pulls in fast_immutable_collections for its `IList`/`IMap` getters; once
  /// the last such block is gone the import is dead and must be pruned or it
  /// trips `unused_import`. Relative model imports are folder-scoped instead
  /// (see [unwire]); this registry is only for shared package imports, so a new
  /// one added to a selector block needs an entry here.
  static const _sharedImportProbes = {
    'package:fast_immutable_collections/fast_immutable_collections.dart': [
      'IList',
      'IMap',
      'ISet',
    ],
  };

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

    // The two facade getters that pointed at the removed type.
    final select = _extensionType(unit, SelectorShape.facadeType);
    final selectors = _mixin(unit, SelectorShape.mixinType);
    for (final getter in [
      if (select != null) ..._getters(select.body, field),
      if (selectors != null) ..._getters(selectors.body, field),
    ]) {
      edits.add(removeDeclaration(content, getter));
      changes.add('getter $field');
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
    // other selector references anymore. Re-parsed (not offset-spliced) so the
    // "still used?" check runs against the post-removal text.
    var source = applyEdits(content, edits);
    final surviving = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit;
    // The non-import body — pruning imports never changes it, so compute it once
    // and search it for each probe symbol (the import line can't self-match).
    // Collect all prune edits against the same parse and apply them in one
    // batch: applyEdits splices highest-offset-first, so several disjoint import
    // removals stay correct (a per-import applyEdits loop would use stale
    // offsets after the first splice).
    final body = _withoutImports(source, surviving);
    final pruneEdits = <Edit>[];
    for (final imp in surviving.directives.whereType<ImportDirective>()) {
      final probes = _sharedImportProbes[imp.uri.stringValue ?? ''];
      if (probes == null) continue;
      // Prefix match (no trailing boundary) so `IList` also covers the const
      // constructors `IListConst` / `IMapConst`.
      if (!probes.any((s) => RegExp('\\b$s').hasMatch(body))) {
        pruneEdits.add(removeDirective(source, imp));
        changes.add("import '${imp.uri.stringValue}'");
      }
    }

    return Unwired(
      source: pruneEdits.isEmpty ? source : applyEdits(source, pruneEdits),
      changes: changes,
    );
  }

  /// [source] with its import directives blanked out, so a symbol search for
  /// "is this import still used?" can't match an import line itself.
  String _withoutImports(String source, CompilationUnit unit) =>
      applyEdits(source, [
        for (final imp in unit.directives.whereType<ImportDirective>())
          Edit.replace(imp.offset, imp.end, ''),
      ]);

  Iterable<MethodDeclaration> _getters(ClassBody body, String name) {
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];
    return members.whereType<MethodDeclaration>().where(
      (m) => m.isGetter && m.name.lexeme == name,
    );
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
