import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';

import '../ast/declarations.dart';
import '../ast/source_index.dart';
import 'ast_edit.dart';

/// Reads and edits a substate's `@freezed` state model — inserting a new field
/// into its redirecting factory constructor, the same AST-splice approach
/// [AppStateSource] uses for `AppState`.
class StateSource {
  StateSource(this.file);

  final File file;

  /// Adds a `<type> <name>` field to the factory of class [className]
  /// (`<Pascal>State`). [defaultExpr] wraps it in `@Default(...)`; [imports]
  /// are added (sorted) when the type needs them (e.g. fast_immutable_collections
  /// for an `IList`).
  ///
  /// A field of that name already there is left alone unless [retype], which
  /// rewrites its declaration to the one asked for.
  ///
  /// **Why retyping belongs here at all.** `add-substate --kind table` scaffolds
  /// `IMap<int, Object>` on purpose — the element type is not known when the
  /// slice is made, and tightening it later was hand work. That was fine while
  /// the state file could be edited by hand; once the guard refused that
  /// channel, the only way to turn `Object` into `Task` was gone, and a traced
  /// run shipped `IMap<int, Object>` because of it. A command that silently
  /// answers "already present" to "make this field a `Task`" is not idempotent,
  /// it is unhelpful.
  Edited addField({
    required String className,
    required String name,
    required String type,
    String? defaultExpr,
    List<String> imports = const [],
    bool retype = false,
  }) {
    final content = sourceIndex.sourceOf(file);
    final unit = sourceIndex.unitFor(file);
    final cls = _stateClass(unit, className);
    final factory = _redirectingFactory(cls, className);

    final existing = factory.parameters.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull;
    if (existing != null) {
      final wanted = _declaration(type, name, defaultExpr);
      if (!retype || existing.toSource() == wanted) {
        return Edited.nothing(content);
      }

      final edits = <Edit>[Edit.replace(existing.offset, existing.end, wanted)];
      // The new type may need an import the old one did not.
      final added = addImports(applyEdits(content, edits), imports);
      return Edited(
        source: added.source,
        changes: ['field: ${existing.toSource()} → $wanted', ...added.changes],
      );
    }

    final params = factory.parameters;
    final decl = _declaration(type, name, defaultExpr);
    final delimiter = params.rightDelimiter;
    final edits = <Edit>[
      // A factory with no named group at all has to grow one; from there the
      // shared comma rule applies.
      delimiter == null
          ? Edit.insert(params.rightParenthesis.offset, '{$decl}')
          : insertIntoList(
              elements: params.parameters,
              closer: delimiter,
              element: decl,
            ),
    ];

    // Imports the field's type needs, each in sorted position in its section.
    final added = addImports(applyEdits(content, edits), imports);
    return Edited(
      source: added.source,
      changes: [...added.changes, 'field: $decl'],
    );
  }

  /// Removes field [name] from the factory of [className], along with any
  /// import in [prune] the removed declaration was the last user of.
  ///
  /// The inverse of [addField], and the only way this file loses a field: the
  /// guard refuses hand edits here, so a field the scaffolder put in — the
  /// `value` every `--kind value` slice arrives with — had no way out at all.
  /// `remove --kind action` deletes the setter and leaves the field; `rm`
  /// cannot open the file.
  ///
  /// `found: false` when the class has no such field, which the caller reports
  /// rather than treating as done: nothing was removed, and saying "removed"
  /// about a name that was never there hides a typo.
  Unwired removeField({
    required String className,
    required String name,
    Map<String, ImportProbe> prune = const {},
  }) {
    final content = sourceIndex.sourceOf(file);
    // [SourceIndex.unitToEdit], not `unitFor`: every edit below is a character
    // offset read off this tree, and offsets from a tree the analyzer recovered
    // out of broken source do not describe the file they land in.
    final unit = sourceIndex.unitToEdit(file);
    final params = _redirectingFactory(
      _stateClass(unit, className),
      className,
    ).parameters;

    final param = params.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull;
    if (param == null) return Unwired.absent(content);

    final edit = _emptiesItsGroup(params, param)
        ? _removeGroup(content, params)
        : removeListItem(content, param);

    // Pruned after the removal, never before: whether the import is still
    // needed is a question about the text that remains.
    final pruned = pruneImports(applyEdits(content, [edit]), prune);
    return Unwired(
      source: pruned.source,
      changes: ['field: ${param.toSource()}', ...pruned.changes],
    );
  }

  /// Whether [param] is the last one inside its delimiters — the `{…}` of a
  /// named group or the `[…]` of an optional positional one.
  ///
  /// Counted within the group, not across the list. `parameters.length == 1`
  /// reads as the same question and is a different one: for
  /// `const factory CheckoutState(int id, {Payment? fallback})` it counts two
  /// and leaves `(int id, {})` behind — an empty group does not parse, and the
  /// file this writes is one the guard will not let anybody repair by hand.
  static bool _emptiesItsGroup(FormalParameterList params, FormalParameter p) {
    if (params.leftDelimiter == null || params.rightDelimiter == null) {
      return false;
    }
    final group = params.parameters.where(
      (other) => other.isNamed == p.isNamed,
    );
    return group.length == 1;
  }

