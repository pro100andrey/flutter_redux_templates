import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../model/substate_artifact.dart';
import '../redux/selectors_source.dart';
import '../scaffold/artifact_templates.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';
import 'wiring.dart';
import 'writing_command.dart';
import '../model/artifact_name.dart';

/// Scaffolds a `ReduxAction` into an existing substate's `actions/` folder.
class AddActionCommand extends WritingCommand {
  @override
  void describeArgs(ArgParser parser) {
    parser
      ..addOption(
        'state',
        abbr: 's',
        help:
            'The substate to add the action to (its folder under '
            'business/lib/redux, any casing).',
      )
      ..addOption(
        'kind',
        abbr: 'k',
        allowed: ['sync', 'async', 'waiting'],
        defaultsTo: 'sync',
        help: 'Action body shape.',
        allowedHelp: {
          'sync': 'AppState? reduce() — synchronous state update.',
          'async': 'Future<AppState?> reduce() async — async work.',
          'waiting':
              'extends Action with WaitingAction — async + wait barrier.',
        },
      )
      ..addMultiOption(
        'mixin',
        abbr: 'm',
        allowed: ActionMixin.values.map((m) => m.name),
        help:
            'async_redux behaviour mixin (repeatable). Dependencies are added '
            'automatically (noDialog → checkInternet, unlimitedRetries → retry).',
        // Derived from the enum, so a mixin cannot be added without its
        // description showing up here — the hand-written copy this replaces had
        // drifted to eight of the ten.
        allowedHelp: {for (final m in ActionMixin.values) m.name: m.summary},
      )
      // Shaped like `add-field`'s, because it is the same rule: the completion
      // boundary wires what the artifact implies. A waiting action's only
      // observable aspect is whether it is running, so a page that cannot ask
      // is half-wired the way a field with no reader is.
      ..addFlag(
        'selector',
        defaultsTo: true,
        help:
            'For --kind waiting, also add the substate\'s `isWaiting` getter '
            'to its Select<Pascal> in selectors.dart.',
      );
  }

  @override
  String get name => 'add-action';

  @override
  String get description => 'Scaffold a ReduxAction into a substate.';

  @override
  String get invocation => 'frx add-action <name> --state <substate>';

  @override
  List<String> get aliases => ['aa'];

