import '../../ast/source_index.dart';
import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../model/removable_artifact.dart';
import '../../redux/selectors_source.dart';
import '../../util/casing.dart';
import '../../util/console.dart';
import '../../workspace/frx_workspace.dart';
import '../wiring.dart';
import '../writing_command.dart';
import 'left_in_place.dart';

/// `remove` for the kinds whose `add-*` wired nothing central — action, model,
/// widget, connector, service.
///
/// They are file sets in known places, found on disk, and removing one is
/// about deleting the whole set: a widget's preview in the mirror tree, a
/// service's dispatcher beside it, a model's `.freezed.dart`. That set is the
/// reason `remove` grew. Across six traced builds the agent reached for raw
/// `rm` sixty-odd times — for actions, models and connectors it could not ask
/// `remove` for — and `rm` deletes the file it was given and leaves the rest
/// of the set behind.
///
/// One of the five wires one thing after all: `add-action -k waiting` puts an
/// `isWaiting` getter keyed on the action's type into the facade, and a
/// removal that left it there left `selectors.dart` naming a type that was
/// gone — frx's own wiring, broken by frx's own command, with a note to go
/// run the audit. The getter goes with the action, and the import it needed.
mixin FileRemoval on WritingCommand {
  /// The plan for a kind that wired nothing central: delete the set, and say
  /// what stops compiling. [repo] is where an action's facade is; without it
  /// the facade is not touched.
  WritePlan removeFiles(
    RemovableArtifact a, {
    required bool apply,
    FrxWorkspace? repo,
  }) {
    final facade = a.kind == .action && repo != null
        ? _unwireWaiting(repo, a.className)
        : null;
    return WritePlan(
      changes: Changeset([
        for (final f in a.files) DeleteFile(f),
        for (final d in a.directories) DeleteDirectory(d),
        ...?facade?.wiring.edits,
      ]),
      header: a.header,
      narrate: facade == null
          ? null
          : () {
              console.out.writeln();
              facade.wiring.narrate();
              narrateLeftInPlace(
                facade.getters.isEmpty
                    ? 'Still keyed on "${a.className}"'
                    : 'Still reads "${facade.getters.join('", "')}"',
                facade.readers,
              );
            },
      previewOnly: !apply,
      previewNotice: kPreviewNotice,
      closing: [
        '✓ Removed ${a.kind.flag} "${a.className}".',
        if (a.dangles != null) '  Note: ${a.dangles}.',
      ].join('\n'),
    );
  }

  /// The facade's getters keyed on [className], taken out — with the import
  /// of the action file they were the last user of — or null when the facade
  /// has none.
  ///
  /// A getter another facade member still reads stays, and is named: the
  /// sibling is somebody's own code, which frx does not rewrite, and the
  /// action is what was asked for — refusing it over the reader would refuse
  /// the whole command over the half `add-action` volunteered.
  _FacadeUnwiring? _unwireWaiting(FrxWorkspace repo, String className) {
    final selectors = SelectorsSource(repo.selectorsFile);
    if (!selectors.exists) {
      return null;
    }
    final keyed = selectors.waitingReadersOf(className);
    if (keyed.isEmpty) {
      return null;
    }
    final kept = <String>[];
    final removable = <({String selectorType, String getterName})>[];
    for (final getter in keyed) {
      final address = '${getter.selectorType}.${getter.getterName}';
      if (selectors
          .readersOf(
            selectorType: getter.selectorType,
            getterName: getter.getterName,
          )
          .isNotEmpty) {
        kept.add(address);
      } else {
        removable.add(getter);
      }
    }
    final unwired = selectors.removeSelectors(removable);
    final taken = [
      if (unwired.found)
        for (final g in removable) '${g.selectorType}.${g.getterName}',
    ];
    // Outside the facade it is somebody's connector, named rather than
    // rewritten — the same courtesy `remove --kind selector` extends.
    final readers = [
      for (final dir in [repo.appLib, repo.uiLib])
        if (dir.existsSync())
          for (final file in sourceIndex.filesUnder(dir))
            if (taken.any(
              (g) =>
                  sourceIndex.sourceOf(file).contains('.${g.split('.').last}'),
            ))
              file.path,
    ];
    return _FacadeUnwiring(
      wiring: [
        if (unwired.found)
          Wiring.of(
            'Selectors',
            selectors.file,
            unwired,
            way: WiringWay.unwired,
          ),
      ],
      getters: taken,
      readers: [
        ...readers,
        for (final k in kept) '${selectors.file.path} ($k, read by a sibling)',
      ],
    );
  }

  /// The "nothing of this kind here" message, told in terms of where it looked.
  /// A bare "not found" leaves the user unable to tell a typo from a wrong
  /// `--kind`, which is the mistake this command's kind list makes easy.
  String notFound(RemovableKind kind, Casing name, String? state) =>
      switch (kind) {
        .action =>
          'No action "${name.pascal}" under '
              '${state == null ? 'any substate' : 'substate "$state"'} '
              '(looked for ${name.snake}_action.dart in redux/*/actions/).',
        .model =>
          'No model or enum "${name.pascal}" — models/lib/${name.snake}.dart '
              'does not exist.',
        .widget =>
          'No widget "${name.pascal}" — no ${name.snake}.dart in any ui/lib '
              'widget folder.',
        .connector =>
          'No connector "${name.pascal}" — '
              'app/lib/connectors/${name.snake}_connector.dart does not exist.',
        .service =>
          'No service "${name.pascal}" — '
              'business/lib/redux/services/${name.snake}/ does not exist.',
      };
}

/// What `remove <action>` takes out of the facade, and what it had to leave.
class _FacadeUnwiring {
  const _FacadeUnwiring({
    required this.wiring,
    required this.getters,
    required this.readers,
  });

  final List<Wiring> wiring;

  /// The getters removed, as `SelectX.isWaiting`.
  final List<String> getters;

  /// Files still reading one of them, plus any getter kept for a reader
  /// inside the facade.
  final List<String> readers;
}
