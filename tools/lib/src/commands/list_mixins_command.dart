import 'dart:convert';

import 'package:args/command_runner.dart';

import '../scaffold/artifact_templates.dart';
import 'options.dart';
import '../util/console.dart';

/// Lists the async_redux behaviour mixins `add-action` can attach, with what
/// each one implies and what it cannot be combined with.
///
/// Exists so the editor's multi-select does not carry its own copy. It did,
/// and the copy had drifted to eight of the ten — and it could not filter the
/// list as you picked, because the exclusion rule lived here.
class ListMixinsCommand extends Command<int> {
  ListMixinsCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Emit JSON ({mixins:[{name,clause,summary,implies,conflictsWith}]}) '
            'instead of a table.',
      )
      // The catalogue is compiled in, so nothing here reads the repo — but
      // every `--json` reader passes `--root`, and refusing it is the same as
      // not existing to them.
      ..addOption('root', help: kRootAcceptedHelp);
  }

  @override
  String get name => 'list-mixins';

  @override
  String get description =>
      'The action mixins, what they imply and what they exclude.';

  @override
  List<String> get aliases => ['lm'];

  @override
  Future<int> run() async {
    if (argResults!.flag('json')) {
      console.out.writeln(
        jsonEncode({
          'mixins': [
            for (final m in ActionMixin.values)
              {
                'name': m.name,
                'clause': m.clause,
                'summary': m.summary,
                'implies': m.implies?.name,
                'conflictsWith': [for (final c in m.conflictsWith) c.name],
              },
          ],
        }),
      );
      return 0;
    }

    final width = ActionMixin.values
        .map((m) => m.name.length)
        .reduce((a, b) => a > b ? a : b);
    console.out.writeln(
      'async_redux behaviour mixins  (frx add-action --mixin)',
    );
    console.out.writeln();
    for (final m in ActionMixin.values) {
      console.out.writeln('  ${m.name.padRight(width)}  ${m.summary}');
      // Computed once: it is a getter that rescans every mixin and allocates.
      final excludes = m.conflictsWith;
      final notes = [
        if (m.implies != null) 'implies ${m.implies!.name}',
        if (excludes.isNotEmpty)
          'excludes ${excludes.map((c) => c.name).join(', ')}',
      ];
      for (final note in notes) {
        console.out.writeln('  ${' ' * width}  ↳ $note');
      }
    }
    console.out
      ..writeln()
      ..writeln(
        '${ActionMixin.values.length} mixin(s). async_redux makes some pairs a '
        'compile error, so `add-action` refuses them up front.',
      );
    return 0;
  }
}
