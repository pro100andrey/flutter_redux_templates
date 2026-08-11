import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../flow/flow_model.dart';
import '../ast/declarations.dart';
import '../ast/source_index.dart';
import '../flow/flow_reader.dart';
import '../flow/route_map.dart';
import '../model/placement.dart';
import '../model/selector_shape.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'graph_model.dart';

/// Joins every reader frx already has into one [AppGraph].
///
/// The readers each answer a narrow question — what does this page do, what
/// routes exist, what is composed into AppState. Answering "who can change
/// `session.token`" needs them joined, and joining them raises two problems
/// this class exists to solve:
///
/// * **Identity.** A `PageFlow` keys actions by class name, which is unambiguous
///   *within* one page because it was resolved through that connector's
///   imports. Globally it is not: this repo has three `SetEmailAction`s. Node
///   ids are therefore qualified with the owning substate, derived from the
///   file path — which leaves `frx flow --json` untouched.
/// * **Coverage.** Walking connectors finds only what a screen dispatches. An
///   action dispatched by a service dispatcher, or by another action, would read as
///   dispatched by nobody.
class GraphReader {
  GraphReader(this.workspace);

  final FrxWorkspace workspace;

  AppGraph read() => inSourceIndex(_read);

  AppGraph _read() {
    final nodes = <String, GraphNode>{};
    final edges = <String, GraphEdge>{};
    final unresolved = <Unresolved>[];

    void addNode(GraphNode n) => nodes.putIfAbsent(n.id, () => n);
    void addEdge(GraphEdge e) => edges.putIfAbsent(e.key, () => e);

    /// Canonical file path → the node that owns it, for the files that read
    /// selectors: a connector, an action, a service dispatcher. Collected as each
    /// section runs so the selector pass can say *who* reads what, rather than
    /// re-deriving the same file-to-artifact map a third time.
    final owners = <String, String>{};

    final flowReader = FlowReader(workspace);

    // ---- substates ----------------------------------------------------
    final appState = AppStateSource.of(workspace);
    for (final s in appState.readSubstates()) {
      addNode(
        GraphNode(
          id: 'substate:${s.field}',
          kind: NodeKind.substate,
          name: s.field,
          // Non-…State framework fields (async_redux's `wait`) have no folder
          // of ours — same rule `list-substates` applies to its `file` column.
          file: s.isSubstate
              ? SubstateArtifact.parse(
                  s.field,
                ).stateFile(appState.reduxDir).path
              : null,
          fields: {'type': s.type},
        ),
      );
    }

    // ---- actions ------------------------------------------------------
    // Read from disk rather than from the page flows: an action no page reaches
    // still exists, and leaving it out would hide exactly the dead code the
    // orphan list is meant to surface.
    final actions = _actionsOnDisk(flowReader);
    for (final a in actions.values) {
      addNode(_actionNode(a));
      owners[a.file] = a.id;
      // One edge per substate touched, off the structured writes. This used to
      // split the display string back apart on the `', '` the renderer joined
      // it with.
      for (final w in a.info.writes) {
        if (!nodes.containsKey('substate:${w.substate}')) continue;
        addEdge(
          GraphEdge(
            from: a.id,
            to: 'substate:${w.substate}',
            kind: EdgeKind.writes,
            via: w.label,
          ),
        );
      }
    }

    /// Resolves a dispatched class name to a node id, adding a placeholder node
    /// plus an [Unresolved] note when it cannot be pinned to a file.
    ///
    /// [owner] is the node whose reading hit the gap — what makes the note
    /// attributable to a subgraph rather than only to the whole project.
    String dispatchTarget(
      String className,
      File? file,
      String at, {
      required String owner,
    }) {
      final resolved = file == null ? null : actions[p.canonicalize(file.path)];
      if (resolved != null) return resolved.id;
      final id = 'action:$className';
      addNode(
        GraphNode(
          id: id,
          kind: NodeKind.action,
          name: className,
          resolved: false,
        ),
      );
      unresolved.add(
        Unresolved(
          kind: 'dispatch-target',
          owner: owner,
          at: at,
          expr: className,
          why:
              'dispatched, but no imported `*_action.dart` declares it — a '
              'factory, an alias, or an action outside business/lib/redux',
        ),
      );
      return id;
    }

    // ---- cascades: an action dispatching another ----------------------
    for (final a in actions.values) {
      for (final step in a.info.dispatches) {
        if (step.isNavigation) continue;
        addEdge(
          GraphEdge(
            from: a.id,
            to: dispatchTarget(
              step.target,
              a.imports[step.target],
              a.file,
              owner: a.id,
            ),
            kind: EdgeKind.dispatches,
            condition: step.condition,
          ),
        );
      }
    }

    // ---- pages, navigation, and what a screen dispatches ---------------
    final map = RouteMapReader(workspace).read();
    for (final page in map.pages) {
      addNode(
        GraphNode(
          id: 'page:${page.page}',
          kind: NodeKind.page,
          name: page.page,
          file: page.connectorFile,
          fields: {
            'route': page.routeType,
            'pageClass': page.pageClass,
            if (page.path != null) 'path': page.path,
            if (page.parent != null) 'parent': page.parent,
            'initial': page.initial,
            'public': page.public,
          },
        ),
      );
      if (page.connectorFile != null)
        owners[page.connectorFile!] = 'page:${page.page}';
      if (page.connectorFile == null) {
        unresolved.add(
          Unresolved(
            kind: 'route-connector',
            owner: 'page:${page.page}',
            at: page.routeType,
            why:
                'the route is registered but has no connector file, so nothing '
                'it dispatches or navigates to could be read',
          ),
        );
      }
    }

    for (final e in map.edges) {
      if (e.to == null) {
        unresolved.add(
          Unresolved(
            kind: 'pop-destination',
            owner: 'page:${e.from}',
            at: 'page:${e.from}',
            expr: 'GoAction.${e.method}',
            why: e.kind == NavKind.pop
                ? 'pop with no single pusher — the destination is whatever is '
                      'on the stack, which the source does not state'
                : 'navigation target is not a literal route',
          ),
        );
        continue;
      }
      addEdge(
        GraphEdge(
          from: 'page:${e.from}',
          to: 'page:${e.to}',
          kind: EdgeKind.navigates,
          via: e.via,
          condition: e.condition,
          inferred: e.inferred,
        ),
      );
    }

    for (final entry in map.flows.entries) {
      final flow = entry.value;
      for (final useCase in flow.useCases) {
        for (final step in useCase.steps) {
          if (step.isNavigation) continue;
          final info = flow.actions[step.target];
          addEdge(
            GraphEdge(
              from: 'page:${entry.key}',
              to: dispatchTarget(
                step.target,
                info?.file == null ? null : File(info!.file!),
                flow.connectorFile ?? 'page:${entry.key}',
                owner: 'page:${entry.key}',
              ),
              kind: EdgeKind.dispatches,
              via: useCase.label,
              condition: step.condition,
            ),
          );
        }
      }
    }

    // ---- services ------------------------------------------------------
    for (final file in sourceIndex.filesUnder(workspace.businessServices)) {
      final read = flowReader.readDispatches(file);
      if (read.steps.isEmpty) continue;
      final name =
          firstClassNameIn(sourceIndex.unitFor(file)) ??
          Casing.parse(p.basenameWithoutExtension(file.path)).pascal;
      final id = 'service:$name';
      addNode(
        GraphNode(id: id, kind: NodeKind.service, name: name, file: file.path),
      );
      owners[file.path] = id;
      for (final step in read.steps) {
        if (step.isNavigation) continue;
        addEdge(
          GraphEdge(
            from: id,
            to: dispatchTarget(
              step.target,
              read.actionFiles[step.target],
              file.path,
              owner: id,
            ),
            kind: EdgeKind.dispatches,
            condition: step.condition,
          ),
        );
      }
    }

    // ---- the persistor ---------------------------------------------------
    // Searched by superclass rather than by a fixed path, so renaming the file
    // does not quietly drop it — the whole reason it is here is that its writes
    // were invisible. The string check keeps that generality cheap: every other
    // file under business/lib is rejected without being parsed.
    for (final file in sourceIndex.filesUnder(workspace.businessLib)) {
      final unit = sourceIndex.unitIf(file, (s) => s.contains('Persistor'));
      if (unit == null) continue;
      final v = _PersistorVisitor();
      unit.accept(v);
      final name = v.className;
      if (name == null) continue;
      final id = 'persistor:$name';
      addNode(
        GraphNode(
          id: id,
          kind: NodeKind.persistor,
          name: name,
          file: file.path,
        ),
      );
      for (final (fields, kind) in [
        (v.restores, EdgeKind.restores),
        (v.reads, EdgeKind.reads),
      ]) {
        for (final field in fields) {
          if (!nodes.containsKey('substate:$field')) continue;
          addEdge(GraphEdge(from: id, to: 'substate:$field', kind: kind));
        }
      }
    }

    // ---- selectors -------------------------------------------------------
    _readSelectors(
      appState,
      addNode: addNode,
      addEdge: addEdge,
      unresolved: unresolved,
      actions: actions,
      hasSubstate: (f) => nodes.containsKey('substate:$f'),
      owners: owners,
    );

    // ---- selectors declared outside the facade ---------------------------
    // The graph reads selector *declarations* from `selectors.dart` and nothing
    // else, while the placement rules sweep all three lib trees for them. So a
    // hand-written selector outside the facade was reported by the audit and
    // absent here: no node, no edges, and the selectors it reads counted as read
    // by nobody — which is a false "nothing reads this" in the dead-selector
    // analysis, the one place frx says "you can delete this".
    //
    // An unresolved entry rather than a node, because both halves matter. The
    // false reading goes away, since the selector is no longer absent. And the
    // misplacement is not dressed up as ordinary wiring: an unresolved entry is
    // a blind spot being declared, not a link being drawn.
    //
    // Asked of the module the audit asks, so the two cannot disagree about what
    // a selector is or where it may live — but *not* honouring `.frxrc`: a
    // project silencing the placement rule has said the file may stay there, not
    // that frx can now follow it.
    for (final finding in placementFindings(
      workspace,
      silenced: const {
        PlacementRule.actionOutsideActionsDir,
        PlacementRule.connectorOutsideConnectors,
      },
    )) {
      final rel = p.relative(finding.file, from: workspace.root.path);
      unresolved.add(
        Unresolved(
          kind: 'misplaced-selector',
          owner: 'file:$rel',
          at: finding.file,
          why:
              '$rel declares a selector outside the facade. frx reads selector '
              'declarations from selectors.dart only, so what this one reads and '
              'who reads it are both unknown here — move it to the facade and '
              'the graph can follow it.',
        ),
      );
    }

    // ---- what the analyzer had to guess at -------------------------------
    // Last, so it covers every file the passes above reached. The reader tier
    // is tolerant of unparseable source on purpose — one broken file must not
    // take a whole read down — and the tolerance was silent, which is worse
    // than the crash it replaced: a node built from a recovered tree answers
    // confidently, and nothing said which answers came from a file that does
    // not compile.
    //
    // Owned by the file rather than by a node: the gap is not in one edge, it
    // is in everything read from there. A focused view drops it, which is the
    // right trade — attributing it to whichever node happened to be nearby
    // would say the gap is somewhere it is not.
    for (final file in sourceIndex.recovered) {
      final rel = p.relative(file.path, from: workspace.root.path);
      unresolved.add(
        Unresolved(
          kind: 'unparsed-file',
          why:
              '$rel does not parse. What frx says about it was read off the '
              'tree the analyzer recovered, so nodes and edges from this file '
              'may be missing or invented — fix the syntax error and re-read.',
          owner: 'file:$rel',
          at: file.path,
        ),
      );
    }

    return AppGraph(
      nodes: nodes.values.toList(),
      edges: edges.values.toList(),
      unresolved: unresolved,
    );
  }

