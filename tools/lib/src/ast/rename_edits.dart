import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../redux/ast_edit.dart';
import 'field_rename.dart';
import 'relocation.dart';

/// Renaming one file's contents: identifiers off the parse tree, URIs off the
/// directives that hold them, and the few whole strings a rename owns.
///
/// `rename` swept the whole tree with fourteen `\b<name>\b` patterns and a
/// hand-rolled scanner that walked each file character by character deciding
/// whether an offset sat inside a string literal — the kind of code that is
/// subtly wrong for years. The parse tree already knows: an identifier token is
/// an identifier, a string is a string, and an import URI is neither. Nothing
/// has to be decided.
///
/// **What a rename genuinely reaches that the tree does not** is the names of
/// the *files*, and those are moves rather than edits — the whole of what the
/// sweep was really for. The URIs naming them follow the files through
/// [Relocation], and the substate's camel field — a common word, unlike its
/// types — through [FieldRename].
///
/// **Comments are renamed, deliberately.** They are the one place the old sweep
/// reached that a token walk would not, and dropping them would leave
/// `/// The [LogInState] this page reads` pointing at a class that no longer
/// exists. A comment is not code, but a dartdoc reference is a reference.
class RenameEdits {
  const RenameEdits({
    required this.identifiers,
    this.field,
    this.relocation,
    this.literals = const {},
  });

  /// Old identifier → new, applied to identifier tokens and to comment text.
  ///
  /// Whole tokens, so `LogInState` never matches inside `MyLogInStateThing` —
  /// which is what the old `\b…\b` was approximating. Generated-code prefixes
  /// are understood rather than listed; see [_rename]. Only names distinctive
  /// enough that spelling one *is* being one belong here — a substate's field
  /// is not, and goes in [field].
  final Map<String, String> identifiers;

  /// The substate field, renamed where it names the `AppState` slot only.
  final FieldRename? field;

  /// The files that move, applied inside `import`, `export` and `part` URIs.
  ///
  /// A URI is a string literal, and a string literal is exactly what a rename
  /// must not touch in general — a persistence key has to survive one. This is
  /// not general: it is the URI of a file that moved, or of a file that moved
  /// away from what it names.
  final Relocation? relocation;

  /// Whole string literals a rename owns, matched entire or by a `/`-segmented
  /// prefix.
  ///
  /// Two, and only these two, both belonging to a page rename:
  ///
  /// * its **route path** — `AutoRoute(…, path: '/home')`. auto_route derives
  ///   the default from the page name, so renaming the page and leaving the URL
  ///   is a half-rename; the prefix rule carries `'/home/:id'` along with it.
  /// * its **placeholder text** — the `Text('HomePage')` the page scaffold
  ///   writes, which would otherwise keep naming a class that no longer exists
  ///   on a screen the user is looking at.
  ///
  /// Whole, and that is the narrowing: the old sweep rewrote the class name
  /// *anywhere* inside *any* string, so `'Go to HomePage now'` moved too, and
  /// so would a storage key that happened to contain it. A literal that is
  /// exactly the old name is the scaffold's; one that merely contains it is
  /// somebody's sentence.
  final Map<String, String> literals;

  /// The edits [unit] needs, in no particular order — `applyEdits` sorts.
  ///
  /// [path] is the file [unit] was read from, which its relative URIs start
  /// from; without one, no URI is rewritten.
  List<Edit> of(CompilationUnit unit, {String? path}) {
    final edits = <Edit>[...?field?.of(unit)];
    for (var token = unit.beginToken; ; token = token.next!) {
      _comments(token, edits);
      if (token.isEof) {
        break;
      }

      if (!_isIdentifier(token) || _isLocalisation(token)) {
        continue;
      }

      final to = _rename(token.lexeme);
      if (to != null) {
        edits.add(Edit.replace(token.offset, token.end, to));
      }
    }

    // Directive URIs first, so their literals are known and the literal walk
    // below leaves them alone: the two maps are different rules, and a URI
    // answering to both would be spliced twice at overlapping offsets.
    final uris = <int>{};
    for (final directive in unit.directives) {
      final uri = switch (directive) {
        ImportDirective(:final uri) => uri,
        ExportDirective(:final uri) => uri,
        PartDirective(:final uri) => uri,
        // `part of` may name a library instead of a file, in which case there
        // is no URI to move.
        PartOfDirective(:final uri) => uri,
        _ => null,
      };
      final was = uri?.stringValue;
      // A URI written as an adjacent-string concatenation has a value but no
      // single span to splice; frx leaves it, which is what it did before.
      if (uri is! SingleStringLiteral || was == null) {
        continue;
      }

      uris.add(uri.offset);
      final now = path == null ? null : relocation?.rewrite(was, from: path);
      if (now != null && now != was) {
        edits.add(_replaceContents(uri, now));
      }
    }

    if (literals.isNotEmpty) {
      final found = <SimpleStringLiteral>[];
      unit.accept(_Literals(found));
      for (final literal in found) {
        if (uris.contains(literal.offset)) {
          continue;
        }

        final now = _rewriteLiteral(literal.value);
        if (now != literal.value) {
          edits.add(_replaceContents(literal, now));
        }
      }
    }
    return edits;
  }

