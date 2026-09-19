/// The actions on disk, under the identity the graph knows them by.
///
/// Read from disk rather than from the page flows: an action no page reaches
/// still exists, and leaving it out would hide exactly the dead code the
/// orphan list is meant to surface.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
import '../flow/flow_model.dart';
import '../flow/flow_reader.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'graph_model.dart';

/// An action plus the identity the graph knows it by.
class GraphAction {
  const GraphAction({
    required this.id,
    required this.substate,
    required this.file,
    required this.info,
    required this.imports,
    required this.isMain,
    required this.sharesFile,
  });

  final String id;
  final String substate;
  final String file;
  final ActionInfo info;

  /// The action files this action's own imports resolve to — carried from the
  /// same parse that produced [info], so following a cascade costs nothing.
  final Map<String, File> imports;

  /// Whether this is the file's first action — the one the file is named for,
  /// and the one that owns the file for every sweep that attributes by file.
  final bool isMain;

  /// Whether the file declares other actions beside this one, in which case
  /// the node carries a line so it opens at the right class.
  final bool sharesFile;

  String get className => info.className;

  GraphNode get node => GraphNode(
    id: id,
    kind: NodeKind.action,
    name: info.className,
    substate: substate,
    file: file,
    line: sharesFile ? info.line : null,
    column: sharesFile ? info.column : null,
    fields: {
      if (info.mixins.isNotEmpty) 'mixins': info.mixins,
      'isAsync': info.isAsync,
      if (info.throwsUserException) 'throwsUserException': true,
    },
  );
}

/// Every action under `business/lib/redux/*/actions/`, looked up the three
/// ways the graph asks for one: by file and class, by class name, and by
/// mixin.
class ActionIndex {
  ActionIndex._(this._byPath);

  /// Reads the actions off [workspace], each file through [reader] once.
  factory ActionIndex.read(FrxWorkspace workspace, FlowReader reader) {
    final byPath = <String, List<GraphAction>>{};
    // `substateDirsIn`, which is where the rule lives. This used to walk the
    // directory itself and skip `isSubstateDir` entirely, so an `actions/`
    // under `redux/services/` would have been read as a substate's; the first
    // fix applied the rule but spelled it here, which is the same duplication
    // one level down.
    for (final dir in workspace.substateDirsIn()) {
      final actionsDir = Directory(p.join(dir.path, 'actions'));
      // Before the name is parsed: a folder that is not a substate — `_shared/`,
      // `2fa/` — has no `actions/`, and its name is not an identifier.
      if (!actionsDir.existsSync()) {
        continue;
      }

      final substate = Casing.parse(p.basename(dir.path)).camel;
      for (final file in sourceIndex.filesUnder(actionsDir)) {
        final read = reader.readActionsWithImports(file);
        // A file here need not hold an action. The template's own idiom is a
        // `mixin … on Action` with the shared `reduce()`, and a mixin is never
        // dispatched — so a node for it could only ever be reported as reached
        // by nobody.
        if (!read.infos.first.declaresClass) {
          continue;
        }

        final main = read.infos.first.className;
        final qualifier = main.startsWith('_')
            ? Casing.parse(p.basenameWithoutExtension(file.path)).pascal
            : main;
        byPath[p.canonicalize(file.path)] = [
          for (final (i, info) in read.infos.indexed)
            GraphAction(
              id: _idOf(substate, qualifier, info.className),
              substate: substate,
              file: file.path,
              info: info,
              imports: read.actionFiles,
              isMain: i == 0,
              sharesFile: read.infos.length > 1,
            ),
        ];
      }
    }

    return ActionIndex._(byPath);
  }

  /// `action:<substate>.<Class>` for a public class. A private one is
  /// library-private, so two files in one substate may each declare a
  /// `_Started` — and did, on the project this was written against. Its id is
  /// qualified with the file, named by the action the file is for:
  /// `action:setup.InstallSkillsAction._AgentWorking`. The main action's
  /// class rather than the file's stem, because the class is what the rest of
  /// the graph shows and the two need not agree — `register_mcp_action.dart`
  /// declares `InstallMcpAction`. The stem stands in only for a file whose
  /// main action is itself private.
  static String _idOf(String substate, String qualifier, String className) =>
      className.startsWith('_')
      ? 'action:$substate.$qualifier.$className'
      : 'action:$substate.$className';

  /// Keyed by canonical path, in listing order; each file's actions in
  /// source order, the main one first.
  final Map<String, List<GraphAction>> _byPath;

  Iterable<GraphAction> get all sync* {
    for (final actions in _byPath.values) {
      yield* actions;
    }
  }

  /// The actions declared in [file], main first — empty when frx models none
  /// there.
  List<GraphAction> inFile(File file) =>
      _byPath[p.canonicalize(file.path)] ?? const [];

  /// The action called [className] in [file], or null when the file declares
  /// no such action.
  GraphAction? at(File file, String className) {
    for (final a in inFile(file)) {
      if (a.className == className) {
        return a;
      }
    }
    return null;
  }

  /// Every action called [className] — one per substate that declares it,
  /// which is why a bare class name cannot be a node id.
  List<GraphAction> named(String className) => _byClass[className] ?? const [];

  /// Every action carrying [mixin] in its `with` clause.
  List<GraphAction> withMixin(String mixin) => _byMixin[mixin] ?? const [];

  late final Map<String, List<GraphAction>> _byClass = _group(
    (a) => [a.info.className],
  );

  late final Map<String, List<GraphAction>> _byMixin = _group(
    (a) => a.info.mixins,
  );

  Map<String, List<GraphAction>> _group(
    Iterable<String> Function(GraphAction) keysOf,
  ) {
    final out = <String, List<GraphAction>>{};
    for (final a in all) {
      // Once per key, however the source spells it: an action belongs to a
      // group, it is not counted per mention.
      for (final key in {...keysOf(a)}) {
        out.putIfAbsent(key, () => []).add(a);
      }
    }
    return out;
  }
}
