import 'package:args/command_runner.dart';

import '../command_runner.dart';
import '../model/page_artifact.dart';
import '../model/target_resolver.dart';
import '../util/casing.dart';
import '../util/console.dart';
import '../workspace/frx_workspace.dart';

/// The completion engine behind the shell scripts: given the words typed so far
/// (as `rest`, after `--`), it prints one candidate per line for the last word.
/// Hidden from help — it's plumbing, not a user command.
class CompleteCommand extends Command<int> {
  @override
  String get name => '__complete';

  @override
  String get description => 'Internal: emit completion candidates.';

  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    final words = argResults!.rest;
    final current = words.isEmpty ? '' : words.last;
    // Candidates can repeat — a substate and a route may share a name — so
    // emit each match once.
    final seen = <String>{};
    for (final c in _candidates(words)) {
      if (c.startsWith(current) && seen.add(c)) {
        console.out.writeln(c);
      }
    }
    return 0;
  }

  List<String> _candidates(List<String> words) {
    // Completing the command name itself (first token).
    if (words.length <= 1) {
      return _commandNames();
    }

    final command = runner!.commands[words.first];
    if (command == null) {
      return const [];
    }
    final current = words.last;
    final prev = words[words.length - 2];

    // A flag: offer the command's long options.
    if (current.startsWith('-')) {
      return [for (final o in command.argParser.options.keys) '--$o'];
    }
    // The value for an option with a fixed allowed set (e.g. --kind).
    if (prev.startsWith('--')) {
      final opt = command.argParser.options[prev.substring(2)];
      if (opt?.allowed != null) {
        return opt!.allowed!.toList();
      }
      if (prev == '--state') {
        return _substateNames(_locate());
      }
      // Existing folders only — `--dir` also accepts a new name, which no
      // completion can guess.
      if (prev == '--dir') {
        return _widgetDirs();
      }
    }
    // A positional name for a command that targets an artifact.
    switch (command.name) {
      case 'remove' || 'rename' || 'which':
        // Located once for both: the resolver walks up (and, failing that,
        // down) for the two wiring files together.
        final resolver = _locate();
        return [..._substateNames(resolver), ..._routeNames(resolver)];
      case 'add-field' || 'add-selector' || 'add-action':
        return _substateNames(_locate());
    }
    return const [];
  }

  List<String> _commandNames() => [
    for (final c in (runner! as FrxRunner).visibleCommands) c.name,
  ];

  /// The wiring sources above the current directory, or null when even
  /// looking for them failed.
  static TargetResolver? _locate() {
    try {
      return TargetResolver.locate(null);
    } on Object catch (_) {
      return null;
    }
  }

  List<String> _substateNames(TargetResolver? resolver) => _safely(() {
    final appState = resolver?.appState;
    if (appState == null) {
      return const [];
    }

    return [
      for (final s in appState.readSubstates())
        if (s.isSubstate) Casing.parse(s.field).snake,
    ];
  });

  List<String> _widgetDirs() =>
      _safely(() => FrxWorkspace.locate().widgetDirs());

  List<String> _routeNames(TargetResolver? resolver) => _safely(() {
    final routes = resolver?.routes;
    if (routes == null) {
      return const [];
    }

    return [
      for (final r in routes.readRoutes())
        if (PageArtifact.fromRouteType(r.routeType) case final a?) a.name.snake,
    ];
  });

  /// Completion must never crash the shell — swallow any resolve/parse error.
  static List<String> _safely(List<String> Function() f) {
    try {
      return f();
    } on Object catch (_) {
      return const [];
    }
  }
}
