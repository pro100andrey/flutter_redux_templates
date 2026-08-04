import 'dart:io';

import 'package:path/path.dart' as p;

import '../scaffold/widget_scaffold.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'artifact_name.dart';

/// The artifacts `remove` can delete that are *file sets* rather than wiring.
///
/// A substate and a page are not here, and the split is the point. Those two are
/// registered somewhere — a field in `AppState`, a route in `AppRouter` — so
/// removing one is an unwiring problem, resolved through [TargetResolver] from
/// what the project declares. Everything in this enum is instead a set of files
/// in a known place, scaffolded by a command that wired nothing central, and so
/// resolved from the filesystem.
///
/// Keeping the two apart is why `ArtifactKind` did not grow: it is also the
/// input to `rename` and `which`, which ask "what does this class name decompose
/// to" — a question no member of this enum answers, because none of them has a
/// class name convention to read backwards.
///
/// What this buys over `rm`, which is what the traced runs reached for 60+ times
/// across six builds: the *set*. A widget's preview mirrors it in another tree, a
/// service is two files in a folder, and a model leaves `.freezed.dart` and
/// `.g.dart` siblings that do not compile once their source is gone.
enum RemovableKind {
  /// `business/lib/redux/<substate>/actions/<snake>_action.dart` — one file,
  /// under whichever substate owns it.
  action,

  /// `models/lib/<snake>.dart`, plus its build_runner siblings. Covers `add-model`
  /// and `add-enum` alike: both write one file to the same directory, and from
  /// the outside a deleted freezed model and a deleted enum are the same job.
  model,

  /// `ui/lib/<dir>/<snake>.dart` and its preview under `ui/lib/previews/<dir>/`.
  widget,

  /// `app/lib/connectors/<snake>_connector.dart` — one file.
  connector,

  /// `business/lib/redux/services/<snake>/` — the service and its dispatcher.
  service;

  /// The spelling `--kind` takes.
  String get flag => name;
}

/// A located artifact: what would be deleted, and what the user should know.
class RemovableArtifact {
  const RemovableArtifact({
    required this.kind,
    required this.name,
    required this.header,
    required this.files,
    this.directories = const [],
    this.missing = const [],
    this.dangles,
  });

  final RemovableKind kind;
  final Casing name;

  /// The plan's one-line title, e.g. `Action "ArchiveTaskAction → tasks"`.
  final String header;

  /// Files that exist and will be deleted.
  final List<String> files;

  /// Directories deleted whole — a service's folder.
  final List<String> directories;

  /// Paths the convention predicts but the disk does not have. Narrated rather
  /// than treated as an error: a widget whose preview was already deleted is
  /// still a widget worth removing, and saying so is more useful than refusing.
  final List<String> missing;

  /// What is left dangling, in the closing note. `remove` deletes an artifact;
  /// it does not chase the code that referenced it — the same stance the
  /// substate path already takes.
  final String? dangles;
}

/// Resolves a name plus a [RemovableKind] to the files that make it up.
///
/// Returns null when nothing of that kind carries the name. A name it will not
/// answer for — matching under two substates, in two widget folders, or naming a
/// connector that belongs to a page — is reported through [blocked] rather than
/// guessed at, because picking one and deleting it is not a recoverable mistake.
class RemovableResolver {
  RemovableResolver(this.repo);

  final FrxWorkspace repo;

  /// Set when the last [resolve] declined to answer — more than one candidate,
  /// or a match that belongs to a bigger artifact. The message names the way
  /// forward, and the caller raises it as a usage error.
  String? blocked;

  RemovableArtifact? resolve(RemovableKind kind, Casing name, {String? state}) {
    blocked = null;
    return switch (kind) {
      RemovableKind.action => _action(name, state),
      RemovableKind.model => _model(name),
      RemovableKind.widget => _widget(name),
      RemovableKind.connector => _connector(name),
      RemovableKind.service => _service(name),
    };
  }

  // --- action ----------------------------------------------------------------