  /// [literal]'s contents replaced with [text], leaving its quoting alone.
  ///
  /// Asked of the node rather than computed as `offset + 1`: a quote is not one
  /// character. `r'/home'` has two before the content and a triple-quoted
  /// string has three, and splicing past them wrote `r/landing'` — source that
  /// does not parse, out of a command whose whole promise is that it either
  /// lands or does not.
  static Edit _replaceContents(SingleStringLiteral literal, String text) =>
      Edit.replace(literal.contentsOffset, literal.contentsEnd, text);

  /// [value] when it *is* one of [literals], or begins with one as a whole
  /// `/`-segment — `'/home'` and `'/home/:id'`, never `'/homepage'`.
  String _rewriteLiteral(String value) {
    for (final entry in literals.entries) {
      if (value == entry.key) {
        return entry.value;
      }

      if (value.startsWith('${entry.key}/')) {
        return entry.value + value.substring(entry.key.length);
      }
    }

    return value;
  }

  /// Identifier-shaped words in a comment.
  static final _word = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// The comment text attached before [token], with its references renamed.
  ///
  /// Comments hang off the token that follows them — including the end-of-file
  /// token, which is where a trailing comment lives and where a loop stopping
  /// *at* EOF never looks.
  ///
  /// Every word goes through the same [_rename] the tokens do, rather than one
  /// `\b<name>\b` pass per entry: `\b` is what put `_LogInState` and
  /// `_$LogInState` on different footings in the first place, and a comment
  /// should not be the one place that accident survives. The field is renamed
  /// only as a `[reference]`: a comment saying "like connectivity" is prose,
  /// and the old sweep renaming it — along with every folder name a comment
  /// happened to share with the substate — was the same over-reach as in code.
  void _comments(Token token, List<Edit> into) {
    for (
      Token? c = token.precedingComments;
      c != null;
      c = c.next as CommentToken?
    ) {
      var text = c.lexeme.replaceAllMapped(
        _word,
        (m) => _rename(m[0]!) ?? m[0]!,
      );
      text = field?.inComment(text) ?? text;
      if (text != c.lexeme) {
        into.add(Edit.replace(c.offset, c.end, text));
      }
    }
  }

  /// [lexeme] renamed, or null when nothing applies.
  ///
  /// A generated-code prefix is part of the token and not part of the name:
  /// freezed writes `_$LogInState` for `LogInState`, and the mixin is one
  /// identifier. The old `\b<name>\b` sweep reached it by accident — `$` is not
  /// a word character, so the boundary fell inside the token — and needed a
  /// hand-written second pattern for `_LogInState`, where `_` *is* one and the
  /// boundary did not. Stated once, both work and the second pattern goes.
  String? _rename(String lexeme) {
    final direct = identifiers[lexeme];
    if (direct != null) {
      return direct;
    }
    for (final prefix in const [r'_$', '_', r'$']) {
      if (!lexeme.startsWith(prefix)) {
        continue;
      }
      final renamed = identifiers[lexeme.substring(prefix.length)];
      if (renamed != null) {
        return '$prefix$renamed';
      }
    }
    return null;
  }

  /// Whether [token] is the tail of `…current.<name>` — an l10n key.
  ///
  /// A substate's camel field is a common word, and `S.current.logIn` is the
  /// generated getter for a translation of the same name. Renaming the substate
  /// must not rename the key it happens to share a word with; renaming the key
  /// is a different job with a different source of truth (the ARB files).
  ///
  /// The old sweep said this with a `(?<!current\.)` lookbehind *and* by
  /// refusing to touch `ui/lib` at all — two approximations of one fact the
  /// token stream states exactly, which is why the `ui` exclusion is gone and a
  /// connector holding an l10n access is safe too.
  static bool _isLocalisation(Token token) =>
      token.previous?.lexeme == '.' &&
      token.previous?.previous?.lexeme == 'current';

  /// Whether [token] is a plain identifier — not a keyword, not a literal.
  ///
  /// A contextual keyword (`await`, `show`, `sync`) is an identifier token in
  /// the parser's eyes and may legitimately be a name, so the test is on the
  /// token's type rather than on a list of words.
  static bool _isIdentifier(Token token) =>
      token.type == TokenType.IDENTIFIER ||
      (token.type.isKeyword && (token.keyword?.isBuiltInOrPseudo ?? false));
}

class _Literals extends RecursiveAstVisitor<void> {
  _Literals(this._into);

  final List<SimpleStringLiteral> _into;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _into.add(node);
}
