import '../util/casing.dart';

/// The word an artifact kind's class name ends in, and the one place that says
/// so.
///
/// Read **forwards** by the scaffolders, which append it to build the class and
/// the file, and **backwards** by `remove`, which has to find that file from
/// whatever the user typed. The two directions disagreed, and precisely for the
/// name a user is most likely to reach for — the one they just read off the
/// class:
///
/// ```
/// frx add-action ArchiveTaskAction   →  class ArchiveTaskActionAction
///                                       archive_task_action_action.dart
/// frx remove     ArchiveTaskAction   →  looks for archive_task_action.dart
/// ```
///
/// `add` never stripped; `remove` always did. Same for `add-connector
/// ToolbarConnector`, which wrote `ToolbarConnectorConnector`.
///
/// The fix is to strip, not to stop stripping: the stem is what the templates
/// want (`${stem.pascal}Action`) and what the directory layout is keyed on, so
/// one normalisation at the front makes every downstream spelling agree
/// without touching any of them.
///
/// `WidgetScaffold` states the same rule for widgets, where it is richer — the
/// `--kind` decides the suffix, and `field` answers to both `Field` and
/// `FormField`. This is the flat case: one kind, one word.
class ArtifactName {
  const ArtifactName._();

  /// `ArchiveTask`, from either `ArchiveTask` or `ArchiveTaskAction`.
  static Casing actionStem(Casing name) => _stem(name, 'action');

  /// `Toolbar`, from either `Toolbar` or `ToolbarConnector`.
  static Casing connectorStem(Casing name) => _stem(name, 'connector');

  /// `Home`, from either `Home` or `HomePage`.
  ///
  /// The third one missed, and the one that mattered most: the skills tell
  /// agents "the suffix is optional and idempotent — pass the name as you have
  /// it", and an agent reads a page's class off `HomePage`. `add-page HomePage`
  /// wrote `class HomePagePage` into `home_page_page.dart`, with connector
  /// `HomePagePageConnector`, route `HomePageRoute` and path `/home-page`.
  /// Documentation that generalises is worse than none when one command does
  /// not honour it.
  static Casing pageStem(Casing name) => _stem(name, 'page');

  /// `Sync`, from either `Sync` or `SyncService`.
  ///
  /// Missed the first time round, on the premise that `service` had "no suffix
  /// rule left to get backwards". It has one — `add-service` writes `class
  /// ${n.pascal}Service` — so `add-service SyncService` produced
  /// `SyncServiceService` in `services/sync_service/`, the identical defect
  /// that had just been fixed for actions and connectors.
  static Casing serviceStem(Casing name) => _stem(name, 'service');

  /// [name] without a trailing [word] — unless that word is the whole name.
  ///
  /// `frx add-action Action` is a strange thing to type, but stripping it to
  /// nothing would scaffold `_action.dart` with an empty class name, and a
  /// crash or a nameless file is a worse answer than `ActionAction`. It still
  /// round-trips, which is the property that matters.
  static Casing _stem(Casing name, String word) =>
      name.words.length > 1 && name.words.last == word
      ? Casing(name.words.sublist(0, name.words.length - 1))
      : name;
}
