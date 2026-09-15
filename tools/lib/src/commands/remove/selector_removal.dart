import 'package:path/path.dart' as p;

import '../../ast/source_index.dart';
import '../../engine/changeset.dart';
import '../../model/substate_artifact.dart';
import '../../redux/selectors_source.dart';
import '../../util/casing.dart';
import '../../util/console.dart';
import '../../workspace/frx_workspace.dart';
import '../substate_target.dart';
import '../wiring.dart';
import '../writing_command.dart';
import 'left_in_place.dart';

/// `remove --kind selector`: one computed getter on the facade — the inverse
/// of `add-selector`.
///
/// **The other half of a pair that only had one.** `add-selector` writes a
/// getter into `Select<Pascal>`; nothing took one out. `selectors.dart` is
/// under the placement guard, so the way out was a hand edit to a file frx
/// complains about being hand-edited — and the splice already existed, used
/// by the field path, which removes the getter it wrote alongside a field.
///
/// **Addressed as `SelectTheme.isWaiting` or as `isWaiting --state theme`.**
/// The dotted form is what `graph` prints and what `doctor` names, so it can
/// be pasted; the bare form matches how `add-selector` takes it. Asked for
/// rather than detected, for `--kind field`'s reason: a getter is named in
/// camel case, which is also a substate's own spelling.
mixin SelectorRemoval on WritingCommand {
  /// The plan for the getter named by the raw positional argument.
  ///
  /// The raw argument, not `requireName()`: the address `graph` and `doctor`
  /// print is `SelectTheme.isWaiting`, and the name validator rejects the dot.
  /// Pasting what the tool just told you is the case worth supporting.
  WritePlan removeSelector(
    FrxWorkspace repo, {
    required String? state,
    required bool apply,
  }) => inSourceIndex(() {
    final raw = argResults!.rest.isEmpty ? '' : argResults!.rest.first;
    if (raw.isEmpty) {
      refuse('Which selector? Pass `SelectTheme.isWaiting`.');
    }
    final dotted = raw.contains('.');
    final getter = dotted ? raw.split('.').last : Casing.parse(raw).camel;
    final selectorType = dotted
        ? raw.split('.').first
        : SubstateArtifact(
            requireSubstate(
              state ??
                  refuse(
                    'Which selector? Pass the facade — `frx remove '
                    'SelectTheme.$getter --kind selector` — or name the '
                    'substate '
                    'with `--state`.',
                  ),
            ),
          ).selectorType;

    final selectors = SelectorsSource(repo.selectorsFile);
    if (!selectors.exists) {
      refuse('No ${p.relative(repo.selectorsFile.path)} to remove from.');
    }

    // Read before the splice, for the reason the field path reads its
    // declaration first: afterwards there is nothing left to ask.
    final readers = [
      for (final member in selectors.readersOf(
        selectorType: selectorType,
        getterName: getter,
      ))
        '$selectorType.$member',
    ];
    if (readers.isNotEmpty) {
      refuse(
        '"$selectorType.$getter" is still read by ${readers.join(', ')} — '
        'removing it would leave '
        '${readers.length == 1 ? 'that member' : 'those members'} naming a '
        'declaration that is gone.\n'
        '  A selector body is yours to edit by hand; rewrite '
        '${readers.length == 1 ? 'it' : 'them'} and run this again.',
      );
    }

    final unwired = selectors.removeSelector(
      selectorType: selectorType,
      getterName: getter,
    );
    if (unwired.changes.isEmpty) {
      refuse(
        '$selectorType has no "$getter" getter '
        '(${p.relative(repo.selectorsFile.path)}) — see `frx graph` for what '
        'the facade declares.',
      );
    }

    // Outside the facade it is somebody's connector, and frx does not rewrite
    // those. Named in the preview rather than refused: unlike a reader inside
    // the file being spliced, this one is in a file the guard leaves alone, so
    // it is a thing to go fix, not a reason the removal cannot be described.
    final outside = _readsSelector(repo, getter);

    final wiring = [
      Wiring.of('Selectors', selectors.file, unwired, way: WiringWay.unwired),
    ];

    return WritePlan(
      changes: Changeset(wiring.edits),
      header: 'Remove selector "$selectorType.$getter"',
      narrate: () {
        console.out.writeln();
        wiring.narrate();
        narrateLeftInPlace('Still reads ".$getter"', outside);
      },
      previewOnly: !apply,
    );
  });

  /// Files outside `business` whose source names `.<getter>`.
  ///
  /// Textual, and it decides nothing — it only names files for the preview, so
  /// a `.title` that belongs to a widget costs a line of output and never a
  /// wrong edit. Resolving it properly is `frx graph`'s job and it does it.
  List<String> _readsSelector(FrxWorkspace repo, String getter) => [
    for (final dir in [repo.appLib, repo.uiLib])
      if (dir.existsSync())
        for (final file in sourceIndex.filesUnder(dir))
          if (sourceIndex.sourceOf(file).contains('.$getter')) file.path,
  ];
}
