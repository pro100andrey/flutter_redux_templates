/// The audit's checks, as a list it walks.
///
/// The list is not the point — walking seven entries costs the same edit to
/// extend as calling seven functions did. Two things are:
///
/// - **A check is addressable and runnable alone.** Answering "what does the
///   substate check say about this tree" used to cost a subprocess and arrive
///   mixed in with six other checks' findings.
/// - **The gate is data.** "Observes the running machine rather than the file
///   tree" was an `if` in the middle of the calls; it is now a property of the
///   check that declares it, which is what the `--json` consumer's exclusion
///   keys on.
///
/// What a check *reports* is [Finding], and what `--fix` would do about it is a
/// [Fix] — named once there rather than three times in three shapes, which is
/// the duplication this split was actually for.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../ast/source_index.dart';
import '../config/frx_config.dart';
import '../engine/build_step.dart';
import '../flow/flow_docs.dart';
import '../model/page_artifact.dart';
import '../model/placement.dart';
import '../model/substate_artifact.dart';
import '../preview/vm_reader.dart';
import '../redux/app_state_source.dart';
import '../redux/store_source.dart';
import '../routing/routes_source.dart';
import '../workspace/frx_workspace.dart';
import 'finding.dart';

/// One audit check: what it is called, and what it reports.
class Check {
  const Check(this.id, this.run, {this.needsProcessState = false});

  /// Stable, kebab-case. Not emitted in `--json` — findings carry the `.frxrc`
  /// rule id, which is a different and finer thing — but it is how a test names
  /// one check, and how a future "run only this" would address it.
  final String id;

  /// Whether this check observes what is *running* rather than what is on disk.
  ///
  /// Those appear and vanish with no file changing, so a consumer that re-audits
  /// on file events — the editor — would keep showing one long after it was
  /// true.
  final bool needsProcessState;

  final void Function(FrxWorkspace repo, List<Finding> into) run;
}

/// Every check, in report order.
const auditChecks = <Check>[
  Check('substates', checkSubstates),
  Check('change-log', checkChangeLog),
  Check('routes-and-connectors', checkRoutesAndConnectors),
  Check('generated-parts', checkGeneratedParts),
  Check('flow-docs', checkFlowDocs),
  Check('preview-mirror', checkPreviewMirror),
  Check('placement', checkPlacement),
  Check('view-model-equality', checkViewModels),
  Check('orphaned-watch', checkOrphanedWatch, needsProcessState: true),
  // Last: it reports on what the checks above read, so it has to run after
  // them. See [checkRecoveredFiles] for why that bound is the honest one.
  Check('recovered-files', checkRecoveredFiles),
];

/// Every finding derived from [repo], minus the process-state checks unless
/// [processState] asks for them.
List<Finding> audit(FrxWorkspace repo, {bool processState = false}) =>
    inSourceIndex(() {
      final findings = <Finding>[];
      for (final check in auditChecks) {
        if (check.needsProcessState && !processState) continue;
        check.run(repo, findings);
      }
      return findings;
    });

// --- substates ---------------------------------------------------------------

/// Substates composed into `AppState` must have their state file + freezed part;
/// substate folders that aren't composed are orphans.
void checkSubstates(FrxWorkspace repo, List<Finding> into) {
  final AppStateSource source;
  try {
    source = AppStateSource.of(repo);
  } on StateError {
    into.add(
      const Finding.warn('AppState not found — skipped substate checks.'),
    );
    return;
  }

  final substates = source.readSubstates();
  final wiredTypes = substates.map((s) => s.type).toSet();

  for (final s in substates) {
    // `wait`/framework fields have no substate folder — skip non-…State types.
    if (!s.isSubstate) continue;
    final stateFile = SubstateArtifact.parse(
      s.field,
    ).stateFile(source.reduxDir);
    if (!stateFile.existsSync()) {
      into.add(
        Finding.error(
          'AppState.${s.field} (${s.type}) has no ${p.relative(stateFile.path)}.',
          // The state file is missing; anchor on where the field is declared.
          file: source.file.path,
        ),
      );
    } else if (!File(
      '${_stripDart(stateFile.path)}.freezed.dart',
    ).existsSync()) {
      into.add(
        Finding.error(
          '${p.relative(stateFile.path)} — freezed part missing (run build_runner).',
          file: stateFile.path,
          fix: const BuildRunnerFix('business'),
        ),
      );
    }
  }

  // Orphan substate folders (a *_state.dart whose type isn't in AppState),
  // and — when even that file is gone — what the folder has become.
  for (final dir in sourceIndex.directoriesIn(source.reduxDir)) {
    final base = p.basename(dir.path);
    if (!FrxWorkspace.isSubstateDir(base)) continue;
    final stateFile = p.join(dir.path, 'models', '${base}_state.dart');
    if (!File(stateFile).existsSync()) {
      _checkSubstateCarcass(dir, base, into);
      continue;
    }
    final expectedType = SubstateArtifact.parse(base).stateType;
    if (!wiredTypes.contains(expectedType)) {
      into.add(
        Finding.warn(
          'redux/$base — $expectedType is not composed into AppState.',
          file: stateFile,
          fix: OrphanFix(base),
        ),
      );
    }
  }
}