  /// Every action under `business/lib/redux/*/actions/`, by canonical path.
  Map<String, _Action> _actionsOnDisk(FlowReader reader) {
    final out = <String, _Action>{};
    if (!workspace.businessRedux.existsSync()) return out;
    // `substateDirsIn`, which is where the rule lives. This used to walk the
    // directory itself and skip `isSubstateDir` entirely, so an `actions/`
    // under `redux/services/` would have been read as a substate's; the first
    // fix applied the rule but spelled it here, which is the same duplication
    // one level down.
    for (final dir in workspace.substateDirsIn()) {
      final actionsDir = Directory(p.join(dir.path, 'actions'));
      if (!actionsDir.existsSync()) continue;
      final substate = Casing.parse(p.basename(dir.path)).camel;
      for (final file in sourceIndex.filesUnder(actionsDir)) {
        final read = reader.readActionWithImports(file);
        // A file here need not hold an action. The template's own idiom is a
        // `mixin … on Action` with the shared `reduce()`, and a mixin is never
        // dispatched — so a node for it could only ever be reported as reached
        // by nobody.
        if (!read.info.declaresClass) continue;
        out[p.canonicalize(file.path)] = _Action(
          id: 'action:$substate.${read.info.className}',
          substate: substate,
          file: file.path,
          info: read.info,
          imports: read.actionFiles,
        );
      }
    }
    return out;
  }

