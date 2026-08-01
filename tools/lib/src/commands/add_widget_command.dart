import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../scaffold/widget_scaffold.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// Scaffolds a widget in the `ui` package, plus its previews in the mirrored
/// `ui/lib/previews/` tree.
class AddWidgetCommand extends WritingCommand {
  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: WidgetKind.values.map((k) => k.name),
        defaultsTo: WidgetKind.view.name,
        help: 'What the widget takes in, and which primitive it wraps.',
        allowedHelp: const {
          'field': 'Takes a FieldVm; wraps InputFormField.',
          'choice': 'Takes a ChoiceVm; wraps ChoiceFormField.',
          'action': 'A labelled action; wraps Button.',
          'view': 'Draws a render model; the tap handler stays a parameter.',
          'container': 'Wraps other widgets; takes a child.',
        },
      )
      ..addOption(
        'dir',
        help:
            'Folder under ui/lib/ to write into, e.g. inputs. Required — a new '
            'name creates the folder. Completion lists the ones in use.',
      );
  }

  @override
  String get name => 'add-widget';

  @override
  String get description =>
      'Scaffold a widget (+ its previews) in the ui package.';

  @override
  String get invocation => 'frx add-widget <name> --dir <folder> [-k <kind>]';

  @override
  List<String> get aliases => ['aw'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    final name = requireName();
    final kind = WidgetKind.values.byName(results['kind'] as String);
    final dir = _requireDir(results['dir'] as String?, kind, repo);

    final scaffold = WidgetScaffold(name: name, kind: kind, dir: dir);
    final widgetFile = p.join(repo.uiLib.path, dir, scaffold.fileName);
    final previewFile = p.join(repo.uiPreviews.path, dir, scaffold.fileName);

    return WritePlan(
      changes: Changeset([
        WriteFile(widgetFile, scaffold.widget()),
        WriteFile(previewFile, scaffold.preview()),
      ]),
      header: 'Widget (${kind.name}) "${scaffold.className}"',
    );
  }

  /// The folder, validated. Required rather than defaulted: the old default
  /// filled `ui/lib/widgets/` with nothing — every real widget was placed by
  /// hand into a folder named for what it is.
  String _requireDir(String? value, WidgetKind kind, FrxWorkspace repo) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      final inUse = repo.widgetDirs();
      usageException(
        'Missing --dir: name the folder under ui/lib/ to write into.\n'
        '${inUse.isEmpty ? '' : 'In use: ${inUse.join(', ')}.\n'}'
        '${kind.homeDir == null ? '' : 'A ${kind.name} usually lives in ${kind.homeDir}.\n'}'
        'A name that does not exist yet creates the folder.',
      );
    }
    if (FrxWorkspace.notWidgetDirs.contains(raw)) {
      usageException(
        '--dir "$raw" is not a widget folder. ${_whyNot(raw)}\n'
        'Name the folder the widget belongs in, e.g. ${kind.homeDir ?? 'cards'}.',
      );
    }
    // An existing folder is targetable as it is named. Only a folder about to
    // be created has to follow the convention — otherwise completion and the
    // picker would offer names (`myWidgets`) that this then refuses.
    if (repo.widgetDirs().contains(raw)) return raw;

    // One path segment: a folder, not a path. Keeps `--dir ../../etc` and
    // nested trees out — the previews mirror assumes one level under lib/.
    final Casing parsed;
    try {
      parsed = Casing.parse(raw);
    } on FormatException catch (e) {
      usageException('Invalid --dir "$raw": ${e.message}');
    }
    if (parsed.snake != raw) {
      usageException(
        'Invalid --dir "$raw": a new folder needs a single lower_snake_case '
        'name (did you mean "${parsed.snake}"?).',
      );
    }
    return parsed.snake;
  }

  static String _whyNot(String dir) => switch (dir) {
    'previews' =>
      'It mirrors the package — a widget there would preview itself.',
    'pages' => 'A page is scaffolded by `frx add-page`, which wires its route.',
    _ => 'It holds $dir, not widgets.',
  };
}