/// The persistor's change log must name the substates `AppState` composes.
///
/// One line per field, feeding the `Δ connectivity, logIn` the action logger
/// prints. frx wired the `AppState` field and the selectors facade and did not
/// know this list existed, so a substate added by frx was invisible to the trace
/// from the moment it was created, and a renamed one kept printing its old name.
///
/// **Warnings, never errors.** Nothing crashes; what breaks is the answer the
/// log gives the person reading it. And the block belongs to the project — one
/// that trimmed it on purpose is not wrong, it is just no longer complete.
///
/// **Silent for a project that has no such block**, the way the docs export is:
/// there is nothing to be out of step with.
void checkChangeLog(FrxWorkspace repo, List<Finding> into) {
  final store = StoreSource.of(repo);
  if (store.ambiguous) {
    // Said rather than guessed at. Picking one by position is a coin flip that
    // loses silently: the wrong list gets the entry, and every real substate is
    // then reported missing from it.
    into.add(
      Finding.warn(
        '${p.relative(store.file.path)} has more than one list shaped like the '
        'change log, so frx cannot tell which one it is — neither wires it nor '
        'checks it.',
        file: store.file.path,
      ),
    );
    return;
  }
  final entries = store.changed();
  if (entries == null) return;

  final AppStateSource appState;
  try {
    appState = AppStateSource.of(repo);
  } on StateError {
    // `checkSubstates` has already said AppState is missing; saying it twice
    // tells the reader nothing and buries the finding that matters.
    return;
  }
  final substates = {
    for (final s in appState.readSubstates())
      if (s.isSubstate) s.field,
  };

  for (final entry in entries) {
    if (!entry.agrees) {
      // States what the line does, not why. A rename that moved the field and
      // left the string is how it usually happens, but the block belongs to the
      // project and `relabel` is careful to leave a deliberate label alone —
      // the audit should not accuse where the editor defers.
      into.add(
        Finding.warn(
          'the change log tests ${entry.field} and prints "${entry.label}", so '
          'the trace names something other than the field it watched.',
          file: store.file.path,
        ),
      );
    } else if (!substates.contains(entry.field)) {
      into.add(
        Finding.warn(
          'the change log names "${entry.label}", which AppState no longer '
          'composes.',
          file: store.file.path,
        ),
      );
    }
  }

  final listed = {for (final e in entries) e.field};
  for (final field in substates) {
    if (!listed.contains(field)) {
      into.add(
        Finding.warn(
          'AppState.$field is missing from the change log, so a change to it '
          'is not traced.',
          file: store.file.path,
        ),
      );
    }
  }
}