  GraphNode _actionNode(_Action a) => GraphNode(
    id: a.id,
    kind: NodeKind.action,
    name: a.info.className,
    substate: a.substate,
    file: a.file,
    fields: {
      if (a.info.mixins.isNotEmpty) 'mixins': a.info.mixins,
      'isAsync': a.info.isAsync,
      if (a.info.throwsUserException) 'throwsUserException': true,
    },
  );

  /// The `Select<Pascal>` extension types in `selectors.dart`.
  ///
  /// Selectors are what makes deleting an action break something far away:
  /// `isWaitingForType<ForgotPasswordAction>()` names the class with no import
  /// of its own to follow, so nothing else in the graph records the reference.
  void _readSelectors(
    AppStateSource appState, {
    required void Function(GraphNode) addNode,
    required void Function(GraphEdge) addEdge,
    required List<Unresolved> unresolved,
    required Map<String, _Action> actions,
    required bool Function(String) hasSubstate,
    required Map<String, String> owners,
  }) {
    // `FrxWorkspace.selectorsFile`, whose doc says it exists so a command
    // holding a workspace need not locate `AppState` to find the file beside
    // it. This located `AppState` to find it anyway — a third spelling of one
    // path.
    final file = workspace.selectorsFile;
    if (!file.existsSync()) return;

    final byClass = <String, List<_Action>>{};
    for (final a in actions.values) {
      byClass.putIfAbsent(a.info.className, () => []).add(a);
    }

    final parsed = sourceIndex.unitFor(file);
    final selectors = _SelectorVisitor.read(parsed);

    // How each selector is *called*, which is not how it is declared: one
    // hanging off a substate is reached as `<field>.<getter>`, a composite on
    // `Select` as a bare `<getter>`. Built before the loop so a composite can
    // resolve a selector declared after it.
    final selectorIds = <String, String>{};
    for (final s in selectors) {
      final owner = SubstateArtifact.substateOfSelectorType(s.ownerType);
      final site = owner != null && hasSubstate(owner)
          ? '$owner.${s.getter}'
          : s.getter;
      selectorIds[site] = s.id;
    }

    // A getter reached from *inside* the type that declares it, where the facade
    // hop above is not written: `email` inside `SelectLogIn`, or inside an
    // `extension … on SelectLogIn`. Keyed by owning type, because a bare name
    // means different getters on different types.
    final siblingIds = <String, Map<String, String>>{};
    for (final s in selectors) {
      (siblingIds[s.ownerType] ??= {})[s.getter] = s.id;
    }

    for (final s in selectors) {
      final id = s.id;
      final owner = SubstateArtifact.substateOfSelectorType(s.ownerType);
      // Every selector in the app shares this one file, so the offset is what
      // makes the node point at the getter rather than at the facade.
      final at = parsed.lineInfo.getLocation(s.offset);
      addNode(
        GraphNode(
          id: id,
          kind: NodeKind.selector,
          name: '${s.type}.${s.getter}',
          // Which substate it *belongs to* (from the facade type), not which
          // ones it reads — a composite selector reads several.
          substate: owner != null && hasSubstate(owner) ? owner : null,
          file: file.path,
          line: at.lineNumber,
          column: at.columnNumber,
        ),
      );

      for (final field in s.readsFields) {
        if (!hasSubstate(field)) continue;
        addEdge(
          GraphEdge(
            from: id,
            to: 'substate:$field',
            kind: EdgeKind.reads,
            via: s.getter,
          ),
        );
      }

      // A composite reads other selectors; those are `uses` edges like any
      // consumer's, so a chain read only by a dead composite reads as dead too.
      final body = s.body;
      final uses = body == null
          ? <String>{}
          : (selectorUsesIn(body, {...selectorIds, ...?siblingIds[s.ownerType]})
              ..remove(id));
      for (final target in uses) {
        addEdge(
          GraphEdge(from: id, to: target, kind: EdgeKind.uses, via: s.getter),
        );
      }

      for (final className in s.waitsForActions) {
        final candidates = byClass[className] ?? const <_Action>[];
        if (candidates.length == 1) {
          addEdge(
            GraphEdge(
              from: id,
              to: candidates.single.id,
              kind: EdgeKind.waitsFor,
              via: s.getter,
            ),
          );
          continue;
        }

        // The type argument may name a *mixin* rather than a class, and then it
        // means every action carrying it. `WaitAction.add(this)` files the
        // action itself as the flag and `isWaitingForType<T>` tests `flag is T`,
        // so `isWaitingForType<WaitingAction>()` — the modal barrier's whole
        // question — waits for all of them at once. Read before this existed, it
        // was an action class by that name, found none, and reported the barrier
        // as following something frx could not.
        final byMixin = [
          for (final a in actions.values)
            if (a.info.mixins.contains(className)) a,
        ];
        if (candidates.isEmpty && byMixin.isNotEmpty) {
          for (final a in byMixin) {
            addEdge(
              GraphEdge(
                from: id,
                to: a.id,
                kind: EdgeKind.waitsFor,
                via: s.getter,
              ),
            );
          }
          continue;
        }

        unresolved.add(
          Unresolved(
            kind: 'selector-action',
            owner: id,
            at: file.path,
            expr: 'isWaitingForType<$className>',
            why: candidates.isEmpty
                ? 'no action class by that name under business/lib/redux'
                : '${candidates.length} substates declare a $className — the '
                      'type argument alone does not say which',
          ),
        );
      }

      // A composite whose selectors *were* resolved is no longer a blind spot:
      // its dependencies are the `uses` edges above. Only a body frx could
      // follow in no way at all belongs here — a list that cries wolf gets
      // ignored, and the real gaps go with it.
      if (s.readsFields.isEmpty && s.waitsForActions.isEmpty && uses.isEmpty) {
        unresolved.add(
          Unresolved(
            kind: 'selector-body',
            owner: id,
            at: file.path,
            expr: '${s.type}.${s.getter}',
            why:
                'reads neither `_state.<substate>` nor an action type — a '
                'composite built from other selectors, whose dependencies are '
                'not recorded',
          ),
        );
      }
    }

    // ---- who reads them --------------------------------------------------
    // The only edges that point *into* a selector, and so the only way to ask
    // which ones nothing reads. Scanned from source rather than resolved: a
    // selector call is a plain getter, with no dispatch or annotation to key on.
    //
    // Every Dart file of the app's own packages, not just the ones that already
    // have a node. A read is a read whether or not frx models the reader, and
    // scanning only modelled files would report the selectors that only an
    // unrouted connector uses as dead — the one mistake here that costs
    // working code.
    for (final consumer in _consumerFiles()) {
      final path = p.canonicalize(consumer.path);
      if (path == p.canonicalize(file.path)) continue; // the facade itself
      final used = selectorUsesIn(sourceIndex.unitFor(consumer), selectorIds);
      if (used.isEmpty) continue;
      final from = owners[consumer.path] ?? owners[path];
      if (from == null) {
        // A reader with no node of its own — see [NodeKind.consumer].
        final name =
            firstClassNameIn(sourceIndex.unitFor(consumer)) ??
            Casing.parse(p.basenameWithoutExtension(consumer.path)).pascal;
        addNode(
          GraphNode(
            id: 'consumer:$name',
            kind: NodeKind.consumer,
            name: name,
            file: consumer.path,
          ),
        );
        for (final target in used) {
          addEdge(
            GraphEdge(from: 'consumer:$name', to: target, kind: EdgeKind.uses),
          );
        }
        continue;
      }
      for (final target in used) {
        addEdge(GraphEdge(from: from, to: target, kind: EdgeKind.uses));
      }
    }
  }

