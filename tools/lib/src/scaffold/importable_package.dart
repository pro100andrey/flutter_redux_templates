import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../ast/source_index.dart';

/// One package, asked "what would a file have to import to name this type?".
class ImportablePackage {
  ImportablePackage(this.name, this.lib);

  final String name;
  final Directory lib;

  /// Identifier → the URI that supplies it, remembered for the life of the
  /// index scope this package was resolved in: a state file names dozens of
  /// identifiers and most of them are not models at all, so a miss — a full
  /// read of the tree — must be paid once, not once per caller.
  final _uris = <String, String?>{};

  final _entries = <String, String?>{};

  /// The import URI of this package that supplies [identifier], or null.
  ///
  /// Two questions. **Which file declares it**, and then **which entry point
  /// exports that file**, when the declaration turns out to live under
  /// `lib/src/` — private by pub's convention, and importing it directly is not
  /// how anybody reaches the class.
  ///
  /// There used to be a third, asked first and cheapest: `Task` is in
  /// `task.dart`, the convention `add-model` writes, one `existsSync`. It is
  /// gone because it answered from the *file name* and never opened the file. A
  /// `models/lib/task.dart` holding `class TaskList` and a `Task` next door in
  /// `other.dart` made it answer `package:models/task.dart` for `Task` — an
  /// import that resolves and does not supply the name, which is the one
  /// failure this module's doc promises it cannot have. The convention it
  /// encoded is not lost: when `task.dart` does declare `Task`, the declaration
  /// search finds it there, having checked.
  String? uriFor(String identifier) => _uris.putIfAbsent(identifier, () {
    final file = _byDeclaration(identifier);
    return file == null ? null : _entryFor(file, identifier, {});
  });

  /// The file that declares [identifier] — or redirects a factory to it, which
  /// is how a freezed union names its cases.
  ///
  /// Text first: [SourceIndex.unitIf] reads each file and parses only the ones
  /// that contain the word at all, so a miss costs reads and no parses. That
  /// pre-filter is what makes the widened search space affordable — the six
  /// path dependencies of one real app are 228 files and 1.3 MB, of which a
  /// given identifier matches a handful.
  ///
  /// Recursive, unlike the `models`-only lookup this replaces: `lib/src/` is
  /// where a package with a barrel keeps everything, and
  /// `models/lib/converters/` was invisible to the old walk for the same
  /// reason.
  ///
  /// Generated files are not searched — `result.freezed.dart` declares the case
  /// too, and importing *it* is not how anybody reaches the class.
  File? _byDeclaration(String identifier) {
    final wanted = _declarationText(identifier);
    for (final file in sourceIndex.filesUnder(lib)) {
      final unit = sourceIndex.unitIf(file, wanted.hasMatch);
      if (unit == null) {
        continue;
      }
      if (_declares(unit, identifier)) {
        return file;
      }
    }
    return null;
  }

  /// The text a file must contain before it is worth parsing for [identifier].
  ///
  /// A plain `contains` is not a pre-filter here, it is a full scan wearing
  /// one: `String` occurs in essentially every Dart file, so
  /// `add-field x note:String?` parsed all 161 files of one real app's
  /// dependency closure to conclude that none of them declares it — 400 ms and
  /// 161 parses to answer "no". Matching the *declaration* instead costs the
  /// same read and almost never the parse.
  ///
  /// Kept deliberately in step with [_declares], which is the authority: this
  /// only has to be no *narrower*, and `type_imports` asserts exactly that over
  /// every declaration form Dart has. A branch missing here is not a slow
  /// answer, it is a wrong one — the file is never parsed, so the declaration
  /// in it is never seen and the import never written.
  ///
  /// The branches, in the order they appear:
  ///
  /// - the keyword forms. `abstract final class X`, `sealed class X` and
  ///   `mixin class X` all contain `class X`; `extension type const X(int i)`
  ///   is why `const` is optional there.
  /// - `typedef`, which has two syntaxes and puts the name in a different place
  ///   in each — `typedef X = void Function()` and the legacy
  ///   `typedef void X()`. Bounded to one statement so it cannot run away.
  /// - the redirect a freezed union writes, `= ResultSuccess;`, which is how a
  ///   case class is named in source before `build_runner` generates it.
  static RegExp _declarationText(String identifier) {
    final name = RegExp.escape(identifier);
    return RegExp(
      r'(?:class|mixin|enum|extension\s+type(?:\s+const)?)\s+'
      '$name'
      r'\b'
      r'|typedef[^;\n]*\b'
      '$name'
      r'\b'
      r'|=\s*'
      '$name'
      r'\s*[;(<]',
    );
  }

  /// The importable URI for [file] — itself when it is public, otherwise the
  /// entry point that exports it.
  ///
  /// Walked upwards from the declaration rather than downwards from every entry
  /// point, because the two directions cost differently: a package's export
  /// closure is its whole source tree (`tm_core` is 163 files), while the files
  /// that mention one basename are a handful the text pre-filter finds. [seen]
  /// bounds a cyclic re-export.
  String? _entryFor(File file, String identifier, Set<String> seen) {
    final key = p.canonicalize(file.path);
    if (!seen.add(key)) {
      return null;
    }

    final relative = p.url.joinAll(
      p.split(p.relative(file.path, from: lib.path)),
    );
    if (!relative.startsWith('src/')) {
      return 'package:$name/$relative';
    }

    // Keyed by the identifier as well as the file: `show`/`hide` mean two names
    // declared side by side in one private file can come out of different entry
    // points, or one of them out of none.
    return _entries.putIfAbsent('$identifier|$key', () {
      final basename = p.basename(file.path);
      for (final candidate in sourceIndex.filesUnder(lib)) {
        if (p.canonicalize(candidate.path) == key) {
          continue;
        }
        final unit = sourceIndex.unitIf(candidate, (s) => s.contains(basename));
        if (unit == null) {
          continue;
        }
        if (!_exports(unit, candidate, key, identifier)) {
          continue;
        }
        final uri = _entryFor(candidate, identifier, seen);
        if (uri != null) {
          return uri;
        }
      }
      return null;
    });
  }