/// A view-model that compares on fewer fields than it holds.
///
/// A value field outside equality is a lie in `==`: two view-models with
/// different values compare equal, so the connector's rebuild never reaches the
/// widget and the screen shows the old value. The reader for this existed for
/// months with no consumer, reading `equatable`'s `props` getter while every
/// view-model here states its equality in `super(equals: […])` — so it read an
/// empty list eight times out of eight and could never have fired.
///
/// **Nothing in this template is reported, and that is expected.** All eight
/// were written correctly, once, by somebody who knew: ten of the eleven fields
/// outside equality are callbacks, which the idiom excludes on purpose, and the
/// eleventh is a dialog that writes its own `==` and says why. The check is for
/// the app grown from the clone, where a field added six months later is not
/// added to the list beside it.
///
/// **A warning with no fix.** Which field belongs in equality is the author's
/// call — a deliberately excluded one is a real design, and a remedy that
/// guessed would be editing an intention.
void checkViewModels(FrxWorkspace repo, List<Finding> into) {
  final rule = PlacementRule.fieldOutsideEquality;
  final config = FrxConfig.load(startDir: repo.root.path);
  if (config.placement[rule.id] == false) return;
  for (final dir in [repo.appLib, repo.uiLib]) {
    if (!dir.existsSync()) continue;
    for (final file in sourceIndex.filesUnder(dir)) {
      // Same bargain the placement sweep strikes: a textual pre-filter decides
      // whether to look, never what to report. A file with neither shape cannot
      // hold a view-model that states an equality.
      final source = sourceIndex.sourceOf(file);
      if (!source.contains('equals:') && !source.contains('get props')) {
        continue;
      }
      for (final vm in VmReader.read(source)) {
        for (final field in vm.fieldsOutsideEquality) {
          into.add(
            Finding.warn(
              '${p.relative(file.path)} — ${vm.className}.${field.name} '
              '(${field.type}) is outside the equality it declares, so two of '
              'them differing only in it compare equal and the rebuild is lost.',
              file: file.path,
              rule: rule.id,
            ),
          );
        }
      }
    }
  }
}

/// Files the analyzer could only recover a tree from.
///
/// The reader tier is tolerant of unparseable source on purpose: one broken file
/// in somebody's repo must not take a whole audit down. The tolerance was
/// silent, and silence is the worse half of that bargain — every check above
/// answers from whatever tree it was handed, and a file with a missing brace has
/// no `@RoutePage` as far as the route check can tell. So a broken file used to
/// make the audit *more* confident, not less: `✓ No issues found.`
///
/// **Bounded by what the audit read, and that is the accurate scope rather than
/// a compromise.** Sweeping the three lib trees to parse everything was tried:
/// it does report the broken action file that motivated this, and it costs
/// 448 → 510 ms on the live monorepo *and* undoes the property
/// `doctor_test`'s "the pre-filter keeps most of the tree unparsed" pins — the
/// placement sweep's whole point. It is also answering a question that is not
/// this one. A file no check read cannot have corrupted a finding, the editor's
/// Dart plugin already flags syntax errors where the author is typing, and
/// `frx graph` — which does read every action file — reports the same file as an
/// unresolved entry. What frx uniquely knows is which of *its own* answers came
/// from a guess.
///
/// **A warning, so the exit code stays 0.** One broken file in a cloned project
/// is the author's to fix, not a reason to fail their build.
void checkRecoveredFiles(FrxWorkspace repo, List<Finding> into) {
  for (final file in sourceIndex.recovered) {
    into.add(
      Finding.warn(
        '${p.relative(file.path)} does not parse — what this audit says about '
        'it was read off a recovered tree.',
        file: file.path,
      ),
    );
  }
}

/// A folder under `redux/` shaped like a substate whose state file is gone.
///
/// The state file is the only evidence that a folder is a substate, and both
/// readers keyed on it: the orphan check above skipped such a folder, and
/// `remove` declines to delete one (its guard exists so a forced
/// `--kind substate` cannot nuke a sibling like `common/`). So the folder
/// became unreportable and undeletable at the same moment — a carcass. This
/// is the audit's own hole rather than a new surface: the scan already walks
/// these directories, and nothing else can say which empty folder is an
/// artifact. A generic empty-directory sweep is `find -type d -empty`, which
/// is cheaper and would fire on every scratch folder in the tree.
///
/// Git tracks no empty directory, so this never reaches CI. It is a standing
/// property of a working copy the way an orphaned watch is one of the machine
/// — and, unlike that one, a fact about the file tree, so it stays in
/// `--json` and the editor's re-audit on file events picks it up.
void _checkSubstateCarcass(Directory dir, String base, List<Finding> into) {
  final left = dir.listSync(recursive: true).whereType<File>().toList();

  // Nothing to lose, so `--fix` may take the whole branch. The scan reached
  // this folder by walking `redux/` through [FrxWorkspace.isSubstateDir], so
  // `common/`, `models/` and `services/` never arrive here — the guard
  // `remove` needs against a name it was *handed* has no counterpart here.
  if (left.isEmpty) {
    into.add(
      Finding.warn(
        'redux/$base — an empty artifact folder: no ${base}_state.dart, and '
        'no file under it at all.',
        // No file to anchor on: `--fix` removes it, but the Problems panel
        // cannot squiggle a directory, so no lightbulb offers it.
        fix: OrphanFix(base),
      ),
    );
    return;
  }

  // Something is still in there. Report it and stop: deleting it is exactly
  // the decision an automatic fix must not make for you, the way a placement
  // fix would move a deliberately placed file.
  into.add(
    Finding.warn(
      'redux/$base — no ${base}_state.dart, but ${left.length} file(s) '
      'remain: what a removed substate left behind.',
      file: left
          .firstWhere((f) => f.path.endsWith('.dart'), orElse: () => left.first)
          .path,
    ),
  );
}