  /// Every Dart file of the app's own packages that could read a selector.
  Iterable<File> _consumerFiles() sync* {
    for (final dir in [
      Directory(p.join(workspace.root.path, 'app', 'lib')),
      workspace.businessLib,
      workspace.uiLib,
    ]) {
      yield* sourceIndex.filesUnder(dir);
    }
  }
}

/// An action plus the identity the graph knows it by.
class _Action {
  const _Action({
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
}

/// Reads the `Persistor` subclass: which substates it puts back on boot, and
/// which it reads back out to save.
///
/// It changes state without dispatching anything, so every other reader here is
/// blind to it. In this template it is the only thing besides `SetTokenAction`
/// that can put a token in `session` — leaving it out made "who can change
/// `session.token`" answer confidently and incompletely.
class _PersistorVisitor extends RecursiveAstVisitor<void> {
  String? className;

  /// Substates rebuilt in `readState()`.
  final restores = <String>{};

  /// Substates read in `persistDifference()`.
  final reads = <String>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final supertypes = [
      ?node.extendsClause?.superclass.toSource(),
      ...?node.implementsClause?.interfaces.map((i) => i.toSource()),
    ];
    if (!supertypes.any((t) => t.startsWith('Persistor'))) return;
    className = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (className == null) return;
    switch (node.name.lexeme) {
      case 'readState':
        // `AppState.initial().copyWith(theme: …, session: …)` — every named
        // argument is a substate being restored, not just the first.
        final v = _CopyWithArgs();
        node.body.accept(v);
        restores.addAll(v.fields);
      case 'persistDifference':
        // `newState.session`, `lastPersistedState?.theme` — the parameter names
        // come from the signature rather than being assumed, since they are the
        // author's to choose.
        final params =
            node.parameters?.parameters
                .map((p) => p.name?.lexeme)
                .nonNulls
                .toSet() ??
            const <String>{};
        if (params.isEmpty) return;
        // Off the tree, not off the text, for the reason [_BodyReader] gives:
        // a parameter named in a string literal is not a read of it.
        node.body.accept(_ParamFieldReads(params, reads));
    }
  }
}

/// Fields read off one of [_params] — `newState.session`,
/// `lastPersistedState?.theme`.
///
/// Both spellings, because `?.` is a [PropertyAccess] while `.` on a plain name
/// is a [PrefixedIdentifier], and the persistor uses each.
class _ParamFieldReads extends RecursiveAstVisitor<void> {
  _ParamFieldReads(this._params, this._into);

