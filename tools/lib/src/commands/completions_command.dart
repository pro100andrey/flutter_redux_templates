import 'package:args/command_runner.dart';

import '../model/page_artifact.dart';
import '../model/target_resolver.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import '../util/console.dart';

/// Prints a shell completion script for `frx`. The scripts are tiny: they defer
/// every decision to `frx __complete`, so completions (including live substate /
/// route names) stay in sync with the CLI instead of being re-encoded in shell.
class CompletionsCommand extends Command<int> {
  @override
  String get name => 'completions';

  @override
  String get description => 'Print a shell completion script (bash|zsh|fish).';

  @override
  String get invocation => 'frx completions <bash|zsh|fish>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected one argument: bash | zsh | fish.');
    }
    final script = switch (rest.single) {
      'bash' => _bash,
      'zsh' => _zsh,
      'fish' => _fish,
      _ => usageException('Unknown shell "${rest.single}" (bash|zsh|fish).'),
    };
    console.out.write(script);
    return 0;
  }

  static const _bash = r'''
# frx bash completion. Add to ~/.bashrc:  source <(frx completions bash)
_frx_complete() {
  local IFS=$'\n'
  COMPREPLY=($(frx __complete -- "${COMP_WORDS[@]:1}" 2>/dev/null))
}
complete -o default -F _frx_complete frx
''';

  static const _zsh = r'''
# frx zsh completion. Add to ~/.zshrc:  source <(frx completions zsh)
_frx() {
  local -a c
  c=(${(f)"$(frx __complete -- ${words[2,-1]} 2>/dev/null)"})
  compadd -- $c
}
compdef _frx frx
''';

  static const _fish = r'''
# frx fish completion. Save to ~/.config/fish/completions/frx.fish
function __frx_complete
  set -l tokens (commandline -opc) (commandline -ct)
  frx __complete -- $tokens[2..-1] 2>/dev/null
end
complete -c frx -f -a '(__frx_complete)'
''';
}

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
    // `runner.commands` keys every alias too, so candidates can repeat — emit
    // each match once.
    final seen = <String>{};
    for (final c in _candidates(words)) {
      if (c.startsWith(current) && seen.add(c)) console.out.writeln(c);
    }
    return 0;
  }

  List<String> _candidates(List<String> words) {
    // Completing the command name itself (first token).
    if (words.length <= 1) return _commandNames();

    final command = runner!.commands[words.first];
    if (command == null) return const [];
    final current = words.last;
    final prev = words[words.length - 2];

    // A flag: offer the command's long options.
    if (current.startsWith('-')) {
      return [for (final o in command.argParser.options.keys) '--$o'];
    }
    // The value for an option with a fixed allowed set (e.g. --kind).
    if (prev.startsWith('--')) {
      final opt = command.argParser.options[prev.substring(2)];
      if (opt?.allowed != null) return opt!.allowed!.toList();
      if (prev == '--state') return _substateNames();
      // Existing folders only — `--dir` also accepts a new name, which no
      // completion can guess.
      if (prev == '--dir') return _widgetDirs();
    }
    // A positional name for a command that targets an artifact.
    switch (command.name) {
      case 'remove' || 'rename' || 'which':
        return [..._substateNames(), ..._routeNames()];
      case 'add-field' || 'add-selector' || 'add-action':
        return _substateNames();
    }
    return const [];
  }

  List<String> _commandNames() => [
    for (final c in runner!.commands.values)
      if (!c.hidden) c.name,
  ];

  List<String> _substateNames() => _safely(() {
    final appState = TargetResolver.locate(null).appState;
    if (appState == null) return const [];
    return [
      for (final s in appState.readSubstates())
        if (s.isSubstate) Casing.parse(s.field).snake,
    ];
  });

  List<String> _widgetDirs() =>
      _safely(() => FrxWorkspace.locate().widgetDirs());

  List<String> _routeNames() => _safely(() {
    final routes = TargetResolver.locate(null).routes;
    if (routes == null) return const [];
    return [
      for (final r in routes.readRoutes())
        if (PageArtifact.fromRouteType(r.routeType) case final a?) a.name.snake,
    ];
  });

  /// Completion must never crash the shell — swallow any resolve/parse error.
  static List<String> _safely(List<String> Function() f) {
    try {
      return f();
    } catch (_) {
      return const [];
    }
  }
}