// --- routes ------------------------------------------------------------------

/// Every route needs its connector; every page connector should be routed.
void checkRoutesAndConnectors(FrxWorkspace repo, List<Finding> into) {
  final RoutesSource routes;
  try {
    routes = RoutesSource.of(repo);
  } on StateError {
    into.add(const Finding.warn('AppRouter not found — skipped route checks.'));
    return;
  }

  final routedTypes = routes.readRoutes().map((r) => r.routeType).toSet();

  // route → connector file
  for (final type in routedTypes) {
    final page = PageArtifact.fromRouteType(type);
    if (page == null) continue;
    final connector = page.connectorFile(routes.connectorsDir);
    if (!connector.existsSync()) {
      into.add(
        Finding.error(
          'Route $type has no ${p.relative(connector.path)}.',
          // The connector is missing; anchor on the route registration.
          file: routes.file.path,
        ),
      );
    }
  }

  // page connector → route (only @RoutePage() connectors are meant to be
  // routed; wrappers like TopLevelPageConnector are not).
  for (final f in sourceIndex.filesUnder(
    routes.connectorsDir,
    recursive: false,
  )) {
    final fname = p.basename(f.path);
    if (!fname.endsWith('_page_connector.dart')) continue;
    // Off the parse tree, not out of the text — and through the one module that
    // decides, so this check and the placement rules cannot come to differ.
    final unit = sourceIndex.unitIf(
      f,
      (s) => s.contains('@${PageArtifact.routePageAnnotation}'),
    );
    if (unit == null || !PageArtifact.carriesRoutePage(unit)) continue;
    final base = fname.substring(
      0,
      fname.length - '_page_connector.dart'.length,
    );
    final type = PageArtifact.parse(base).routeType;
    if (!routedTypes.contains(type)) {
      into.add(
        Finding.warn(
          'connectors/$fname — $type is not registered in AppRouter.',
          file: f.path,
        ),
      );
    }
  }
}

// --- generated code ----------------------------------------------------------

/// Any `part 'x.(freezed|g|g.theme|gr).dart'` whose target file is absent means
/// build_runner hasn't run (or is stale).
void checkGeneratedParts(FrxWorkspace repo, List<Finding> into) {
  const pkgs = ['business', 'http_client', 'ui', 'app', 'models'];
  final partRe = RegExp(
    r'''^part\s+['"]([^'"]+\.(?:freezed|g|g\.theme|gr)\.dart)['"]\s*;''',
    multiLine: true,
  );

  for (final pkg in pkgs) {
    final lib = Directory(p.join(repo.root.path, pkg, 'lib'));
    for (final entity in sourceIndex.filesUnder(lib)) {
      for (final m in partRe.allMatches(sourceIndex.sourceOf(entity))) {
        final target = File(p.join(entity.parent.path, m.group(1)!));
        if (target.existsSync()) continue;
        into.add(
          Finding.error(
            '${p.relative(entity.path, from: repo.root.path)} → part '
            '"${m.group(1)}" missing (run build_runner).',
            file: entity.path,
            fix: BuildRunnerFix(pkg),
          ),
        );
      }
    }
  }
}

// --- exports -----------------------------------------------------------------

