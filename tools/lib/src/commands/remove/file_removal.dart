import '../../engine/changeset.dart';
import '../../engine/write_path.dart';
import '../../model/removable_artifact.dart';
import '../../util/casing.dart';
import '../writing_command.dart';

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
mixin FileRemoval on WritingCommand {
  /// The plan for a kind that wired nothing central: delete the set, and say
  /// what stops compiling.
  WritePlan removeFiles(RemovableArtifact a, {required bool apply}) =>
      WritePlan(
        changes: Changeset([
          for (final f in a.files) DeleteFile(f),
          for (final d in a.directories) DeleteDirectory(d),
        ]),
        header: a.header,
        previewOnly: !apply,
        previewNotice: kPreviewNotice,
        closing: [
          '✓ Removed ${a.kind.flag} "${a.className}".',
          if (a.dangles != null) '  Note: ${a.dangles}.',
        ].join('\n'),
      );

  /// The "nothing of this kind here" message, told in terms of where it looked.
  /// A bare "not found" leaves the user unable to tell a typo from a wrong
  /// `--kind`, which is the mistake this command's kind list makes easy.
  String notFound(RemovableKind kind, Casing name, String? state) =>
      switch (kind) {
        RemovableKind.action =>
          'No action "${name.pascal}" under '
              '${state == null ? 'any substate' : 'substate "$state"'} '
              '(looked for ${name.snake}_action.dart in redux/*/actions/).',
        RemovableKind.model =>
          'No model or enum "${name.pascal}" — models/lib/${name.snake}.dart '
              'does not exist.',
        RemovableKind.widget =>
          'No widget "${name.pascal}" — no ${name.snake}.dart in any ui/lib '
              'widget folder.',
        RemovableKind.connector =>
          'No connector "${name.pascal}" — '
              'app/lib/connectors/${name.snake}_connector.dart does not exist.',
        RemovableKind.service =>
          'No service "${name.pascal}" — '
              'business/lib/redux/services/${name.snake}/ does not exist.',
      };
}
