import 'package:args/command_runner.dart';

import '../util/console.dart';

/// Prints a shell completion script for `frx`. The scripts are tiny: they defer
/// every decision to `frx __complete`, so completions (including live substate
/// / route names) stay in sync with the CLI instead of being re-encoded in
/// shell.
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