  /// Removes a group's delimiters and everything in them, taking the comma that
  /// separated it from the positional parameters before it.
  ///
  /// `(int id, {Payment? fallback})` → `(int id)`. Leaving the comma parses —
  /// a trailing comma is legal — but writes `(int id, )` into a file that is
  /// only formatted when `--format` is on.
  static Edit _removeGroup(String source, FormalParameterList params) {
    var start = params.leftDelimiter!.offset;
    var before = start;
    while (before > 0 &&
        (source[before - 1] == ' ' || source[before - 1] == '\t')) {
      before--;
    }
    if (before > 0 && source[before - 1] == ',') start = before - 1;
    return Edit.replace(start, params.rightDelimiter!.end, '');
  }

  /// The members of [className] whose source still names [field] — a computed
  /// getter over it, a method reading it.
  ///
  /// Asked before the field is taken out, because nothing else will catch them:
  /// the guard refuses a hand edit to this file, so a `bool get isAuthenticated
  /// => token != null;` left behind is a state class that does not compile and
  /// that its owner is not allowed to fix. Named rather than deleted — the
  /// factory is frx's to write, a member somebody added is not.
  List<String> readersOf({required String className, required String field}) {
    final unit = sourceIndex.unitFor(file);
    final cls = classNamed(unit, className);
    final body = cls?.body;
    if (body is! BlockClassBody) return const [];

    final names = <String>[];
    for (final member in body.members) {
      if (member is ConstructorDeclaration) continue;
      if (!_mentions(member.toSource(), field)) continue;
      names.add(switch (member) {
        MethodDeclaration(:final name) => name.lexeme,
        FieldDeclaration(:final fields) => fields.variables.first.name.lexeme,
        _ => member.toSource(),
      });
    }
    return names;
  }

  /// Whether [source] names [identifier] as a word of its own — not as the tail
  /// of `other.$identifier` and not inside a longer name.
  static bool _mentions(String source, String identifier) {
    for (final match in RegExp(
      '\\b${RegExp.escape(identifier)}\\b',
    ).allMatches(source)) {
      final at = match.start;
      if (at == 0 || source[at - 1] != '.') return true;
    }
    return false;
  }

  /// The source of field [name]'s declaration — `@Default(0) int count` — or
  /// null when the class has no such field.
  ///
  /// Asked before a removal, by the caller that has to work out which imports
  /// the field was the reason for. That question is answered from the
  /// declaration's own text (see `ImportProbes`), and after the removal there
  /// is no declaration left to read it from.
  ///
  /// [SourceIndex.unitFor] and not `unitToEdit`, though an edit follows: what
  /// this returns is *text*, and no offset of it reaches a splice. The strict
  /// parse is [removeField]'s, where the offsets are taken — and it is also
  /// what lets `remove` search a project holding one unparseable slice.
  String? declarationOf({required String className, required String name}) {
    final unit = sourceIndex.unitFor(file);
    final factory = _redirectingFactory(
      _stateClass(unit, className),
      className,
    );
    return factory.parameters.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull
        ?.toSource();
  }

  /// The `@Default(...)` expression on field [name], or null when it has none.
  ///
  /// Asked before a retype, which rebuilds the declaration from scratch: a
  /// default the old one carried and the new invocation does not would be
  /// dropped, and dropping it changes what `AppState.initial()` produces for
  /// every reader. Better to refuse and name it than to write it away.
  String? defaultOf({required String className, required String name}) {
    final unit = sourceIndex.unitFor(file);
    final factory = _redirectingFactory(
      _stateClass(unit, className),
      className,
    );
    final param = factory.parameters.parameters
        .where((p) => p.name?.lexeme == name)
        .firstOrNull;
    if (param == null) return null;
    for (final annotation in param.metadata) {
      if (annotation.name.name != 'Default') continue;
      final args = annotation.arguments?.arguments;
      if (args != null && args.isNotEmpty) return args.first.toSource();
    }
    return null;
  }

  /// The source of one factory parameter — written in one place so an added
  /// field and a retyped one cannot disagree about their own spelling.
  static String _declaration(String type, String name, String? defaultExpr) =>
      defaultExpr != null
      ? '@Default($defaultExpr) $type $name'
      : '$type $name';

  ClassDeclaration _stateClass(CompilationUnit unit, String className) {
    final cls = classNamed(unit, className);
    if (cls == null) {
      throw StateError('class $className not found in "${file.path}".');
    }
    return cls;
  }

  /// The `const factory <Name>({...}) = _<Name>;` redirecting constructor.
  ConstructorDeclaration _redirectingFactory(
    ClassDeclaration cls,
    String className,
  ) {
    final body = cls.body;
    final members = body is BlockClassBody
        ? body.members
        : const <ClassMember>[];
    final ctor = members
        .whereType<ConstructorDeclaration>()
        .where(
          (c) =>
              c.factoryKeyword != null &&
              c.name == null &&
              c.redirectedConstructor != null,
        )
        .firstOrNull;
    if (ctor == null) {
      throw StateError(
        '$className has no redirecting factory constructor in "${file.path}" '
        '— is it a `@freezed` state class?',
      );
    }
    return ctor;
  }
}
