/// Reading and parsing a Dart file, in one place.
///
/// Twenty call sites across nine files call `parseString` directly, none of
/// them caching, and the cost lands where it is felt: `frx graph` parses an
/// action file four times, `frx doctor` parses the router three times and walks
/// `app/lib`, `ui/lib` and `business/lib` twice apiece. The editor re-runs the
/// audit on filesystem events, so that is paid while somebody is typing.
///
/// The reader tier — flow, graph, routing, redux — and the audit both read
/// through it.
///
/// ## Strictness is a policy, not a per-call-site accident
///
/// The tier is currently split between parsing that throws on a diagnostic and
/// parsing that does not, with no rule saying which applies where. The rule:
///
/// - A file frx is about to **edit** must parse cleanly — [unitToEdit]. Every
///   edit in this codebase is a character-offset splice computed against a tree,
///   and offsets taken from a tree built out of broken source do not describe
///   the file they will be applied to.
/// - A file frx is only **reading to report on** must not — [unitFor]. One
///   unparseable file in somebody's repo must not take the whole audit down, and
///   a recovered tree still answers most of what a check asks.
///
/// ## What is cached is the parse, not the file
///
/// Every lookup reads the file; only an unchanged one skips the parse. Reading
/// is what this module is *not* trying to save — parsing is far dearer, and a
/// cache keyed on anything cheaper than the content gets it wrong. Keying on
/// modification time and length was tried first, and a same-length rewrite
/// inside one filesystem timestamp tick served the stale tree about half the
/// time (96 of 200 in one measurement here; it is a race, so the figure moves).
/// That is precisely the read-compute-write-reread shape a batch has.
///
/// A parse therefore needs no invalidation. A *listing* is a different animal —
/// it is a snapshot of a directory, and nothing checks it again — so an index
/// must not outlive the read that made it. [inSourceIndex] is that scope.
library;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../workspace/frx_workspace.dart';

/// One run's worth of parsed Dart.
class SourceIndex {
  SourceIndex();

  final _units = <String, _Entry>{};
  final _listings = <String, List<FileSystemEntity>>{};

  /// How many times a file was actually parsed.
  ///
  /// Exposed because "parsed once" and "not parsed at all on a pre-filter miss"
  /// are the two properties this module exists for, and a property nothing can
  /// observe is a property nothing can hold it to.
  int get parses => _parseCounts.values.fold(0, (a, b) => a + b);

  /// How many times [file] in particular was parsed.
  ///
  /// The total alone cannot see the duplication this module was built to end:
  /// a reader that regressed to parsing a file itself would make the total go
  /// *down*, not up. Only the per-file count says "once".
  int parsesOf(File file) => _parseCounts[p.canonicalize(file.path)] ?? 0;

  final _parseCounts = <String, int>{};

  /// How many times a directory was actually walked.
  ///
  /// The listing half of the same property: "the audit walks app, ui and
  /// business once apiece" is not observable from parse counts, because a
  /// second walk of an unchanged tree adds no parses at all.
  int get walks => _walkCounts.values.fold(0, (a, b) => a + b);

  /// How many times [dir] in particular was walked, however it was asked for.
  ///
  /// Per directory, not just a total: a listing is keyed by its flags too, so
  /// the same directory listed two ways is two walks — which a total cannot
  /// distinguish from two directories listed once each.
  int walksOf(Directory dir) => _walkCounts[p.canonicalize(dir.path)] ?? 0;

  final _walkCounts = <String, int>{};

  /// The tree for [file].
  ///
  /// Tolerant: a file with syntax errors yields the analyzer's recovered tree
  /// rather than throwing. See the strictness rule on [SourceIndex].
  CompilationUnit unitFor(File file) => _entry(file, parse: true).unit!;

  /// The tree for [file], for a caller about to compute edit offsets against it.
  ///
  /// Throws [StateError] when the file does not parse cleanly — the convention
  /// the runner renders as `✗ <message>` and exits 70 by, because "the file you
  /// asked me to edit does not compile" is the user's problem to fix, not a
  /// crash.
  CompilationUnit unitToEdit(File file) {
    final entry = _entry(file, parse: true);
    if (entry.hasErrors) {
      throw StateError(
        '${p.relative(file.path)} does not parse. frx edits by splicing at '
        'offsets read off the parse tree, and a tree recovered from broken '
        'source does not describe the file — fix the syntax error first.',
      );
    }
    return entry.unit!;
  }

  /// The tree for [file], or null when [wanted] rejects its text.
  ///
  /// The cheap half of every sweep in this codebase: parsing every file to find
  /// the handful that could match is what makes an audit something you avoid
  /// running. On a miss the file is read and **not** parsed.
  ///
  /// A predicate rather than a list of needles, because the real filters are not
  /// all the same shape: the placement rules want `extension` *and* `Select`, or
  /// `@RoutePage`. A caller that needs to know *which* matched should ask
  /// [sourceOf] and then [unitFor] — the same two lookups, without a closure
  /// that has to run for the answer to be right.
  CompilationUnit? unitIf(File file, bool Function(String source) wanted) {
    final entry = _entry(file, parse: false);
    if (!wanted(entry.source)) return null;
    return _entry(file, parse: true).unit!;
  }

