/// What an import *supplies*, so an edit that takes code away can tell which
/// imports it took the last reason for.
///
/// The inverse of `TypeImports`, and needed because that direction only answers
/// for what it knows. `TypeImports` is a table — "a snippet naming `IList`
/// needs fast_immutable_collections" — and a table can only be asked about the
/// entries somebody wrote into it. Every other import in a file is invisible to
/// it, so `frx remove … --kind selector` took
///
///     bool get isWaiting =>
///         _state.wait.isWaitingForType<LoadContactsAction>();
///
/// out of the facade and left
/// `import 'contacts/actions/load_contacts_action.dart'` behind, and did the
/// same with the package that supplied the return type of the one other getter
/// that named it. Two `unused_import`s and a hand edit to a file under the
/// placement guard — which is the shape of thing the command exists to avoid.
///
/// **The question is answered by reading, not by a table.** An import URI
/// resolves to a file; a file declares names and hands on the ones it exports;
/// a name in the surviving source is what keeps the import. That covers a
/// relative import, a package one, the project's own packages and pub's alike,
/// and it needs no entry written in advance.
///
/// **A name can have two suppliers, and that decides nothing on its own.** A
/// project on a generated Serverpod client gets `UuidValue` from it *and* from
/// the auth package beside it. An import still naming something the file uses
/// is only kept when no import that is *staying* supplies that name too — which
/// is the rule the analyzer's own `unused_import` applies, and without it the
/// second of two suppliers can never be removed.
///
/// **Every uncertainty keeps the import.** An export that does not resolve, a
/// package outside `package_config.json`, a URI in a scheme this cannot read —
/// any of them makes the answer "unknown", and an unknown import is never
/// removed. Erring wide leaves an import nothing uses, which is a lint; erring
/// narrow takes one out from under live code, which is a build.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../redux/ast_edit.dart';
import 'directives.dart';
import 'library_resolver.dart';
import 'source_index.dart';

/// Removes the imports of [source] that nothing in it needs any more.
///
/// [file] is the file [source] belongs to — where it sits decides what a
/// relative URI means and which `package_config.json` answers for a package
/// one. [source] is the text *after* the removal, since the question is about
/// what survived it.
///
/// [removedNames] scopes the pass to the edit that prompted it: an import is a
/// candidate only when it supplies a name the removal took out of the file
/// altogether. An import that was already unused before this command ran stays
/// — cleaning it up is not this edit's business, and a `remove` that quietly
/// tidies imports it was not pointed at is a diff nobody asked for. It is also
/// what keeps the pass off the disk in the ordinary case: no name vanished, no
/// import can have died, and not one library is opened.
({String source, List<String> changes}) pruneUnusedImports(
  String source, {
  required File file,
  required Set<String> removedNames,
}) {
  if (removedNames.isEmpty) {
    return (source: source, changes: const []);
  }

  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final imports = importsOf(unit);
  if (imports.isEmpty) {
    return (source: source, changes: const []);
  }

  // A library whose parts are not in front of us is a library whose uses are
  // not either: a `part` names types on the importing file's behalf, and a
  // generated one is usually stale at exactly the moment a removal runs. There
  // is nothing to say about such a file, so nothing is said.
  if (unit.directives.whereType<PartDirective>().isNotEmpty) {
    return (source: source, changes: const []);
  }

  final body = namesUsedIn(unit);
  final vanished = {...removedNames}..removeWhere(body.contains);
  if (vanished.isEmpty) {
    return (source: source, changes: const []);
  }

  final supply = _Supply(p.dirname(p.absolute(file.path)));
  final supplied = <ImportDirective, Set<String>>{};
  // The imports that supply each name — the other side of the same table,
  // which is what "does anything staying still supply this" is asked of.
  final suppliers = <String, List<ImportDirective>>{};
  for (final imp in imports) {
    final uri = imp.uri.stringValue;
    if (uri == null) {
      continue;
    }
    // A prefixed import is reached by its prefix and by nothing else, so what
    // it supplies never has to be resolved.
    final prefix = imp.prefix?.name;
    final names = prefix != null ? {prefix} : supply.of(uri);
    if (names == null) {
      continue; // unknown — see the library doc
    }

    final kept = _filter(names, imp.combinators);
    supplied[imp] = kept;
    for (final name in kept) {
      suppliers.putIfAbsent(name, () => []).add(imp);
    }
  }

  final edits = <Edit>[];
  final changes = <String>[];
  final gone = <ImportDirective>{};
  for (final imp in imports) {
    final names = supplied[imp];
    // Every import that could answer for a vanished name is judged, not just
    // the first one that can.
    if (names == null || !names.any(vanished.contains)) {
      continue;
    }

    final held = names.where(body.contains);
    final covered = held.every(
      (name) => suppliers[name]!.any(
        (other) => other != imp && !gone.contains(other),
      ),
    );
    if (!covered) {
      continue;
    }

    gone.add(imp);
    edits.add(removeDirective(source, imp));
    changes.add("import '${imp.uri.stringValue}'");
  }

  return edits.isEmpty
      ? (source: source, changes: const [])
      : (source: applyEdits(source, edits), changes: changes);
}

