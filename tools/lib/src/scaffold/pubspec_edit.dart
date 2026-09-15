/// Surgical edits to a `pubspec.yaml`: a workspace member added or removed, a
/// path dependency declared or withdrawn.
///
/// Splices through `yaml_edit` and by span, never a parse-and-re-serialise: a
/// pubspec carries prose and blank lines that are not ours to reflow, and the
/// root one has a paragraph about Pub workspaces a round-trip would drop.
/// Each function returns its input unchanged when there is nothing to do, so
/// no caller needs its own idempotency rule.
library;

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../refusal.dart';

/// [source] with [name] added to the root pubspec's `workspace:` list.
///
/// A surgical splice through `yaml_edit`, not a parse-and-re-serialise: the
/// root pubspec carries a paragraph of prose about Pub workspaces that a
/// round-trip would reflow or drop. Returns [source] unchanged when the entry
/// is already there, so the caller's idempotency needs no second rule.
String addToWorkspaceList(String source, String name) {
  final editor = YamlEditor(source);
  final members = _workspaceList(editor);

  if (members is! List) {
    throw const FrxRefusal(
      'The root pubspec has no `workspace:` list — this does not look like '
      'the monorepo (looked in the pubspec beside the frx marker).',
    );
  }
  if (members.contains(name)) {
    return source;
  }

  editor.appendToList(['workspace'], name);
  return editor.toString();
}

/// [source] with [name] removed from the `workspace:` list, for the symmetry
/// `remove` will want. Unchanged when it is not a member.
String removeFromWorkspaceList(String source, String name) {
  final editor = YamlEditor(source);
  final members = _workspaceList(editor);
  if (members is! List) {
    return source;
  }

  final at = members.indexOf(name);
  if (at < 0) {
    return source;
  }

  editor.remove(['workspace', at]);
  return editor.toString();
}

/// The value under `workspace:`, or null when the key is absent.
Object? _workspaceList(YamlEditor editor) =>
    editor.parseAt(['workspace'], orElse: () => wrapAsYamlNode(null)).value;

/// [source] with a path dependency on [name] under `dependencies:`.
/// Unchanged when it is already declared.
///
/// **Inserted in sorted position, not appended**, which is why this is not
/// `editor.update(['dependencies', name], …)`: that appends, `pro_lints`
/// turns on `sort_pub_dependencies`, and a project would open with an
/// analyzer warning in the file this command had just edited.
///
/// So the position is read off the YAML — the keys and their spans — and the
/// two lines are spliced into the text. A parse-and-re-serialise would place
/// them correctly and reflow everything else, and a pubspec is not ours to
/// reformat; it is the reason [addToWorkspaceList] is a splice too.
String addPathDependency(String source, String name) {
  final editor = YamlEditor(source);
  final deps = editor.parseAt([
    'dependencies',
  ], orElse: () => wrapAsYamlNode(null));

  if (deps is YamlMap && deps.isNotEmpty) {
    if (deps.containsKey(name)) {
      return source;
    }

    return _splice(source, _placeFor(source, deps, name), _entry(name));
  }
  if (deps is YamlMap || deps.value == null) {
    // An empty block, a `dependencies:` with nothing under it, or no key at
    // all — nothing to sort against, so `yaml_edit` writes the whole block.
    editor.update(
      ['dependencies'],
      {
        name: {'path': '../$name'},
      },
    );
    return editor.toString();
  }
  // Anything else is a shape this does not understand, and overwriting it would
  // take a list of dependencies away without saying so. [addToWorkspaceList]
  // refuses the same class of surprise rather than guessing.
  throw FrxRefusal(
    'The `dependencies:` of this pubspec is not a map of package names, so '
    '"$name" cannot be added to it without discarding what is there.',
  );
}

/// [source] with the dependency on [name] gone. Unchanged when it declares
/// none — the idempotency the callers would otherwise each need a rule for.
///
/// A splice, and for a sharper reason than [addPathDependency]'s:
/// `editor.remove` takes the blank line after the block with it when the entry
/// removed is the last one, so it was not the inverse of an insert in that one
/// position. Cutting exactly the lines the entry spans is inverse by
/// construction.
String removePathDependency(String source, String name) {
  final deps = YamlEditor(
    source,
  ).parseAt(['dependencies'], orElse: () => wrapAsYamlNode(null));
  if (deps is! YamlMap) {
    return source;
  }

  for (final entry in deps.nodes.entries) {
    final key = entry.key as YamlScalar;
    if (key.value != name) {
      continue;
    }

    final from = _startOfLine(source, key.span.start.offset);
    final to = _afterLine(source, entry.value.span.end.offset);
    return source.substring(0, from) + source.substring(to);
  }

  return source;
}

/// The two lines a path dependency on [name] is written as.
String _entry(String name) => '  $name:\n    path: ../$name\n';

/// Where in [source] an entry named [name] belongs, given the existing
/// (non-empty) [deps].
///
/// **After the last entry that sorts before it**, rather than before the
/// first that sorts after. The two differ by exactly one thing: a comment
/// sits above the key it annotates, so inserting *before* a key inserts
/// between that key and its comment — silently re-parenting prose onto the
/// new entry, in a splice whose whole purpose is to leave prose alone.
int _placeFor(String source, YamlMap deps, String name) {
  YamlNode? previous;
  for (final entry in deps.nodes.entries) {
    if (((entry.key as YamlScalar).value as String).compareTo(name) > 0) {
      break;
    }
    previous = entry.value;
  }

  if (previous != null) {
    return _afterLine(source, previous.span.end.offset);
  }

  // It sorts before everything: the top of the block, above the first entry
  // *and* above the comment lines that belong to it.
  var at = _startOfLine(source, deps.span.start.offset);
  while (at > 0) {
    final previousStart = at == 1 ? 0 : _startOfLine(source, at - 2);
    final line = source.substring(previousStart, at - 1).trim();
    if (line.isNotEmpty && !line.startsWith('#')) {
      break;
    }
    at = previousStart;
  }
  return at;
}

/// [source] with [entry] inserted at [at].
///
/// A source that does not end in a newline is given one first: [_afterLine]
/// answers `source.length` for the last line of such a file, and splicing
/// there would run the new entry onto the end of the last one.
String _splice(String source, int at, String entry) =>
    at == source.length && !source.endsWith('\n')
    ? '$source\n$entry'
    : source.substring(0, at) + entry + source.substring(at);

/// The offset of the first character on the line holding [offset].
int _startOfLine(String source, int offset) {
  final newline = source.lastIndexOf('\n', offset);
  return newline < 0 ? 0 : newline + 1;
}

/// The offset just past the end of the line holding [offset], newline
/// included — where a following line can be spliced in.
///
/// Trailing whitespace is walked back over first, because a block node's span
/// may end past its last character: taken literally, the next newline would
/// then be the one *after* the line meant, and the splice would land a line
/// too low.
int _afterLine(String source, int offset) {
  var at = offset;
  while (at > 0 && _isSpace(source.codeUnitAt(at - 1))) {
    at--;
  }
  final newline = source.indexOf('\n', at);
  return newline < 0 ? source.length : newline + 1;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;