  final Set<String> _params;
  final Set<String> _into;

  /// Lower-case initial only, as the pattern this replaced required: a field is
  /// not a nested type name.
  void _add(String name) {
    if (name.isNotEmpty && name[0] == name[0].toLowerCase()) _into.add(name);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (_params.contains(node.prefix.name)) _add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && _params.contains(target.name)) {
      _add(node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }
}

/// Every named argument of every `copyWith(...)` in the visited subtree.
class _CopyWithArgs extends RecursiveAstVisitor<void> {
  final fields = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'copyWith') {
      for (final a in node.argumentList.arguments.whereType<NamedArgument>()) {
        fields.add(a.name.lexeme);
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// One getter on a `Select<Pascal>` extension type.
class _Selector {
  _Selector(this.type, this.ownerType, this.getter, this.offset);

  /// The type that *declares* the getter — the node's identity.
  final String type;

  /// The type the getter is *called* on, which is not always [type]: an
  /// `extension X on SelectLogIn` contributes to `SelectLogIn`, so its getters
  /// are reached as `select.logIn.<getter>` however `X` is named.
  final String ownerType;

  final String getter;

  /// The node id this getter is filed under — the declaring type, not the type
  /// it is called on, so two extensions on one selector stay distinct.
  String get id => 'selector:$type.$getter';

  /// Character offset of the getter's name, for the node's line/column.
  final int offset;
  final readsFields = <String>{};
  final waitsForActions = <String>{};

  /// Bare identifiers in the body, some of which name a getter alongside it.
  final siblings = <String>{};

  /// The getter's body, scanned for the selectors it calls once every selector
  /// is known (a composite can name one declared below it). Held as AST: a
  /// selector quoted in a string is not a read of it.
  FunctionBody? body;
}

/// A dotted chain — `context.session.token`, `_state.logIn.email`.
///
/// The selector ids [node] calls, given an index of call site → node id.
///
/// Walks the AST rather than scanning source text. Text scanning counted a
/// selector named in a comment or quoted in a string as a read, which made
/// "something reads this" untrustworthy in exactly the direction that hides
/// dead code — and the files are parsed here anyway.
///
/// Two call shapes, because a selector is reached two ways: `<substate>.<getter>`
/// for the ones hanging off a substate, and a bare `<getter>` for a composite
/// declared on `Select` itself.
///
/// Still deliberately generous about the bare shape: a composite's name can
/// collide with a local of the same name, which files a selector as used when
/// it is not. That direction costs a missed cleanup; the other one — reporting
/// a live selector as dead — invites someone to delete working code.
Set<String> selectorUsesIn(AstNode node, Map<String, String> index) {
  final visitor = _SelectorUseVisitor(index);
  node.accept(visitor);
  return visitor.used;
}

/// Finds selector reads by shape, so a mention in a comment or a string cannot
/// be one.
class _SelectorUseVisitor extends RecursiveAstVisitor<void> {
  _SelectorUseVisitor(this.index);

  final Map<String, String> index;
  final used = <String>{};

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _chain(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _chain(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A composite reached by its bare name — `if (canEnterApp)`. Skipped when
    // it is a segment of a chain, which `_chain` has already judged as a whole.
    final parent = node.parent;
    if (parent is PrefixedIdentifier || parent is PropertyAccess) return;
    final id = index[node.name];
    if (id != null) used.add(id);
  }

  /// Judges a dotted access by where the receiver sits in its chain.
  ///
  /// `logIn.email` is a selector: the receiver heads the chain, which is how a
  /// class mixing in `Selectors` reaches one. `state.select.logIn.email` is the
  /// same selector through the facade. `vm.logIn.email` and `_state.logIn.email`
  /// are not — a view-model field and the substate behind the selector. Text
  /// scanning could not tell the three apart without listing the receivers to
  /// refuse; the position in the chain says it outright.
  void _chain(Expression node) {
    // Only the outermost node of a chain: an inner one is judged with it.
    final parent = node.parent;
    if ((parent is PropertyAccess && parent.target == node) ||
        (parent is PrefixedIdentifier && parent.prefix == node)) {
      return;
    }
    final parts = _segments(node);
    if (parts == null) return;
    for (var i = 0; i + 1 < parts.length; i++) {
      // The receiver either heads the chain, or the facade hop is in front of
      // it — `…select.logIn.email`.
      if (i > 0 && parts[i - 1] != 'select') continue;
      final id = index['${parts[i]}.${parts[i + 1]}'];
      if (id != null) used.add(id);
    }
    // `state.select.canEnterApp` — a composite behind the facade.
    for (var i = 1; i < parts.length; i++) {
      if (parts[i - 1] != 'select') continue;
      final id = index[parts[i]];
      if (id != null) used.add(id);
    }
  }

  /// The chain as plain names, or null when it is rooted in something that is
  /// not one — `items[0].logIn.email`, `of(context).logIn.email`. Those are
  /// reads frx cannot attribute, and guessing at them is what the graph's
  /// blind-spot discipline exists to avoid.
  List<String>? _segments(Expression node) => switch (node) {
    // `this` is transparent: inside a class mixing in `Selectors`,
    // `this.logIn.email` is the same read as the bare `logIn.email`, and
    // refusing it would report a live selector as dead.
    ThisExpression() => const [],
    SimpleIdentifier() => [node.name],
    PrefixedIdentifier() => [node.prefix.name, node.identifier.name],
    // A cascade section (`thing..field = 1`) is a PropertyAccess with no
    // target. Falling back to the node itself recurses on it forever; there is
    // no receiver to name, so the chain is simply unreadable.
    PropertyAccess(target: final target?) => switch (_segments(target)) {
      final head? => [...head, node.propertyName.name],
      _ => null,
    },
    _ => null,
  };
}

/// Adds [from] to [into], reporting whether anything was new — `Set.addAll`
/// returns void, and the fixpoint loop needs to know when to stop.
bool _merge(Set<String> into, Set<String> from) {
  final before = into.length;
  into.addAll(from);
  return into.length != before;
}

/// Collects the `Select*` extension types and what each getter touches.
class _SelectorVisitor extends RecursiveAstVisitor<void> {
  final selectors = <_Selector>[];

  /// Every selector declared in [unit], with each one's sibling reads folded in.
  ///
  /// The single entry point, because the fold has to happen after the whole file
  /// is visited — an extension can be declared above the type it extends — and a
  /// caller that has to remember a second call would eventually not.
  static List<_Selector> read(CompilationUnit unit) {
    final v = _SelectorVisitor();
    unit.accept(v);
    // Grouped by owning type rather than by declaration: an
    // `extension X on SelectLogIn` contributes getters *to* `SelectLogIn`, so
    // its siblings are that type's getters and not its own.
    final byOwner = <String, Map<String, _Selector>>{};
    for (final s in v.selectors) {
      (byOwner[s.ownerType] ??= {})[s.getter] = s;
    }
    byOwner.values.forEach(v._inheritFromSiblings);
    return v.selectors;
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _collect(node);
    super.visitExtensionTypeDeclaration(node);
  }

  /// A composite selector — `extension SelectComposites on Selectors` — reads
  /// other selectors instead of the state.
  ///
  /// Keyed on what it extends, not on what it is called: the name is free, and
  /// missing these would report every selector a composite reads as read by
  /// nobody. It is an `extension`, not an `extension type`, so the visit above
  /// never sees it.
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _collect(node);
    super.visitExtensionDeclaration(node);
  }

  /// Records the getters [node] declares, if it declares a selector at all.
  ///
  /// The spine's *own* body is skipped — `SelectLogIn get logIn => …` on
  /// `Select` is a hop onto a selector, not one. An `extension … on Select` is
  /// kept: those getters are composites, reached by a bare name. An unnamed
  /// extension is dropped here rather than in [SelectorShape], because the
  /// placement rules can report one without naming it but a graph node cannot
  /// exist without an id.
  void _collect(AstNode node) {
    final decl = SelectorShape.of(node);
    if (decl == null || (decl.declaresOwner && decl.onFacadeSpine)) return;
    final type = decl.name;
    if (type == null) return;
    for (final m in decl.members.whereType<MethodDeclaration>()) {
      if (!m.isGetter) continue;
      final s = _Selector(type, decl.owner, m.name.lexeme, m.name.offset);
      m.body.accept(_BodyReader(s));
      s.body = m.body;
      selectors.add(s);
    }
  }

  /// Folds a sibling getter's reads into the one that calls it.
  ///
  /// `bool get isAvailable => token != null;` reads no state of its own, but
  /// `token` next to it does — so it reads that substate just the same. Without
  /// this it lands in `unresolved` as an unreadable composite, which is worse
  /// than a missing edge: a blind-spot list that cries wolf gets ignored, and
  /// then the real gaps go with it.
  void _inheritFromSiblings(Map<String, _Selector> group) {
    // Bounded by the group size: each pass can only propagate one hop, and a
    // reference cycle simply stops adding anything.
    for (var pass = 0; pass < group.length; pass++) {
      var changed = false;
      for (final s in group.values) {
        for (final name in s.siblings) {
          final other = group[name];
          if (other == null || identical(other, s)) continue;
          changed |= _merge(s.readsFields, other.readsFields);
          changed |= _merge(s.waitsForActions, other.waitsForActions);
        }
      }
      if (!changed) break;
    }
  }
}

/// What one getter's body touches, read off the tree rather than off its text.
///
/// Three regexes over `m.body.toSource()` stood here, and text cannot tell a
/// string literal from code. Reproduced with the product's own commands on a
/// fresh project — `frx add-selector session label -t String -e "'token'"` —
/// after which `SelectSession.label`, whose whole body is the *string*
/// `'token'`, was reported as reading the session slice: the bare-identifier
/// scrape matched `token` inside the quotes and the sibling fold handed it the
/// neighbouring `token` getter's reads. In the same output the reason another
/// selector was dead changed with it, and where such a phantom reader is itself
/// read, a dead selector is reported alive.
///
/// [_Selector.body] already stated the rule — "a selector quoted in a string is
/// not a read of it" — for the half of this file that was already a visitor
/// ([selectorUsesIn]). This is the other half saying the same thing.
class _BodyReader extends RecursiveAstVisitor<void> {
  _BodyReader(this._into);

  final _Selector _into;

  /// The two spellings of the state receiver. `_state` is the field of an
  /// `extension type Select…`; `state` is the getter on the `Selectors` mixin,
  /// which is what a composite in `extension SelectComposites on Selectors`
  /// has to use — it has no `_state` to reach. The old pattern knew only the
  /// first, so every composite reading state directly was a blind spot.
  static const _stateReceivers = {'_state', 'state'};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;

    // The right half of `a.b` — a name reached through something, not one
    // standing on its own. This is what the old "not preceded by a dot"
    // lookbehind expressed.
    if (parent is PrefixedIdentifier && parent.identifier == node) {
      if (_stateReceivers.contains(parent.prefix.name)) {
        _into.readsFields.add(node.name);
      }
      return;
    }
    if (parent is PropertyAccess && parent.propertyName == node) return;
    if (parent is MethodInvocation && parent.methodName == node) {
      _waitedOn(parent);
      return;
    }
    if (_stateReceivers.contains(node.name)) return;

    // Lower-case initial only, which is what keeps a type name out of the
    // sibling set — the same filter the old pattern's `[a-z]` applied.
    final name = node.name;
    if (name.isNotEmpty && name[0] == name[0].toLowerCase()) {
      _into.siblings.add(name);
    }
  }

  /// The action type in `…isWaitingForType<LogInWithEmailAction>()`.
  void _waitedOn(MethodInvocation node) {
    if (node.methodName.name != 'isWaitingForType') return;
    for (final arg
        in node.typeArguments?.arguments ?? const <TypeAnnotation>[]) {
      if (arg is NamedType) _into.waitsForActions.add(arg.name.lexeme);
    }
  }
}
