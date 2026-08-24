import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../ast/mixin_chain_reader.dart';
import '../ast/source_index.dart';
import '../scaffold/artifact_templates.dart';
import '../workspace/frx_workspace.dart';
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
            'Emit JSON ({mixins:[{name,clause,summary,implies,conflictsWith,'
            'swallowsAfter}]}) instead of a table.',
      )
      // The catalogue is compiled in; the project's own mixins are not, and
      // reading them is what `--root` is now for. It used to be accepted and
      // ignored, which is why the one mixin that has to go last — the app's
      // `WaitingAction` — was missing from the command whose job is to say what
      // combines with what.
      ..addOption('root', help: kRootAcceptedHelp);
  }

  @override
  String get name => 'list-mixins';

  @override
  String get description =>
      'The action mixins, what they imply and what they exclude.';

  @override
  List<String> get aliases => ['lm'];

  /// The mixins the project declares on its own actions, or empty when there
  /// is no workspace here to read — this command answers about async_redux with
  /// or without one, and a missing repo is not a reason to fail.
  List<DeclaredMixin> _projectMixins() {
    final FrxWorkspace repo;
    try {
      repo = FrxWorkspace.locate(
        startDir: argResults!.option('root') ?? Directory.current.path,
      );
    } on Object {
      return const [];
    }
    if (!repo.businessRedux.existsSync()) return const [];
    return inSourceIndex(
      () => [
        for (final file in sourceIndex.filesUnder(repo.businessRedux))
          // A textual pre-filter, as everywhere else: `mixin ` is rare and
          // parsing every action file to find three declarations is not.
          if (sourceIndex.sourceOf(file).contains('mixin '))
            ...MixinChainReader.declaredIn(file),
      ],
    );
  }

  @override
  Future<int> run() async {
    final project = _projectMixins();

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
                'swallowsAfter': m.swallowsAfter,
              },
          ],
          'projectMixins': [
            for (final m in project)
              {
                'name': m.name,
                'on': m.on,
                'hooks': [
                  for (final h in m.hooks)
                    {'name': h.name, 'chainsSuper': h.chainsSuper},
                ],
                'swallowsAfter': m.swallowsAfter,
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
        // Third column, and the one that was missing while the order it
        // governs was wrong: excludes says which pairs will not compile,
        // implies says what has to precede this one — neither says which
        // mixin silently eats the other's cleanup.
        if (m.swallowsAfter)
          'ends the after() chain — anything whose after() must still run '
              '(WaitingAction) goes AFTER it',
      ];
      for (final note in notes) {
        console.out.writeln('  ${' ' * width}  ↳ $note');
      }
    }
    if (project.isNotEmpty) {
      final w = project
          .map((m) => m.name.length)
          .reduce((a, b) => a > b ? a : b);
      console.out
        ..writeln()
        ..writeln('this project declares  (business/lib/redux)')
        ..writeln();
      for (final m in project) {
        console.out.writeln('  ${m.name.padRight(w)}  on ${m.on}');
        for (final h in m.hooks) {
          console.out.writeln(
            '  ${' ' * w}  ↳ ${h.name}() '
            '${h.chainsSuper ? 'chains super — safe anywhere in the clause' : '**does not chain** — it must come LAST, and nothing that '
                      'needs its own ${h.name}() may follow it'}',
          );
        }
        if (m.hooks.isEmpty) {
          console.out.writeln('  ${' ' * w}  ↳ overrides no lifecycle hook');
        }
      }
    }

    console.out
      ..writeln()
      ..writeln(
        '${ActionMixin.values.length} mixin(s). An excluded pair is an '
        'analyzer error, so `add-action` refuses it up front rather than '
        'scaffolding a file the gate rejects. The third note is a different '
        'failure and a quieter one: no analyzer error, no assert, just '
        'cleanup that never runs.',
      );
    return 0;
  }
}
