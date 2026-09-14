import 'package:path/path.dart' as p;

import '../../engine/build_step.dart';
import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../model/substate_artifact.dart';
import '../../redux/app_state_source.dart';
import '../../redux/selectors_source.dart';
import '../../redux/store_source.dart';
import '../../util/casing.dart';
import '../../util/console.dart';
import '../../workspace/frx_workspace.dart';
import '../wiring.dart';
import '../writing_command.dart';

/// `remove --kind substate`: the folder, and the three facades that composed
/// it — the inverse of `add-substate`.
///
/// A substate is *wired*: it is found by what the project declares (an
/// `AppState` field) and removing one is mostly an unwiring job.
mixin SubstateRemoval on WritingCommand {
  WritePlan removeSubstate(
    Casing name,
    AppStateSource appState,
    FrxWorkspace repo, {
    required bool apply,
  }) {
    final a = SubstateArtifact(name);
    final substateDir = a.dir(appState.reduxDir);
    // Guard: only delete the folder if it really holds this substate's state
    // model, so a forced `--kind substate` can never nuke a sibling folder
    // (`common/`, `services/`) that happens to share the name.
    final canDeleteFolder = a.stateFile(appState.reduxDir).existsSync();

    final unwire = appState.unwireSubstate(
      field: a.field,
      importPath: a.stateImportPath,
    );
    final selectors = SelectorsSource.beside(appState.file);
    final selUnwire = selectors.exists
        ? selectors.unwire(
            field: a.field,
            pascal: name.pascal,
            snake: name.snake,
          )
        : null;

    // The persistor's change log, when the project kept it. Matched on either
    // half, so a line left labelled with the old name after a rename goes too.
    final store = StoreSource.of(repo);
    final storeUnwire = store.changed() == null
        ? null
        : store.unwire(field: a.field);

    final wiring = [
      Wiring.of(
        'AppState',
        appState.file,
        unwire,
        skipped: 'field "${a.field}" not present — nothing to unwire.',
        way: WiringWay.unwired,
      ),
      if (storeUnwire != null)
        Wiring.of(
          'Store',
          store.file,
          storeUnwire,
          skipped: 'change log does not list "${a.field}" — nothing to unwire.',
          way: WiringWay.unwired,
        ),
      if (selUnwire != null)
        Wiring.of(
          'Selectors',
          selectors.file,
          selUnwire,
          skipped: '${a.selectorType} absent — nothing to unwire.',
          way: WiringWay.unwired,
        ),
    ];

    return WritePlan(
      changes: Changeset([
        if (canDeleteFolder) DeleteDirectory(substateDir.path),
        ...wiring.edits,
      ]),
      header:
          'Remove substate "${name.pascal}"  '
          '(field: ${a.field}, type: ${a.stateType})',
      narrate: () {
        if (!canDeleteFolder) {
          console.out.writeln(
            '  • ${p.relative(substateDir.path)} — no '
            '${name.snake}_state.dart, '
            'left in place',
          );
        }
        // One blank line before the blocks, because what precedes them is a
        // note about a file rather than nothing. The blocks space themselves.
        console.out.writeln();
        wiring.narrate();
      },
      previewOnly: !apply,
      previewNotice: kPreviewNotice,
      closing:
          '✓ Removed substate "${name.pascal}".\n'
          '  Note: code elsewhere that dispatched its actions or read its '
          'selectors now dangles — run `frx doctor` / `dart analyze`.',
      // A substate lives entirely in `business`, so its deleted files (and
      // their freezed parts) are in the same package build_runner writes to —
      // incremental build handles the deletion fine.
      build: (_) => BuildStep.build(
        FrxWorkspace.packageRootOf(appState.file.path),
        nextHint: 'regenerate AppState (its freezed part)',
      ),
    );
  }
}