/// The `docs/flows/` export is a pure function of the connectors, so anything
/// it doesn't match is drift. Opt-in: checked only once the directory exists,
/// which is what `frx flow --md` creates.
void checkFlowDocs(FrxWorkspace repo, List<Finding> into) {
  final docs = FlowDocs(repo);
  if (!docs.enabled) return;

  final List<DocDrift> drift;
  try {
    drift = docs.check();
  } on StateError {
    // No AppRouter — `checkRoutesAndConnectors` already said so.
    return;
  }

  for (final d in drift) {
    into.add(
      Finding.error(
        '${d.message} — run `frx flow --md`.',
        // A missing file can't be squiggled; the rest can.
        file: d.kind == DocDriftKind.missing ? null : d.path,
        fix: const FlowDocsFix(),
      ),
    );
  }
}

/// Previews in `ui/lib/previews/` whose widget is gone.
///
/// The mirror's one weakness: move `inputs/foo.dart` to `fields/` by hand and
/// its preview stays behind, still compiling — nothing imports the previews
/// tree, so neither the app build nor a rebuild notices.
///
/// Only the orphan direction is checked. "Widget has no preview" is a
/// coverage goal, not a defect, and reporting it would bury the real
/// findings under one warning per widget written before previews existed.
///
/// Opt-in: no `previews/` directory, nothing to say.
void checkPreviewMirror(FrxWorkspace repo, List<Finding> into) {
  final previews = repo.uiPreviews;
  // Generated output included: a `.g.dart` under `previews/` is still a preview
  // whose widget can go missing, and the sweep reported one before the listing
  // moved behind the index.
  for (final file in sourceIndex.filesUnder(previews, includeGenerated: true)) {
    // previews/<dir>/<name>.dart mirrors <dir>/<name>.dart.
    final mirrored = p.relative(file.path, from: previews.path);
    // A file straight in previews/ mirrors nothing — that is where shared
    // preview infrastructure (sample values, wrappers) belongs. Only entries
    // one level down, in a folder, reflect a widget.
    if (p.split(mirrored).length < 2) continue;
    final widget = File(p.join(repo.uiLib.path, mirrored));
    if (widget.existsSync()) continue;
    into.add(
      Finding.warn(
        '${p.relative(file.path)} previews a widget that is not at '
        '${p.relative(widget.path)} — the widget moved or was deleted.',
        file: file.path,
      ),
    );
  }
}

// --- placement ---------------------------------------------------------------

/// Code that is wired, compiles, and sits in the wrong place.
///
/// **Warnings, never errors, and silenceable per rule.** False positives here
/// are guaranteed by construction rather than by accident: this template is
/// cloned and diverged from on purpose, and a check that can be wrong about
/// someone else's project must not fail their build. That keeps faith with the
/// posture the audit already takes — reporting non-defects buries the real
/// findings.
///
/// **No automatic fix.** A placement fix is a move, and a deliberately placed
/// file is exactly the false positive being accepted here — an automatic move
/// would "fix" somebody's decision.
void checkPlacement(FrxWorkspace repo, List<Finding> into) {
  final config = FrxConfig.load(startDir: repo.root.path);
  final silenced = {
    for (final e in config.placement.entries)
      if (!e.value)
        if (PlacementRule.byId(e.key) case final rule?) rule,
  };
  for (final f in placementFindings(repo, silenced: silenced)) {
    into.add(Finding.warn(f.message, file: f.file, rule: f.rule.id));
  }
}

// --- process state -----------------------------------------------------------

/// `build_runner watch` processes whose parent died.
///
/// They linger for hours regenerating nothing, and look identical to a
/// healthy watch from the outside — the generated file simply stops keeping
/// up. frx already refuses to build around a live watch, so an orphan would
/// otherwise make it stand down for a process that will never do the work.
// The workspace is unused — this check reads the process table, not the tree.
// Kept in the signature so every check has one shape and the registry can hold
// them together; the alternative is a second signature and a branch to pick it.
void checkOrphanedWatch(FrxWorkspace repo, List<Finding> into) {
  for (final pid in orphanedBuildRunnerWatchPids()) {
    into.add(
      Finding.warn(
        'build_runner watch (pid $pid) outlived the terminal or IDE that '
        'started it — it regenerates nothing. Stop it with `kill $pid` '
        'and start a new one.',
      ),
    );
  }
}

String _stripDart(String path) =>
    path.substring(0, path.length - '.dart'.length);