  /// The source of [file].
  String sourceOf(File file) => _entry(file, parse: false).source;

  /// The files whose tree the analyzer recovered from broken source, sorted.
  ///
  /// The index is the only module that can say: tolerance is its policy, and
  /// [unitFor] hands a recovered tree back looking exactly like a clean one. So
  /// every answer built from one is a guess presented as a fact — a graph node
  /// for a class the analyzer inferred, an audit that found no `@RoutePage` in a
  /// file whose annotation it could not read.
  ///
  /// Only what this run actually parsed: a sweep that pre-filters on text
  /// ([unitIf]) never parses a file it rejected, and a file nothing read is a
  /// file nothing claimed anything about.
  List<File> get recovered => [
    for (final entry in _units.entries)
      if (entry.value.hasErrors) File(entry.key),
  ]..sort((a, b) => a.path.compareTo(b.path));

  /// Dart files under [dir].
  ///
  /// Generated output is excluded by default: it is nobody's decision, and it is
  /// the bulk of what a recursive listing returns. The carcass check is the one
  /// caller that wants it — what a removed substate left behind is exactly the
  /// generated file nothing regenerates.
  List<File> filesUnder(
    Directory dir, {
    bool recursive = true,
    bool includeGenerated = false,
  }) {
    final key =
        'f${recursive ? 'r' : ''}${includeGenerated ? 'g' : ''}:'
        '${p.canonicalize(dir.path)}';
    return _listing(dir, key, recursive, (e) {
      if (e is! File || !e.path.endsWith('.dart')) return false;
      if (e.path.contains('.dart_tool')) return false;
      return includeGenerated || !FrxWorkspace.isGenerated(e.path);
    }).cast<File>();
  }

  /// Immediate subdirectories of [dir] — the substate folders under `redux/`,
  /// and the like.
  List<Directory> directoriesIn(Directory dir) => _listing(
    dir,
    'd:${p.canonicalize(dir.path)}',
    false,
    (e) => e is Directory,
  ).cast<Directory>();

  List<FileSystemEntity> _listing(
    Directory dir,
    String key,
    bool recursive,
    bool Function(FileSystemEntity) keep,
  ) {
    final cached = _listings[key];
    if (cached != null) return cached;
    // A directory that is not there is not cached: `docs/flows/` and
    // `ui/lib/previews/` are opt-in, and a run that creates one must see it.
    if (!dir.existsSync()) return const [];
    // Sorted: a listing feeds node order in `frx graph` and section order in
    // the docs export, and `listSync` promises no order at all — so the same
    // tree produced a different file on a different filesystem.
    _walkCounts.update(
      p.canonicalize(dir.path),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    return _listings[key] = [
      for (final e in dir.listSync(recursive: recursive))
        if (keep(e)) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  _Entry _entry(File file, {required bool parse}) {
    final key = p.canonicalize(file.path);
    final source = file.readAsStringSync();
    final cached = _units[key];
    if (cached != null && cached.source == source) {
      if (!parse || cached.unit != null) return cached;
    }
    if (!parse) return _units[key] = _Entry(source: source);

    final parsed = parseString(content: source, throwIfDiagnostics: false);
    _parseCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
    return _units[key] = _Entry(
      source: source,
      unit: parsed.unit,
      hasErrors: parsed.errors.isNotEmpty,
    );
  }
}

const _zoneKey = #frxSourceIndex;

/// The index in scope, or a throwaway when there is none.
///
/// Held in a zone rather than a mutable global, for the reason `console` gives
/// for the same choice: `dart test` runs a suite's cases on one isolate, so a
/// global is shared state between them. A process-global was tried and is the
/// wrong shape twice over — a listing is a snapshot of a directory, and `frx
/// batch` writes between intents.
///
/// Outside a scope every lookup gets a fresh index and therefore no caching.
/// That is the safe default: a caller that has not said how long its snapshot
/// is good for does not get one.
SourceIndex get sourceIndex =>
    (Zone.current[_zoneKey] as SourceIndex?) ?? SourceIndex();

/// Runs [body] against [index].
R withSourceIndex<R>(SourceIndex index, R Function() body) =>
    runZoned(body, zoneValues: {_zoneKey: index});

/// Runs [body] against a fresh index, unless one is already in scope.
///
/// What a top-level read wraps itself in. Nesting defers to the outer scope, so
/// a graph read that runs a route-map read inside it is one snapshot, not two.
R inSourceIndex<R>(R Function() body) => Zone.current[_zoneKey] != null
    ? body()
    : withSourceIndex(SourceIndex(), body);

class _Entry {
  _Entry({required this.source, this.unit, this.hasErrors = false});

  final String source;

  /// Null when the file has been read but deliberately not parsed — the
  /// pre-filter's whole point.
  final CompilationUnit? unit;

  final bool hasErrors;
}
