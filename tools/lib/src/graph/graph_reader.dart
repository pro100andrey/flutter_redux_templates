import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../ast/declarations.dart';
import '../ast/source_index.dart';
import '../flow/connector_visitor.dart';
import '../flow/flow_model.dart';
import '../flow/flow_reader.dart';
import '../flow/route_map.dart';
import '../model/placement.dart';
import '../model/substate_artifact.dart';
import '../redux/app_state_source.dart';
import '../workspace/frx_workspace.dart';
import 'action_index.dart';
import 'graph_builder.dart';
import 'graph_model.dart';
import 'persistor_reader.dart';
import 'selector_reader.dart';
import 'selector_uses.dart';

export 'selector_uses.dart' show facadesIn, selectorUsesIn;

/// Joins every reader frx already has into one [AppGraph].
///
/// The readers each answer a narrow question — what does this page do, what
/// routes exist, what is composed into AppState. Answering "who can change
/// `session.token`" needs them joined, and joining them raises two problems
/// this class exists to solve:
///
/// * **Identity.** A `PageFlow` keys actions by class name, which is
///   unambiguous *within* one page because it was resolved through that
///   connector's imports. Globally it is not: this repo has three
///   `SetEmailAction`s. Node ids are therefore qualified with the owning
///   substate, derived from the file path — which leaves `frx flow --json`
///   untouched.
/// * **Coverage.** Walking connectors finds only what a screen dispatches. An
///   action dispatched by a service dispatcher, or by another action, would
///   read as dispatched by nobody.
class GraphReader {
  GraphReader(this.workspace);

  final FrxWorkspace workspace;

  AppGraph read() => inSourceIndex(() => _GraphRead(workspace).run());
}

/// One read: the passes, in the order that lets each attribute an edge more
/// precisely than the one after it, over the state they share.
class _GraphRead {
  _GraphRead(this.workspace);

  final FrxWorkspace workspace;
  final graph = GraphBuilder();

  late final flowReader = FlowReader(workspace);
  late final appState = AppStateSource.of(workspace);
  late final actions = ActionIndex.read(workspace, flowReader);

  /// Every Dart file of the app's own packages, by canonical path, in listing
  /// order — each read once however many passes ask.
  late final Map<String, _Consumer> consumers = {
    for (final dir in [
      workspace.appLib,
      workspace.businessLib,
      workspace.uiLib,
    ])
      for (final file in sourceIndex.filesUnder(dir))
        p.canonicalize(file.path): _Consumer(file, flowReader),
  };

  AppGraph run() {
    _addSubstates();
    _addActions();
    _addCascades();
    _addPages();
    _addServices();
    _addPersistor();
    _addStrayDispatches();
    _addSelectors();
    _addComposition();
    _addMisplacedSelectors();
    _addUnparsed();
    return graph.build();
  }