  /// Whether [unit] re-exports [identifier] from the file at [target].
  ///
  /// Only relative exports are followed. `export 'package:other/other.dart'` is
  /// a different package's entry point, and this package is not what supplies
  /// the name — the other one is, and it is resolved on its own if it is a
  /// dependency and correctly not resolved if it is not.
  ///
  /// The combinators are honoured, and that is not pedantry: this module's
  /// whole safety argument is that it can miss an import but never invent a
  /// wrong one, and `export 'src/store.dart' show SqliteEventStore` is a real
  /// barrel in a real dependency here. Answering
  /// `package:tm_store_sqlite/tm_store_sqlite.dart` for the *other* class in
  /// that file would be an import that resolves and does not supply the name —
  /// the exact failure the doc above promises away.
  static bool _exports(
    CompilationUnit unit,
    File from,
    String target,
    String identifier,
  ) {
    for (final directive in unit.directives.whereType<ExportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || uri.contains(':')) {
        continue;
      }
      final resolved = p.canonicalize(
        p.normalize(p.join(p.dirname(from.path), p.fromUri(uri))),
      );
      if (resolved != target) {
        continue;
      }
      if (_combinatorsAdmit(directive, identifier, File(target))) {
        return true;
      }
    }
    return false;
  }

  /// Whether [directive]'s `show`/`hide` list lets [identifier] out of
  /// [target].
  ///
  /// A union case is admitted by its union's name too — `show Result` exports
  /// `ResultSuccess`, because the case is a constructor redirect on the class
  /// the combinator names, not a separate top-level name to list. Established
  /// by reading that redirect in [target], **not** by
  /// `ResultSuccess.startsWith`: the prefix guess admits
  /// `MemoryDigestInternals` for a `show MemoryDigest`, which is the same guess
  /// this module's `probeFor` doc records having thrown out for keeping
  /// `task.dart` alive for a surviving `TaskList`.
  static bool _combinatorsAdmit(
    ExportDirective directive,
    String identifier,
    File target,
  ) {
    for (final combinator in directive.combinators) {
      switch (combinator) {
        case ShowCombinator(:final shownNames):
          final shown = shownNames.map((n) => n.name).toSet();
          if (shown.contains(identifier)) {
            continue;
          }
          final unit = sourceIndex.unitIf(
            target,
            (s) => s.contains(identifier),
          );
          final owners = unit == null
              ? const <String>{}
              : _redirectOwners(unit, identifier);
          if (owners.any(shown.contains)) {
            continue;
          }
          return false;
        case HideCombinator(:final hiddenNames):
          if (hiddenNames.any((n) => n.name == identifier)) {
            return false;
          }
      }
    }
    return true;
  }

  /// Whether [unit] supplies [identifier] — declares it outright, or names it
  /// as the case of a union it declares.
  static bool _declares(CompilationUnit unit, String identifier) =>
      _declaredNames(unit).contains(identifier) ||
      _redirectOwners(unit, identifier).isNotEmpty;

  /// The top-level type names [unit] declares.
  static Set<String> _declaredNames(CompilationUnit unit) => {
    for (final declaration in unit.declarations)
      // Each kind carries its own name, and the analyzer 14 spelling differs
      // between them — `namePart.typeName` for the ones that can be augmented,
      // a plain `name` for the rest. There is no shared supertype to ask, so
      // the list is spelled out.
      //
      // A kind missing from it is **not** symmetric between the two directions
      // this resolver serves. Adding: a missed import is a compile error naming
      // the type, which is loud. Pruning: the probe reads "nothing here needs
      // that file" and takes a live import out — silent, and in a state file
      // nobody is allowed to put back by hand. So a new declaration kind
      // belongs here before it belongs anywhere.
      if (switch (declaration) {
            ClassDeclaration(:final namePart) ||
            ExtensionTypeDeclaration(:final namePart) ||
            EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
            MixinDeclaration(:final name) ||
            TypeAlias(:final name) => name.lexeme,
            _ => null,
          }
          case final String declared)
        declared,
  };

  /// The classes in [unit] that redirect a factory to [identifier] — the shape
  /// `const factory Result.success() = ResultSuccess;` has, where the case
  /// class itself is generated and this is where the source says its name.
  ///
  /// One reading of the redirect, asked two ways. "Does this file supply
  /// `ResultSuccess`?" is `isNotEmpty`; "does `show Result` carry it?" is
  /// `contains('Result')`. They were two functions walking the same members for
  /// the same statement, which is how a resolver ends up agreeing with itself
  /// only by coincidence.
  static Set<String> _redirectOwners(
    CompilationUnit unit,
    String identifier,
  ) => {
    for (final declaration in classesIn(unit))
      if (declaration.body.members.whereType<ConstructorDeclaration>().any(
        (m) => m.redirectedConstructor?.type.name.lexeme == identifier,
      ))
        declaration.namePart.typeName.lexeme,
  };
}
