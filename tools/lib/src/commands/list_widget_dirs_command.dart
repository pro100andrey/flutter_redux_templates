import 'dart:convert';

import 'package:args/command_runner.dart';

import '../scaffold/widget_scaffold.dart';
import '../workspace/frx_workspace.dart';
import 'options.dart';
import '../util/console.dart';

/// Lists the folders under `ui/lib/` that already hold widgets — what
/// `add-widget --dir` suggests.
///
/// A suggestion, not the allowed set: `--dir` also takes a name that does not
/// exist yet and creates the folder. Read-only. `--json` is what the VSCode
/// folder picker consumes, so the two never disagree about what exists.
class ListWidgetDirsCommand extends Command<int> {
  ListWidgetDirsCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON ({dirs:[…], home:{kind:dir}}) instead of a list.',
      )
      ..addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'list-widget-dirs';

  @override
  String get description =>
      'List the ui/lib folders that hold widgets (add-widget --dir).';

  @override
  List<String> get aliases => ['lwd'];

  @override
  Future<int> run() async {
    final repo = FrxWorkspace.locate(startDir: argResults?['root'] as String?);
    final dirs = repo.widgetDirs();

    if (argResults!.flag('json')) {
      console.out.writeln(
        jsonEncode({
          'dirs': dirs,
          // Where each kind usually goes, so a picker can offer it first.
          // `view` has no home — a card, a tile and a header are all views.
          'home': {
            for (final k in WidgetKind.values)
              if (k.homeDir case final home?) k.name: home,
          },
        }),
      );
      return 0;
    }

    if (dirs.isEmpty) {
      console.out.writeln(
        'No widget folders under ui/lib yet — name one with --dir.',
      );
      return 0;
    }
    for (final d in dirs) {
      console.out.writeln(d);
    }
    return 0;
  }
}