/// Every name [unit]'s own code names, which is what "is this import still
/// needed" comes down to.
///
/// Read off the tree rather than scanned out of the text, and the difference is
/// not academic: a facade whose prose said "this *slice* has more than one
/// thing" counted `slice` as a use, and an import that happened to declare that
/// name somewhere could never be removed again. Doc *references* — the
/// `[Thing]` kind — are in the tree and do count, which is the same line the
/// analyzer draws.
///
/// The directives are skipped: an import naming what it shows is not a use of
/// it.
Set<String> namesUsedIn(CompilationUnit unit) {
  final visitor = _UsedNameVisitor();
  for (final declaration in unit.declarations) {
    declaration.accept(visitor);
  }

  return visitor.names;
}

/// The names [node] names — [namesUsedIn] asked of one declaration, which is
/// how a caller says what its removal took away.
Set<String> namesIn(AstNode node) {
  final visitor = _UsedNameVisitor();
  node.accept(visitor);

  return visitor.names;
}

class _UsedNameVisitor extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  /// A type is not an identifier on this tree — `IList<String>` and the
  /// `LoadContactsAction` inside `isWaitingForType<…>()` are [NamedType], whose
  /// name is a token. Left out, the pass saw a file that named no types at all,
  /// which is both halves of the question answered wrongly at once.
  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    final prefix = node.importPrefix?.name.lexeme;
    if (prefix != null) {
      names.add(prefix);
    }

    super.visitNamedType(node);
  }
}

/// [names] with `show` and `hide` applied.
Set<String> _filter(Set<String> names, List<Combinator> combinators) {
  var kept = names;
  for (final combinator in combinators) {
    switch (combinator) {
      case ShowCombinator():
        final shown = {for (final n in combinator.shownNames) n.name};
        kept = {...kept.where(shown.contains)};
      case HideCombinator():
        final hidden = {for (final n in combinator.hiddenNames) n.name};
        kept = {...kept.where((n) => !hidden.contains(n))};
    }
  }
  return kept;
}

/// The names each import URI supplies, resolved once per pass.
class _Supply {
  _Supply(this.dir) : _resolver = LibraryResolver(dir);

  /// The directory of the file whose imports are being judged.
  final String dir;

  final LibraryResolver _resolver;
  final _byUri = <String, Set<String>?>{};
  final _done = <String, Set<String>>{};

  /// The names [uri] supplies, or null when they cannot be enumerated.
  Set<String>? of(String uri) =>
      _byUri.putIfAbsent(uri, () => _names(_resolver.resolve(uri, dir), {}));