  // ---- substates ----------------------------------------------------
  void _addSubstates() {
    for (final s in appState.readSubstates()) {
      graph.addNode(
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
  }

  // ---- actions ------------------------------------------------------
  void _addActions() {
    for (final a in actions.all) {
      graph
        ..addNode(a.node)
        ..own(a.file, a.id);
      // One edge per substate touched, off the structured writes. This used to
      // split the display string back apart on the `', '` the renderer joined
      // it with.
      for (final w in a.info.writes) {
        if (!graph.hasSubstate(w.substate)) {
          continue;
        }
        graph.addEdge(
          GraphEdge(
            from: a.id,
            to: 'substate:${w.substate}',
            kind: .writes,
            via: w.label,
          ),
        );
      }
    }
  }

  /// Resolves a dispatched class name to a node id, adding a placeholder node
  /// plus an [Unresolved] note when it cannot be pinned to a file.
  ///
  /// [owner] is the node whose reading hit the gap — what makes the note
  /// attributable to a subgraph rather than only to the whole project.
  String _dispatchTarget(
    String className,
    File? file,
    String at, {
    required String owner,
  }) {
    final resolved = file == null ? null : actions.at(file);
    if (resolved != null) {
      return resolved.id;
    }
    final id = 'action:$className';
    graph
      ..addNode(
        GraphNode(
          id: id,
          kind: NodeKind.action,
          name: className,
          resolved: false,
        ),
      )
      ..unresolved.add(
        Unresolved(
          kind: 'dispatch-target',
          owner: owner,
          at: at,
          expr: className,
          why: _declaredIn(at, className)
              // A private action beside the one the file is named for. The
              // reason is real and the old wording was not: it said "no
              // imported `*_action.dart` declares it" about a class declared
              // three lines down. What frx cannot do is model it — an action
              // node is keyed on its file, and this file already has one.
              ? 'declared in this file beside its main action, so it has no '
                    'node of its own — one action per file is what the graph '
                    'can key on'
              : 'dispatched, but no imported `*_action.dart` declares it — a '
                    'factory, an alias, or an action outside business/lib/redux',
        ),
      );
    return id;
  }

  // ---- cascades: an action dispatching another ----------------------
  void _addCascades() {
    for (final a in actions.all) {
      for (final step in a.info.dispatches) {
        if (step.isNavigation) {
          continue;
        }
        graph.addEdge(
          GraphEdge(
            from: a.id,
            to: _dispatchTarget(
              step.target,
              a.imports[step.target],
              a.file,
              owner: a.id,
            ),
            kind: .dispatches,
            condition: step.condition,
          ),
        );
      }
    }
  }

  // ---- pages, navigation, and what a screen dispatches ---------------
  void _addPages() {
    final map = RouteMapReader(workspace).read();
    for (final page in map.pages) {
      graph.addNode(
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

      final connectorFile = page.connectorFile;
      if (connectorFile != null) {
        graph.own(connectorFile, 'page:${page.page}');
      } else {
        graph.unresolved.add(
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
        graph.unresolved.add(
          Unresolved(
            kind: 'pop-destination',
            owner: 'page:${e.from}',
            at: 'page:${e.from}',
            expr: 'GoAction.${e.method}',
            why: e.kind == .pop
                ? 'pop with no single pusher — the destination is whatever is '
                      'on the stack, which the source does not state'
                : 'navigation target is not a literal route',
          ),
        );
        continue;
      }
      graph.addEdge(
        GraphEdge(
          from: 'page:${e.from}',
          to: 'page:${e.to}',
          kind: .navigates,
          via: e.via,
          condition: e.condition,
          inferred: e.inferred,
        ),
      );
    }

    for (final entry in map.flows.entries) {
      final flow = entry.value;
      final id = 'page:${entry.key}';
      for (final useCase in flow.useCases) {
        for (final step in useCase.steps) {
          if (step.isNavigation) {
            continue;
          }

          final file = flow.actions[step.target]?.file;
          graph.addEdge(
            GraphEdge(
              from: id,
              to: _dispatchTarget(
                step.target,
                file == null ? null : File(file),
                flow.connectorFile ?? id,
                owner: id,
              ),
              kind: .dispatches,
              via: useCase.label,
              condition: step.condition,
            ),
          );
        }
      }
    }
  }

  // ---- services ------------------------------------------------------
  void _addServices() {
    for (final file in sourceIndex.filesUnder(workspace.businessServices)) {
      final consumer = _consumerAt(file);
      final read = consumer.dispatches;
      if (read.steps.isEmpty) {
        continue;
      }

      final name = artifactNameIn(consumer.unit, file);
      final id = 'service:$name';
      graph
        ..addNode(
          GraphNode(
            id: id,
            kind: NodeKind.service,
            name: name,
            file: file.path,
          ),
        )
        ..own(file.path, id);
      for (final step in read.steps) {
        if (step.isNavigation) {
          continue;
        }
        graph.addEdge(
          GraphEdge(
            from: id,
            to: _dispatchTarget(
              step.target,
              read.actionFiles[step.target],
              file.path,
              owner: id,
            ),
            kind: .dispatches,
            condition: step.condition,
          ),
        );
      }
    }
  }

  // ---- the persistor ---------------------------------------------------
  // Searched by superclass rather than by a fixed path, so renaming the file
  // does not quietly drop it — the whole reason it is here is that its writes
  // were invisible. The string check keeps that generality cheap: every other
  // file under business/lib is rejected without being parsed.
  void _addPersistor() {
    for (final file in sourceIndex.filesUnder(workspace.businessLib)) {
      final unit = sourceIndex.unitIf(file, (s) => s.contains('Persistor'));
      if (unit == null) {
        continue;
      }
      final persistor = persistorIn(unit);
      if (persistor == null) {
        continue;
      }
      final id = 'persistor:${persistor.className}';
      graph.addNode(
        GraphNode(
          id: id,
          kind: NodeKind.persistor,
          name: persistor.className,
          file: file.path,
        ),
      );
      for (final (fields, kind) in [
        (persistor.restores, EdgeKind.restores),
        (persistor.reads, EdgeKind.reads),
      ]) {
        for (final field in fields) {
          if (!graph.hasSubstate(field)) {
            continue;
          }
          graph.addEdge(GraphEdge(from: id, to: 'substate:$field', kind: kind));
        }
      }
    }
  }

  // ---- dispatches from everywhere else ---------------------------------
  // **The same sweep the selector pass below makes, for the other half of the
  // question it answers.** That pass reads every Dart file of the app's own
  // packages and says why: "a read is a read whether or not frx models the
  // reader, and scanning only modelled files would report the selectors that
  // only an unrouted connector uses as dead — the one mistake here that costs
  // working code." Every word of it is true of a dispatch, and this half did
  // not do it.
  //
  // What it did instead was take dispatches from the page walk, which turns a
  // dispatch into an edge only where it is written as a named argument of the
  // `_Vm(...)` construction. Three ordinary shapes fall outside that and were
  // dropped:
  //
  //   * `onInit: (store) => store.dispatch(LoadX())` on the `StoreConnector`,
  //     which belongs to no interaction and so to no view-model field;
  //   * a callback built in `builder:` rather than in `_Vm(...)`;
  //   * every connector no route registers — the walk starts at `@RoutePage`
  //     connectors, so a tree rooted in `MaterialApp.builder` is never
  //     entered. `NodeKind.consumer` was invented for exactly that file and
  //     applied only to its selector reads.
  //
  // The reader already knew: each one lands in `PageFlow.untraced`, which
  // `flow --md` prints as "these files dispatch anyway — so this page has
  // interactions that are not drawn". The graph never read it, so the orphan
  // list — the one place frx says "you can delete this" — named actions that
  // a connector three lines away dispatches. Measured on a real project: four
  // of eleven reported orphan actions.
  //
  // Additive, and deliberately after everything that attributes an edge more
  // precisely: a flow edge carries the interaction it belongs to
  // (`via onSubmit`), and this pass must not shadow one with a bare
  // duplicate. So it fills gaps only — a pair already linked is left as the
  // richer edge.
  void _addStrayDispatches() {
    final linked = {
      for (final e in graph.edges)
        if (e.kind == EdgeKind.dispatches) '${e.from}|${e.to}',
    };
    //
    // **Resolve-or-skip, unlike every other pass here.** The others call
    // [_dispatchTarget], which invents a placeholder node and an `unresolved`
    // note for a name it cannot pin to a file. Doing that from a sweep of every
    // file was measured and rejected: `unresolved` went from 6 entries to 22 on
    // the project this was written against — the same unresolvable factory
    // reported once per file that calls it, and `WaitAction.add` /
    // `WaitAction.remove` raised as project actions because the template's own
    // `WaitingAction` mixin dispatches async_redux's bookkeeping. None of it is
    // new information: naming what a dispatch could not be resolved to is the
    // routed walk's job and it already does it. This pass exists to stop an
    // action frx *does* model from being called unreachable, so an edge it
    // cannot draw to a known action is an edge it has no business inventing.
    for (final consumer in consumers.values) {
      final read = consumer.dispatches;
      if (read.steps.isEmpty) {
        continue;
      }

      final targets = <String>{};
      for (final step in read.steps) {
        if (step.isNavigation) {
          continue;
        }
        final file = read.actionFiles[step.target];
        final known = file == null ? null : actions.at(file);
        if (known != null) {
          targets.add(known.id);
        }
      }
      if (targets.isEmpty) {
        continue;
      }

      final from = graph.nodeFor(consumer.file, consumer.unit);
      for (final to in targets) {
        if (!linked.add('$from|$to')) {
          continue;
        }
        graph.addEdge(GraphEdge(from: from, to: to, kind: EdgeKind.dispatches));
      }
    }
  }

  // ---- selectors -------------------------------------------------------
  /// The `Select<Pascal>` extension types in `selectors.dart`.
  ///
  /// Selectors are what makes deleting an action break something far away:
  /// `isWaitingForType<ForgotPasswordAction>()` names the class with no import
  /// of its own to follow, so nothing else in the graph records the reference.
  void _addSelectors() {
    // `FrxWorkspace.selectorsFile`, whose doc says it exists so a command
    // holding a workspace need not locate `AppState` to find the file beside
    // it. This located `AppState` to find it anyway — a third spelling of one
    // path.
    final file = workspace.selectorsFile;
    if (!file.existsSync()) {
      return;
    }

    final parsed = sourceIndex.unitFor(file);
    final selectors = readSelectorGetters(parsed);

    /// Which substate [s] *belongs to* — from the facade type, and only when
    /// `AppState` composes one by that name — not which ones it reads: a
    /// composite selector reads several.
    String? substateOf(SelectorGetter s) {
      final owner = SubstateArtifact.substateOfSelectorType(s.ownerType);
      return owner != null && graph.hasSubstate(owner) ? owner : null;
    }

    // How each selector is *called*, which is not how it is declared: one
    // hanging off a substate is reached as `<field>.<getter>`, a composite on
    // `Select` as a bare `<getter>`. Built before the loop so a composite can
    // resolve a selector declared after it.
    final selectorIds = <String, String>{};
    for (final s in selectors) {
      final site = switch (substateOf(s)) {
        final owner? => '$owner.${s.getter}',
        null => s.getter,
      };
      selectorIds[site] = s.id;
    }

    // A getter reached from *inside* the type that declares it, where the
    // facade hop above is not written: `email` inside `SelectLogIn`, or inside
    // an `extension … on SelectLogIn`. Keyed by owning type, because a bare
    // name means different getters on different types.
    final siblingIds = <String, Map<String, String>>{};
    for (final s in selectors) {
      (siblingIds[s.ownerType] ??= {})[s.getter] = s.id;
    }

    // The call sites a body on [ownerType] can name: the facade's plus its own
    // siblings. Merged once per type rather than once per getter.
    final bodyIndex = <String, Map<String, String>>{};
    Map<String, String> bodyIndexFor(String ownerType) => bodyIndex.putIfAbsent(
      ownerType,
      () => {...selectorIds, ...?siblingIds[ownerType]},
    );

    for (final s in selectors) {
      final id = s.id;
      // Every selector in the app shares this one file, so the offset is what
      // makes the node point at the getter rather than at the facade.
      final at = parsed.lineInfo.getLocation(s.offset);
      graph.addNode(
        GraphNode(
          id: id,
          kind: NodeKind.selector,
          name: '${s.type}.${s.getter}',
          substate: substateOf(s),
          file: file.path,
          line: at.lineNumber,
          column: at.columnNumber,
        ),
      );

      for (final field in s.readsFields) {
        if (!graph.hasSubstate(field)) {
          continue;
        }
        graph.addEdge(
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
          : (selectorUsesIn(body, bodyIndexFor(s.ownerType))..remove(id));
      for (final target in uses) {
        graph.addEdge(
          GraphEdge(from: id, to: target, kind: EdgeKind.uses, via: s.getter),
        );
      }

      for (final className in s.waitsForActions) {
        final candidates = actions.named(className);
        if (candidates.length == 1) {
          graph.addEdge(
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
        // action itself as the flag and `isWaitingForType<T>` tests
        // `flag is T`, so `isWaitingForType<WaitingAction>()` — the modal
        // barrier's whole question — waits for all of them at once. Read before
        // this existed, it was an action class by that name, found none, and
        // reported the barrier as following something frx could not.
        final byMixin = actions.withMixin(className);
        if (candidates.isEmpty && byMixin.isNotEmpty) {
          for (final a in byMixin) {
            graph.addEdge(
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

        graph.unresolved.add(
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
        graph.unresolved.add(
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
    // selector call is a plain getter, with no dispatch or annotation to key
    // on.
    //
    // Every Dart file of the app's own packages, not just the ones that already
    // have a node. A read is a read whether or not frx models the reader, and
    // scanning only modelled files would report the selectors that only an
    // unrouted connector uses as dead — the one mistake here that costs
    // working code.
    final facade = p.canonicalize(file.path);
    for (final consumer in consumers.values) {
      if (consumer.path == facade) {
        continue; // the facade itself
      }
      final unit = consumer.unit;
      final used = selectorUsesIn(unit, selectorIds, facades: facadesIn(unit));
      if (used.isEmpty) {
        continue;
      }
      final from = graph.nodeFor(consumer.file, unit);
      for (final target in used) {
        graph.addEdge(GraphEdge(from: from, to: target, kind: EdgeKind.uses));
      }
    }
  }

  // ---- how the screens are composed ------------------------------------
  // Which connector builds which, so "nothing builds this one" becomes
  // sayable. Without it the graph had no notion of a widget connector
  // existing at all: on a real project six of eleven reported orphan actions
  // were dispatched only from a `SettingsConnector` that no file constructs,
  // so the verdict was right and the reason — the whole connector is dead,
  // not the six actions one at a time — was missing.
  //
  // The composition itself is not new; `FlowReader` walks it to find a page's
  // regions. It was private to that walk, which starts at `@RoutePage`
  // connectors, so nothing outside the routed tree was ever composed.
  //
  // Runs after everything that makes a node, and matches on the class name
  // rather than on a resolved import: a builder is any file at all, and the
  // one that constructs the app's root widget is not itself a connector.
  void _addComposition() {
    final connectorNodes = <String, String>{
      for (final n in graph.nodes)
        if (n.kind == NodeKind.consumer) n.name: n.id,
    };
    for (final consumer in consumers.values) {
      final built = consumer.builds;
      if (built.isEmpty) {
        continue;
      }

      // Only to nodes that already exist: constructing something frx does not
      // model is not evidence of anything.
      final targets = {
        for (final name in built) ?connectorNodes[name],
      };
      if (targets.isEmpty) {
        continue;
      }

      // A builder with no artifact of its own — the `run_env.dart` that wraps
      // the root widget. It gets a node so the construction can be recorded;
      // the dead-connector rule looks only at names ending in `Connector`, so
      // giving one to a plain file cannot put it on that list.
      final from = graph.nodeFor(consumer.file, consumer.unit);
      for (final to in targets) {
        if (to == from) {
          continue;
        }
        graph.addEdge(GraphEdge(from: from, to: to, kind: EdgeKind.builds));
      }
    }
  }

  // ---- selectors declared outside the facade ---------------------------
  // The graph reads selector *declarations* from `selectors.dart` and nothing
  // else, while the placement rules sweep all three lib trees for them. So a
  // hand-written selector outside the facade was reported by the audit and
  // absent here: no node, no edges, and the selectors it reads counted as
  // read by nobody — which is a false "nothing reads this" in the
  // dead-selector analysis, the one place frx says "you can delete this".
  //
  // An unresolved entry rather than a node, because both halves matter. The
  // false reading goes away, since the selector is no longer absent. And the
  // misplacement is not dressed up as ordinary wiring: an unresolved entry is
  // a blind spot being declared, not a link being drawn.
  //
  // Asked of the module the audit asks, so the two cannot disagree about what
  // a selector is or where it may live — but *not* honouring `.frxrc`: a
  // project silencing the placement rule has said the file may stay there,
  // not that frx can now follow it.
  void _addMisplacedSelectors() {
    for (final finding in placementFindings(
      workspace,
      silenced: const {
        PlacementRule.actionOutsideActionsDir,
        PlacementRule.connectorOutsideConnectors,
      },
    )) {
      final rel = p.relative(finding.file, from: workspace.root.path);
      graph.unresolved.add(
        Unresolved(
          kind: 'misplaced-selector',
          owner: 'file:$rel',
          at: finding.file,
          why:
              '$rel declares a selector outside the facade. frx reads selector '
              'declarations from selectors.dart only, so what this one reads '
              'and '
              'who reads it are both unknown here — move it to the facade and '
              'the graph can follow it.',
        ),
      );
    }
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
  void _addUnparsed() {
    for (final file in sourceIndex.recovered) {
      final rel = p.relative(file.path, from: workspace.root.path);
      graph.unresolved.add(
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
  }

  /// The consumer entry for [file], so a file listed from a subdirectory of
  /// the app's packages shares the sweep's reading of it rather than being
  /// read again on its own.
  _Consumer _consumerAt(File file) =>
      consumers[p.canonicalize(file.path)] ?? _Consumer(file, flowReader);
}

/// One Dart file of the app's own packages, and what the passes ask of it.
///
/// Three passes sweep the same files — for what they dispatch, for the
/// selectors they read, for the connectors they construct. Each fact is read
/// on first use and kept, so the passes share one reading of the file rather
/// than fetching its tree once per question.
class _Consumer {
  _Consumer(this.file, this._reader);

  final File file;
  final FlowReader _reader;

  late final String path = p.canonicalize(file.path);
  late final CompilationUnit unit = sourceIndex.unitFor(file);
  late final DispatchRead dispatches = _reader.dispatchesIn(unit, file.parent);
  late final Set<String> builds = connectorNamesIn(unit);
}

/// Whether the file at [path] declares a class called [className].
///
/// `at` is a file path for every caller that has one and a node id for the one
/// that does not, so this answers false rather than throwing on the latter.
bool _declaredIn(String path, String className) {
  final file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  return classNamed(sourceIndex.unitFor(file), className) != null;
}