  RemovableArtifact? _action(Casing name, String? state) {
    // `ArchiveTask` and `ArchiveTaskAction` name the same file — see
    // [ArtifactName], which `add-action` now reads too, so the two directions
    // are the same statement rather than two that happen to agree.
    final snake = '${ArtifactName.actionStem(name).snake}_action';

    final hits = <String>[];
    for (final dir in state != null ? [state] : repo.substateDirs()) {
      final f = File(
        p.join(repo.businessRedux.path, dir, 'actions', '$snake.dart'),
      );
      if (f.existsSync()) hits.add(dir);
    }

    if (hits.isEmpty) return null;
    if (hits.length > 1) {
      blocked =
          '"${name.pascal}" names an action under ${hits.length} substates '
          '(${hits.join(', ')}). Disambiguate with --state <substate>.';
      return null;
    }

    final owner = hits.single;
    final file = p.join(
      repo.businessRedux.path,
      owner,
      'actions',
      '$snake.dart',
    );
    return RemovableArtifact(
      kind: RemovableKind.action,
      name: name,
      header: 'Remove action "${_pascalOf(snake)}"  (substate: $owner)',
      files: [file],
      dangles:
          'anything that dispatched it no longer compiles — run `frx doctor` / '
          '`dart analyze`',
    );
  }

  // --- model / enum ----------------------------------------------------------

  RemovableArtifact? _model(Casing name) {
    final source = File(p.join(repo.modelsLib.path, '${name.snake}.dart'));
    if (!source.existsSync()) return null;

    // The generated siblings go with it. Left behind they are the worse half of
    // the failure: `task.freezed.dart` still `part of 'task.dart'`, so the
    // package stops compiling on a file the user never wrote and did not delete.
    final generated =
        repo.modelsLib
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(
              (path) =>
                  FrxWorkspace.isGenerated(path) &&
                  p.basename(path).startsWith('${name.snake}.'),
            )
            .toList()
          ..sort();

    return RemovableArtifact(
      kind: RemovableKind.model,
      name: name,
      header: 'Remove model "${name.pascal}"',
      files: [source.path, ...generated],
      dangles:
          'code that imported it no longer compiles — run `frx doctor` / '
          '`dart analyze`',
    );
  }

  // --- widget ----------------------------------------------------------------

  /// The backward read of [WidgetScaffold.fileNameFor].
  ///
  /// A widget's file is named after its *class*, not after the argument: `-k
  /// field` turns `Pin` into `PinFormField` and writes `pin_form_field.dart`.
  /// So the name the user types does not name the file, and looking for
  /// `<typed>.dart` found nothing for exactly the kinds that rename — measured:
  /// `add-widget Pin --dir inputs -k field` then `remove Pin --kind widget`
  /// exited 70. Every kind's spelling is tried, because `remove` is not told
  /// which one built it.
  RemovableArtifact? _widget(Casing name) {
    final spellings = {
      for (final kind in WidgetKind.values)
        WidgetScaffold.fileNameFor(name, kind),
    };

    final hits = <({String dir, String file})>[];
    for (final dir in repo.widgetDirs()) {
      for (final file in spellings) {
        if (File(p.join(repo.uiLib.path, dir, file)).existsSync()) {
          hits.add((dir: dir, file: file));
        }
      }
    }

    if (hits.isEmpty) return null;

    // The name as typed, spelled straight, beats a suffix expansion of it.
    //
    // Not a guess — it is the narrower reading of the same input. With
    // `pin.dart` (a view) and `pin_form_field.dart` (a field) side by side,
    // every spelling of "Pin" matches something, and refusing left the view
    // unreachable: `PinFormField` names the field, and nothing names the view,
    // because `Pin` *is* its own name and was being read as ambiguous. So the
    // advice the refusal gave — "delete the one you mean by its own name" —
    // was advice one of the two could not take.
    final exact = hits.where((h) => h.file == '${name.snake}.dart').toList();
    final candidates = exact.length == 1 ? exact : hits;

    if (candidates.length > 1) {
      // Genuinely ambiguous: the same basename in two folders, or two
      // expansions with no straight spelling between them.
      final where = candidates.map((h) => 'ui/lib/${h.dir}/${h.file}').toList()
        ..sort();
      blocked =
          '"${name.pascal}" names ${candidates.length} widgets '
          '(${where.join(', ')}). Name the one you mean by its own class '
          '(${candidates.map((h) => _pascalOf(h.file.substring(0, h.file.length - 5))).toSet().join(' or ')}), '
          'or rename one of them first.';
      return null;
    }

    final hit = candidates.single;
    final widget = p.join(repo.uiLib.path, hit.dir, hit.file);
    final preview = p.join(repo.uiPreviews.path, hit.dir, hit.file);
    final hasPreview = File(preview).existsSync();
    // The class, read back off the file that was found — so the report names
    // what is being deleted rather than what was typed.
    final className = _pascalOf(hit.file.substring(0, hit.file.length - 5));

    return RemovableArtifact(
      kind: RemovableKind.widget,
      name: name,
      header: 'Remove widget "$className"  (ui/lib/${hit.dir})',
      files: [widget, if (hasPreview) preview],
      // A preview left behind imports a file that is gone, and the previewer
      // loads every file in the tree — so it fails on the whole mirror, not just
      // this entry. Worth naming even when it is already absent.
      missing: [if (!hasPreview) preview],
      dangles: 'anything that built it no longer compiles',
    );
  }

