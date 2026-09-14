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
  });

  final String id;
  final String substate;
  final String file;
  final ActionInfo info;

  /// The action files this action's own imports resolve to — carried from the
  /// same parse that produced [info], so following a cascade costs nothing.
  final Map<String, File> imports;

  GraphNode get node => GraphNode(
    id: id,
    kind: NodeKind.action,
    name: info.className,
    substate: substate,
    file: file,
    fields: {
      if (info.mixins.isNotEmpty) 'mixins': info.mixins,
      'isAsync': info.isAsync,
      if (info.throwsUserException) 'throwsUserException': true,
    },
  );
}

/// Every action under `business/lib/redux/*/actions/`, looked up the three
/// ways the graph asks for one: by file, by class name, and by mixin.
class ActionIndex {
  ActionIndex._(this._byPath);

  /// Reads the actions off [workspace], each through [reader] once.
  factory ActionIndex.read(FrxWorkspace workspace, FlowReader reader) {
    final byPath = <String, GraphAction>{};
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
        final read = reader.readActionWithImports(file);
        // A file here need not hold an action. The template's own idiom is a
        // `mixin … on Action` with the shared `reduce()`, and a mixin is never
        // dispatched — so a node for it could only ever be reported as reached
        // by nobody.
        if (!read.info.declaresClass) {
          continue;
        }
        byPath[p.canonicalize(file.path)] = GraphAction(
          id: 'action:$substate.${read.info.className}',
          substate: substate,
          file: file.path,
          info: read.info,
          imports: read.actionFiles,
        );
      }
    }
    return ActionIndex._(byPath);
  }

  /// Keyed by canonical path, in listing order.
  final Map<String, GraphAction> _byPath;

  Iterable<GraphAction> get all => _byPath.values;

  /// The action declared in [file], or null when frx models none there.
  GraphAction? at(File file) => _byPath[p.canonicalize(file.path)];

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
