import 'dart:io';

import 'package:path/path.dart' as p;

/// Walks up from [startDir] (or the current directory) until an ancestor
/// containing [marker] (a repo-relative path) is found, returning that ancestor
/// directory. Throws [StateError] with `describe(origin)` when the filesystem
/// root is reached without a hit.
///
/// The single walk-up primitive: [FrxWorkspace], [AppStateSource] and
/// [RoutesSource] all resolve their roots through it, each supplying its own
/// marker and not-found message, so the loop body lives in exactly one place.
Directory walkUpForMarker(
  String? startDir,
  String marker,
  String Function(String origin) describe,
) {
  final origin = startDir ?? Directory.current.path;
  var dir = Directory(origin).absolute;
  while (true) {
    if (File(p.join(dir.path, marker)).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError(describe(origin));
    dir = parent;
  }
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
  static const _marker = 'app/lib/navigation/app_router.dart';

  static FrxWorkspace locate({String? startDir}) => FrxWorkspace(
    walkUpForMarker(
      startDir,
      _marker,
      (origin) =>
          'Could not find the monorepo root (looking for "$_marker") walking '
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
  List<String> substateDirs() {
    final dir = businessRedux;
    if (!dir.existsSync()) return const [];
    return [
      for (final entry in dir.listSync().whereType<Directory>())
        if (isSubstateDir(p.basename(entry.path))) p.basename(entry.path),
    ]..sort();
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
