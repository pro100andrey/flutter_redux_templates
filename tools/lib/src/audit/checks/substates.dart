import 'dart:io';

import 'package:path/path.dart' as p;

import '../../model/substate_artifact.dart';
import '../../redux/app_state_source.dart';
import '../../redux/store_source.dart';
import '../../refusal.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// Substates composed into `AppState` must have their state file + freezed
/// part; substate folders that aren't composed are orphans.
void checkSubstates(FrxWorkspace repo, List<Finding> into) {
  final AppStateSource source;
  try {
    source = AppStateSource.of(repo);
  } on FrxRefusal {
    into.add(
      const Finding.warn('AppState not found — skipped substate checks.'),
    );
    return;
  }

  final substates = source.readSubstates();
  final wiredTypes = substates.map((s) => s.type).toSet();

  for (final s in substates) {
    // `wait`/framework fields have no substate folder — skip non-…State types.
    if (!s.isSubstate) {
      continue;
    }
    final stateFile = SubstateArtifact.parse(
      s.field,
    ).stateFile(source.reduxDir);
    if (!stateFile.existsSync()) {
      into.add(
        Finding.error(
          'AppState.${s.field} (${s.type}) has no '
          '${p.relative(stateFile.path)}.',
          // The state file is missing; anchor on where the field is declared.
          file: source.file.path,
        ),
      );
    } else if (!File(
      p.setExtension(stateFile.path, '.freezed.dart'),
    ).existsSync()) {
      into.add(
        Finding.error(
          '${p.relative(stateFile.path)} — freezed part missing (run '
          'build_runner).',
          file: stateFile.path,
          fix: const BuildRunnerFix('business'),
        ),
      );
    }
  }

  // Orphan substate folders (a *_state.dart whose type isn't in AppState),
  // and — when even that file is gone — what the folder has become.
  for (final dir in repo.substateDirsIn()) {
    final base = p.basename(dir.path);
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
/// know this list existed, so a substate added by frx was invisible to the
/// trace from the moment it was created, and a renamed one kept printing its
/// old name.
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
  if (entries == null) {
    return;
  }

  final AppStateSource appState;
  try {
    appState = AppStateSource.of(repo);
  } on FrxRefusal {
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