  // --- connector -------------------------------------------------------------

  RemovableArtifact? _connector(Casing name) {
    final snake = '${ArtifactName.connectorStem(name).snake}_connector';
    final file = File(p.join(repo.appConnectors.path, '$snake.dart'));
    if (!file.existsSync()) return null;

    // A page's connector is half of the page, not a connector of its own:
    // `add-page` writes both and registers the route against this file. Deleting
    // it alone leaves a route pointing at nothing — and the two are told apart by
    // the name, since `add-page` writes `<name>_page_connector.dart` where
    // `add-connector` writes `<name>_connector.dart`.
    //
    // Caught by `remove HomePage`, which auto-detection resolved here and would
    // have silently orphaned the page: the page's own canonical name is `Home`,
    // so the substate/page resolver did not recognise `HomePage` and raised no
    // ambiguity.
    if (snake.endsWith('_page_connector')) {
      final page = snake.substring(0, snake.length - '_page_connector'.length);
      blocked =
          '"${_pascalOf(snake)}" is the connector of page "$page", not a '
          'standalone connector — removing it alone would leave the route '
          'pointing at nothing. Remove the page instead: '
          'frx remove $page --kind page.';
      return null;
    }

    return RemovableArtifact(
      kind: RemovableKind.connector,
      name: name,
      header: 'Remove connector "${_pascalOf(snake)}"',
      files: [file.path],
      dangles: 'the route or widget that referenced it no longer compiles',
    );
  }

  // --- service ---------------------------------------------------------------

  RemovableArtifact? _service(Casing name) {
    final stem = ArtifactName.serviceStem(name);
    final dir = Directory(p.join(repo.businessServices.path, stem.snake));
    if (!dir.existsSync()) return null;

    final held =
        dir
            .listSync()
            .whereType<File>()
            .map((f) => p.relative(f.path, from: repo.root.path))
            .toList()
          ..sort();

    return RemovableArtifact(
      kind: RemovableKind.service,
      name: name,
      header:
          'Remove service "${stem.pascal}Service"  (${held.length} file(s))',
      files: const [],
      directories: [dir.path],
      // `add-service` does not write `dependencies.dart` either — the field that
      // constructs the service is hand-written, so removal stays symmetric and
      // points at it instead of editing it. Naming the file is the whole value:
      // it is the one place the project will not compile from.
      dangles:
          'business/lib/dependencies.dart still constructs it — drop its field '
          'and import',
    );
  }

  static String _pascalOf(String snake) => Casing.parse(snake).pascal;
}