  @override
  Future<WritePlan> planFor(FrxWorkspace repo, ArgResults results) async {
    // Stripped so `ArchiveTask` and `ArchiveTaskAction` scaffold the same
    // artifact — and so `remove`, which strips, finds either.
    final name = ArtifactName.actionStem(requireName());
    final stateArg = results['state'] as String?;
    if (stateArg == null || stateArg.trim().isEmpty) {
      usageException('--state <substate> is required.');
    }

    final Casing state;
    try {
      state = Casing.parse(stateArg);
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final stateDir = Directory(p.join(repo.businessRedux.path, state.snake));
    if (!stateDir.existsSync()) {
      refuse(
        'Substate "${state.snake}" not found under ${p.relative(repo.businessRedux.path)}.\n'
        'Available: ${repo.substateDirs().join(', ')}',
      );
    }

    final kind = ActionKind.parse(results['kind'] as String);
    final mixins = ActionMixin.expand(results['mixin'] as List<String>);

    // async_redux makes some mixins mutually exclusive, enforced by a private
    // name collision — combining them is a compile error, not a runtime one.
    // Catch it here rather than write a file that cannot compile.
    final conflict = ActionMixin.conflictIn(mixins);
    if (conflict != null) {
      final (a, b) = conflict;
      usageException(
        'Mixins "${a.name}" and "${b.name}" cannot be combined — async_redux '
        'declares them mutually exclusive (${a.clause} and ${b.clause} would '
        'collide). Pick one.',
      );
    }

    final file = p.join(stateDir.path, 'actions', '${name.snake}_action.dart');

    // Most mixins make before()/reduce() effectively async — a sync action
    // carrying one must not be dispatched via dispatchSync.
    if (kind == ActionKind.sync &&
        mixins.any((m) => m != ActionMixin.nonReentrant)) {
      console.err.writeln(
        '⚠ These mixins do async work in before()/around reduce() — dispatch '
        'the action with dispatch()/dispatchAndWait(), not dispatchSync().',
      );
    }

    final mixinSuffix = mixins.isEmpty
        ? ''
        : ' + ${mixins.map((m) => m.clause).join(', ')}';

    final waiting = kind == ActionKind.waiting && (results['selector'] as bool)
        ? _waitingSelector(repo, state, name)
        : null;

    // A skipped reader goes to stderr, not into the plan's narration: narration
    // is the human report and is silent under `--json`, and the consumer that
    // needs to hear "the reader was not added" most is the agent the machine
    // format exists for. Warnings on stderr keep stdout parseable.
    if (waiting != null && waiting.edit == null) {
      console.err.writeln('⚠ ${waiting.note}');
    }

    return WritePlan(
      changes: Changeset([
        WriteFile(file, ArtifactTemplates.action(name, kind, mixins: mixins)),
      ])..addIf(waiting?.edit),
      header:
          'Action (${kind.name}$mixinSuffix) '
          '"${name.pascal}Action → ${state.snake}"',
      narrate: () {
        // The edit the plan is about to make; a skip has already gone to stderr.
        if (waiting?.edit != null) {
          console.out
            ..writeln('${p.relative(repo.selectorsFile.path)}:')
            ..writeln('  ${waiting!.note}')
            ..writeln();
        }
      },
    );
  }

  /// The substate's `isWaiting` getter, as an edit to `selectors.dart` plus the
  /// line to say about it.
  ///
  /// **Always named `isWaiting`, and never overwriting one that exists.** That
  /// matches the four already hand-written in this template, one per waiting
  /// action. A second waiting action in the same substate is reported as a taken
  /// name rather than disambiguated: naming the getter after the action would
  /// make those four an exception to their own rule, and naming only the later
  /// ones differently would make a selector's name depend on the order the
  /// artifacts happened to be created in.
  ///
  /// A substate whose selector block is absent (not wired, or no `selectors.dart`
  /// at all) gets the action and a note. The action is what was asked for; making
  /// the reader a precondition for it would refuse the whole command over the
  /// half it volunteered.
  _WaitingSelector? _waitingSelector(
    FrxWorkspace repo,
    Casing state,
    Casing action,
  ) {
    final selectors = SelectorsSource(repo.selectorsFile);
    if (!selectors.exists) {
      return const _WaitingSelector(
        null,
        'no selectors.dart — `isWaiting` not added.',
      );
    }
    final artifact = SubstateArtifact(state);
    final SelectorsAddResult result;
    try {
      result = selectors.addSelector(
        selectorType: artifact.selectorType,
        getterName: 'isWaiting',
        returnType: 'bool',
        // The idiom already in the template, four times over.
        expr: '_state.wait.isWaitingForType<${action.pascal}Action>()',
      );
    } on StateError {
      // The substate is not in the facade, so there is no block to add to.
      return _WaitingSelector(
        null,
        '${artifact.selectorType} is not wired — `isWaiting` not added '
        '(run `frx add-substate ${state.snake}` first, or add it by hand).',
      );
    }
    if (result.alreadyPresent) {
      return _WaitingSelector(
        null,
        '${artifact.selectorType}.isWaiting is taken — left as it is. Add a '
        'reader for ${action.pascal}Action by hand under a name of your own.',
      );
    }
    return _WaitingSelector(
      result.editTo(selectors.file),
      '+ ${artifact.selectorType}.isWaiting => '
      '_state.wait.isWaitingForType<${action.pascal}Action>()',
    );
  }
}

/// The `isWaiting` outcome: the edit to make, or null with a reason.
class _WaitingSelector {
  const _WaitingSelector(this.edit, this.note);

  final EditFile? edit;

  /// What to tell the author — the getter added, or why it was not.
  final String note;
}
