import 'dart:io';

import 'package:path/path.dart' as p;

import '../ast/source_index.dart';

/// Walks up from [startDir] (or the current directory) until an ancestor
/// containing [marker] (a repo-relative path) is found, returning that ancestor
/// directory. Throws [StateError] with `describe(origin)` when neither the walk
/// up nor the search below finds one.
///
/// The single walk-up primitive: [FrxWorkspace], [AppStateSource] and
/// [RoutesSource] all resolve their roots through it, each supplying its own
/// marker and not-found message, so the loop body lives in exactly one place.
///
/// **Up first, then down.** Walking up alone assumes the project is at or above
/// where you stand, which is true only when the project *is* the repository. A
/// template unpacked into somebody else's monorepo is not: `bloom/` is a pub
/// workspace whose own root has no router, and the app sits in
/// `apps/tm_console`. Every command run from `bloom/` failed with "run this from
/// inside the monorepo" while the project was one directory down — a correct
/// message about the wrong assumption.
///
/// The search below is deliberately narrow. It answers only when **exactly one**
/// project is under [startDir]; with two, picking one would mean writing into an
/// app nobody named, so it stays an error and says which ones it found.
Directory walkUpForMarker(
  String? startDir,
  String marker,
  String Function(String origin) describe,
) {
  // Absolute *then* normalised, and the order is the whole point: `p.normalize`
  // leaves a bare `.` as `.`, and `Directory('.').absolute` concatenates without
  // normalising, so normalising first still produced `<cwd>/.` — which then
  // travelled into every path the command printed and every `--root` it passed
  // on. Caught by review after the first fix claimed to have closed it.
  final origin = p.normalize(p.absolute(startDir ?? Directory.current.path));
  var dir = Directory(origin);
  while (true) {
    if (File(p.join(dir.path, marker)).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  final below = _searchBelow(origin, marker);
  if (below.length == 1) return below.single;
  if (below.length > 1) {
    final names = below.map((d) => p.relative(d.path, from: origin)).toList()
      ..sort();
    throw StateError(
      '${below.length} frx projects are under "$origin" '
      '(${names.join(', ')}). Pass --root to name the one you mean.',
    );
  }
  throw StateError(describe(origin));
}

/// The downward search, run only where it can pay off and only once per
/// question.
///
/// **Two bounds, and both were bought with a cost that showed up in review.**
///
/// The scan used to run on *every* failed walk-up, so a command typed in a home
/// directory walked three levels of everything under it before reporting the
/// same "not inside a frx project" it used to report instantly. Now the origin
/// has to look like somewhere a project could have been unpacked — a directory
/// with a `pubspec.yaml` or a `.git` — which is true of `bloom/` (the case this
/// exists for) and false of the places the cost was paid in.
///
/// And [TargetResolver] asks this three times per command, once per marker
/// (`app_router.dart`, `app_state.dart`, …), so one `frx remove` outside a
/// project paid for three full scans. Memoised per question, which is safe for
/// a process that lives for one command.
List<Directory> _searchBelow(String origin, String marker) {
  final dir = Directory(origin);
  final plausible =
      File(p.join(origin, 'pubspec.yaml')).existsSync() ||
      Directory(p.join(origin, '.git')).existsSync();
  if (!plausible) return const [];
  final question = (origin, marker);
  return _searched.putIfAbsent(
    question,
    () => _holdersBelow(dir.absolute, marker),
  );
}

/// Keyed by the pair, not by a joined string.
///
/// The joined form needed a separator no path can contain, which is NUL — and a
/// literal NUL makes the whole `.dart` file binary to every tool that decides by
/// scanning for one. `grep -I` skips such a file entirely, so this module — the
/// one that owns the monorepo's layout — returned no hits anywhere in the
/// repository for `notSubstateDirs`, `isSubstateDir`, `packageRootOf` or
/// `marker`. The code was correct and unfindable, which is the worse failure:
/// nothing reports it, and the next reader concludes the declaration is missing.
///
/// A record key needs no separator, so there is nothing left to encode.
final _searched = <(String, String), List<Directory>>{};

/// How far below the origin a project is looked for — the same bound the editor
/// extension uses, covering `apps/<name>`, `packages/<name>` and one grouping
/// level above those.
const _searchDepth = 3;

/// Never descended into: build output, platform shells and dependency trees.
/// All are large and none can hold a project of ours.
const _skipDirs = {
  'build',
  'node_modules',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
  'web',
};

/// Directories under [from] that hold [marker], outermost first. A hit is not
/// descended into: its own packages are packages, not projects.
List<Directory> _holdersBelow(Directory from, String marker, [int depth = 0]) {
  if (File(p.join(from.path, marker)).existsSync()) return [from];
  if (depth >= _searchDepth) return const [];

  final List<FileSystemEntity> entries;
  try {
    entries = from.listSync(followLinks: false);
  } on FileSystemException {
    return const []; // unreadable — a permission or a race, not our business
  }

  return [
    for (final entry in entries.whereType<Directory>())
      if (!p.basename(entry.path).startsWith('.') &&
          !_skipDirs.contains(p.basename(entry.path)))
        ..._holdersBelow(entry, marker, depth + 1),
  ];
}

/// The resolved monorepo: its root plus the well-known package directories the
/// scaffolders write into. Resolved once (via [locate]) and passed down, so no
/// command re-walks the tree.
///
/// Also the home for the two filesystem facts every command needs — which files
/// are generated ([isGenerated]) and which package a file belongs to
/// ([packageRootOf]) — so those rules live here instead of being copied into
/// each command.
class FrxWorkspace {
  FrxWorkspace(this.root);

  final Directory root;

  /// The marker that identifies the repo root — the same file [RoutesSource]
  /// keys on, so both agree on where the monorepo begins.
  ///
  /// Public because the editor needs it too, and used to carry its own copy:
  /// `ContractGen` emits it into the extension's generated constants rather
  /// than anyone keeping a fourth declaration in step by hand.
  static const marker = 'app/lib/navigation/app_router.dart';

  static FrxWorkspace locate({String? startDir}) => FrxWorkspace(
    walkUpForMarker(
      startDir,
      marker,
      (origin) =>
          'Could not find the monorepo root (looking for "$marker") walking '
          'up from "$origin". Run this from inside the monorepo, or pass --root.',
    ),
  );

  Directory _dir(List<String> parts) =>
      Directory(p.joinAll([root.path, ...parts]));

  Directory get uiWidgets => _dir(['ui', 'lib', 'widgets']);
  Directory get uiThemeExtensions => _dir(['ui', 'lib', 'theme', 'extensions']);
  Directory get uiPages => _dir(['ui', 'lib', 'pages']);
  Directory get uiLib => _dir(['ui', 'lib']);

  /// Where previews mirror the package: previews for `ui/lib/<dir>/<name>.dart`
  /// live in `ui/lib/previews/<dir>/<name>.dart`.
  ///
  /// The tree must stay under `lib/` — the widget previewer imports each file
  /// by its `package:` URI, and a file outside `lib/` has none, which crashes
  /// the tool rather than being skipped.
  Directory get uiPreviews => _dir(['ui', 'lib', 'previews']);

  /// Directories under `ui/lib/` that hold widgets, by folder name, sorted.
  ///
  /// Backs both `--dir` completion and the extension's folder picker, so the
  /// two never disagree about what exists. The list is a suggestion, not the
  /// allowed set: `--dir` also takes a name that does not exist yet, and
  /// creates it.
  ///
  /// Only folders that already contain a `.dart` file are offered. An empty
  /// folder is not an established home — offering `widgets/`, left behind by
  /// the old default, would keep steering new widgets into the folder nobody
  /// uses.
  List<String> widgetDirs() {
    final lib = uiLib;
    if (!lib.existsSync()) return const [];
    final names = <String>[
      for (final e in lib.listSync().whereType<Directory>())
        if (!notWidgetDirs.contains(p.basename(e.path)) &&
            e.listSync().whereType<File>().any((f) => f.path.endsWith('.dart')))
          p.basename(e.path),
    ]..sort();
    return names;
  }

  /// Folders under `ui/lib/` that are not widget homes: generated output, the
  /// theme layer, view-models, the previews mirror, and `pages/` — a page is
  /// scaffolded by `add-page`, which also wires its route.
  ///
  /// Both a filter for [widgetDirs] and a guard for `add-widget --dir`: a
  /// folder that is not worth suggesting is not worth writing into either.
  /// Without the second use, `--dir previews` would put a widget inside its own
  /// mirror and its preview in `previews/previews/`.
  static const notWidgetDirs = {
    'previews',
    'theme',
    'models',
    'generated',
    'l10n',
    'pages',
  };

  /// Folders under `business/lib/redux/` that are not substates.
  ///
  /// The sibling of [notWidgetDirs], and it lives here for the same reason:
  /// "which folders under this directory are artifacts" is a fact about the
  /// monorepo's layout, not about whichever command asks first. It was spelled
  /// out three times — in `add-action`'s substate list, in `doctor`'s orphan
  /// scan, and again in TypeScript in the editor's "New here" menu — so a
  /// fourth kind of shared folder would have had to be found three times.
  static const notSubstateDirs = {'common', 'models', 'services'};

  /// The substate folder names, sorted. A directory under `redux/` that is not
  /// in [notSubstateDirs] and is not hidden.
  List<String> substateDirs() =>
      [for (final dir in substateDirsIn()) p.basename(dir.path)]..sort();

  /// The same folders as [substateDirs], as directories and unsorted.
  ///
  /// Split out because the graph reader wants the directories themselves and
  /// had grown its own copy of the rule to get them — `directoriesIn` plus
  /// `isSubstateDir`, spelled a second time, which is the duplication that
  /// consolidation was supposed to end. One statement, and both callers share
  /// the index's cached listing rather than walking `redux/` twice in a run
  /// that asks both.
  List<Directory> substateDirsIn() {
    final dir = businessRedux;
    if (!dir.existsSync()) return const [];
    return [
      for (final entry in sourceIndex.directoriesIn(dir))
        if (isSubstateDir(p.basename(entry.path))) entry,
    ];
  }

  /// Whether a folder name directly under `redux/` names a substate.
  static bool isSubstateDir(String name) =>
      !name.startsWith('.') && !notSubstateDirs.contains(name);

  Directory get appLib => _dir(['app', 'lib']);
  Directory get appConnectors => _dir(['app', 'lib', 'connectors']);
  Directory get businessLib => _dir(['business', 'lib']);
  Directory get businessRedux => _dir(['business', 'lib', 'redux']);
  Directory get businessServices =>
      _dir(['business', 'lib', 'redux', 'services']);
  Directory get httpApi => _dir(['http_client', 'lib', 'api']);
  Directory get modelsLib => _dir(['models', 'lib']);

  /// The selector facade beside `app_state.dart`. Named here so a command that
  /// already has a workspace does not have to locate `AppState` just to find the
  /// file sitting next to it.
  File get selectorsFile => File(p.join(businessRedux.path, 'selectors.dart'));

  /// Whether [path] is build_runner output (freezed / json_serializable /
  /// theme_extensions / auto_route). The one place the generated-file suffixes
  /// are listed — sweeps, deletions and part-checks all defer to it.
  static bool isGenerated(String path) =>
      path.endsWith('.freezed.dart') ||
      path.endsWith('.g.dart') ||
      path.endsWith('.g.theme.dart') ||
      path.endsWith('.gr.dart');

  /// Walks up from [filePath] to the nearest directory containing a
  /// `pubspec.yaml` — the package root where build_runner must run. Falls back
  /// to the file's own directory if none is found.
  static String packageRootOf(String filePath) {
    var dir = File(filePath).parent;
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) return File(filePath).parent.path;
      dir = parent;
    }
  }
}