  /// Every name [file] hands out: its own public declarations, its parts', and
  /// what it exports, as far as that reaches. Null when a link in it cannot be
  /// read.
  ///
  /// Parsed here, not through [sourceIndex]: the index keeps every tree it
  /// parses for the run, and what this walks is the SDK and the pub cache —
  /// hundreds of libraries nothing else reads, whose trees held for the length
  /// of a `remove` quadruple its memory. Only the names are worth keeping, and
  /// [_done] keeps them.
  Set<String>? _names(File? file, Set<String> onStack) {
    if (file == null || !file.existsSync()) {
      return null;
    }
    final path = p.canonicalize(file.path);
    final done = _done[path];
    if (done != null) {
      return done;
    }
    // Two libraries exporting each other is legal and rare. The one in progress
    // contributes nothing on the way round, which is where the recursion stops;
    // its names still reach the caller by the path that is still unwinding.
    if (!onStack.add(path)) {
      return const {};
    }

    final unit = parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
    final names = declaredNamesIn(unit);

    final from = p.dirname(path);
    for (final directive in unit.directives) {
      // Every branch of `export 'a.dart' if (…) 'b.dart'`, since which one a
      // build takes is not a property of the text. Their union is the wider
      // answer, and wider keeps imports rather than removing them.
      final uris = switch (directive) {
        ExportDirective() => [
          ?directive.uri.stringValue,
          for (final c in directive.configurations) ?c.uri.stringValue,
        ],
        PartDirective() => [?directive.uri.stringValue],
        _ => const <String>[],
      };
      for (final uri in uris) {
        final reached = _names(_resolver.resolve(uri, from), onStack);
        if (reached != null) {
          names.addAll(
            directive is ExportDirective
                ? _filter(reached, directive.combinators)
                : reached,
          );
          continue;
        }
        // A `part` that is not on disk is the SDK's own shape: `dart:_internal`
        // declares `part 'patch.dart'`, and the patch is supplied by the build
        // rather than shipped beside the source. What such a part declares is
        // the SDK's implementation of itself, which no import of a project file
        // is there for — so it is skipped, where an export that does not
        // resolve still makes the whole answer unknown.
        if (directive is PartDirective) {
          continue;
        }
        onStack.remove(path);
        return null;
      }
    }

    onStack.remove(path);
    return _done[path] = names;
  }
}

/// Every name a compilation unit hands to whoever imports it.
///
/// An extension contributes its member names as well as its own: `.toIList()`
/// names neither the extension nor the type it is on, and an import that
/// supplies only that is still an import the code needs.
Set<String> declaredNamesIn(CompilationUnit unit) {
  final names = _Public();
  for (final d in unit.declarations) {
    switch (d) {
      case ClassDeclaration():
        names.add(d.namePart.typeName.lexeme);
      case EnumDeclaration():
        names.add(d.namePart.typeName.lexeme);
      case ExtensionTypeDeclaration():
        names.add(d.namePart.typeName.lexeme);
      case MixinDeclaration():
        names.add(d.name.lexeme);
      case TypeAlias():
        names.add(d.name.lexeme);
      case FunctionDeclaration():
        names.add(d.name.lexeme);
      case TopLevelVariableDeclaration():
        for (final v in d.variables.variables) {
          names.add(v.name.lexeme);
        }
      case ExtensionDeclaration():
        names.add(d.name?.lexeme);
        for (final member in d.body.members) {
          switch (member) {
            case MethodDeclaration():
              names.add(member.name.lexeme);
            case FieldDeclaration():
              for (final v in member.fields.variables) {
                names.add(v.name.lexeme);
              }
            case _:
          }
        }
      case _:
    }
  }
  return names.taken;
}

/// A name set that drops what a library cannot hand out. A private declaration
/// is not visible to an importer, and counting one as supplied is how a package
/// looked as if it were still answering for the `_Factory` that a connector in
/// *this* project declares.
class _Public {
  final taken = <String>{};

  void add(String? name) {
    if (name != null && !name.startsWith('_')) {
      taken.add(name);
    }
  }
}
