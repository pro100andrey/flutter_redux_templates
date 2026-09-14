/// One file frx reads and edits by way of the index.
///
/// Every reader-editor in the redux and routing tiers has the same spine: it
/// holds a [File], reads its text for the splice and its tree for the offsets,
/// and refuses when the class it wires into is not there. Each of them wrote
/// that spine for itself — a `_parse` that took an optional string and parsed
/// it *again* when the index already held that very text, and a class lookup
/// whose refusal three files worded identically. This is the spine, once.
///
/// Both trees are on offer because both strictnesses are in use, and which
/// applies where is a per-call decision the [SourceIndex] doc states the rule
/// for. Nothing here picks for a caller.
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../refusal.dart';
import '../workspace/frx_workspace.dart';
import 'declarations.dart';
import 'source_index.dart';

/// A Dart file read and edited through [sourceIndex].
abstract class FileSource {
  FileSource(this.file);

  final File file;

  bool get exists => file.existsSync();

  /// The text on disk — what every edit is spliced into.
  String get content => sourceIndex.sourceOf(file);

  /// The tree for [file]; a recovered one when the file does not parse.
  CompilationUnit get unit => sourceIndex.unitFor(file);

  /// The tree for [file], refused when the file does not parse cleanly.
  CompilationUnit get unitToEdit => sourceIndex.unitToEdit(file);

  /// [content] and [unit] from one read — what a splice takes, since offsets
  /// read off a tree only describe the text it was parsed from, and [content]
  /// then [unit] is two reads of a file something else may save between.
  Snapshot get snapshot => sourceIndex.snapshotOf(file);

  /// [snapshot], refused when the file does not parse cleanly.
  Snapshot get snapshotToEdit => sourceIndex.snapshotToEdit(file);

  /// The top-level class [name] in [unit], or a refusal naming this file.
  ClassDeclaration classIn(CompilationUnit unit, String name) =>
      classNamed(unit, name) ??
      (throw FrxRefusal('class $name not found in "${file.path}".'));
}

/// The file at [relativePath] under the project root found from [startDir]
/// (or the current directory) — see [walkUpForMarker] for how the root is
/// found. For a caller with no workspace yet; one that holds a workspace joins
/// onto its root instead.
File locateFile(String relativePath, {String? startDir}) {
  final root = walkUpForMarker(
    startDir,
    relativePath,
    (origin) =>
        'Could not find "$relativePath" walking up from "$origin". '
        'Run this from inside the monorepo, or pass --root.',
  );
  return File(p.join(root.path, relativePath));
}
