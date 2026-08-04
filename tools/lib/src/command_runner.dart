import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'commands/add_action_command.dart';
import 'commands/add_connector_command.dart';
import 'commands/add_nav_command.dart';
import 'commands/add_enum_command.dart';
import 'commands/add_field_command.dart';
import 'commands/add_model_command.dart';
import 'commands/add_page_command.dart';
import 'commands/add_retrofit_command.dart';
import 'commands/add_selector_command.dart';
import 'commands/add_service_command.dart';
import 'commands/add_substate_command.dart';
import 'commands/add_tabs_command.dart';
import 'commands/add_theme_extension_command.dart';
import 'commands/add_widget_command.dart';
import 'commands/batch_command.dart';
import 'commands/completions_command.dart';
import 'commands/create_command.dart';
import 'commands/doctor_command.dart';
import 'commands/flow_command.dart';
import 'commands/graph_command.dart';
import 'commands/list_mixins_command.dart';
import 'commands/list_routes_command.dart';
import 'commands/list_widget_dirs_command.dart';
import 'commands/list_substates_command.dart';
import 'commands/new_command.dart';
import 'commands/remove_command.dart';
import 'commands/rename_command.dart';
import 'commands/watch_command.dart';
import 'commands/which_command.dart';
import 'config/frx_config.dart';
import 'engine/changeset.dart';
import 'version.dart';
import 'util/console.dart';

/// Root of the `frx` CLI — the dev toolbox for this Flutter Redux monorepo.
///
/// Commands are added here. Each command is a [Command] subclass under
/// `commands/` and returns an `int` exit code.
class FrxRunner extends CommandRunner<int> {
  FrxRunner()
    : super('frx', 'Dev CLI for the Flutter Redux monorepo (AST-based).') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the frx version and exit.',
    );
    addCommand(ListSubstatesCommand());
    addCommand(AddSubstateCommand());
    addCommand(ListRoutesCommand());
    addCommand(ListWidgetDirsCommand());
    addCommand(ListMixinsCommand());
    addCommand(AddPageCommand());
    addCommand(AddActionCommand());
    addCommand(AddFieldCommand());
    addCommand(AddWidgetCommand());
    addCommand(AddConnectorCommand());
    addCommand(AddNavCommand());
    addCommand(AddModelCommand());
    addCommand(AddEnumCommand());
    addCommand(AddSelectorCommand());
    addCommand(AddServiceCommand());
    addCommand(AddRetrofitCommand());
    addCommand(AddThemeExtensionCommand());
    addCommand(AddTabsCommand());
    addCommand(NewCommand());
    addCommand(CreateCommand());
    addCommand(BatchCommand());
    addCommand(RemoveCommand());
    addCommand(RenameCommand());
    addCommand(WhichCommand());
    addCommand(WatchCommand());
    addCommand(CompletionsCommand());
    addCommand(CompleteCommand());
    addCommand(FlowCommand());
    addCommand(GraphCommand());
    addCommand(DoctorCommand());
  }

  /// Short-circuits `--version` before command dispatch so `frx --version`
  /// works on its own (no subcommand required). Prints `frx <version>` — the
  /// VSCode extension parses this line to resolve and verify the binary.
  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    if (topLevelResults.flag('version')) {
      console.out.writeln('frx $frxVersion');
      return Future<int?>.value(0);
    }
    return super.runCommand(topLevelResults);
  }

  /// Runs the CLI, mapping argument-parsing problems to exit code 64 (EX_USAGE)
  /// so shells and CI can distinguish "you used it wrong" from a real failure.
  ///
  /// Named, because the editor reads them back — `scaffold.ts` keys on 70 to
  /// offer an overwrite, `artifact.ts` on 64 to raise a disambiguation picker.
  /// They travel into `contract.ts` with the rest of the contract rather than
  /// being spelled as bare numbers on both sides.
  ///
  /// The values are sysexits.h's, which is what a shell expects.

  /// You used it wrong: bad flags, an unknown kind, an ambiguous name.
  static const exitUsage = 64;

  /// It could not be done: not inside a project, a shape frx cannot wire, a
  /// changeset that failed and was rolled back.
  static const exitFailure = 70;

  Future<int> runFrx(List<String> args) async {
    try {
      return await run(_withConfigDefaults(args)) ?? 0;
    } on UsageException catch (e) {
      console.err.writeln(e.message);
      console.err.writeln();
      console.err.writeln(e.usage);
      return exitUsage;
    } on StateError catch (e) {
      // Commands throw StateError for user-facing "can't do this here" cases
      // (project not found, an AppState/selectors shape we can't wire). Surface
      // the message cleanly instead of letting it escape as an unhandled crash.
      console.err.writeln('✗ ${e.message}');
      return exitFailure;
    } on ApplyFailure catch (e) {
      // Caught here rather than per command because the guarantee being
      // reported — the tree is as it was — is the applier's, not any one
      // command's, and three call sites reach it: the writing-command tail,
      // `rename`, and the audit's orphan fixer. A non-zero exit is the whole
      // truth for a consumer that only needs to know whether it worked.
      console.err.writeln('✗ ${e.message}');
      return exitFailure;
    }
  }

  /// Applies `.frxrc` project defaults to [args] before dispatch — for the
  /// resolved command only, and only for flags the user didn't set.
  List<String> _withConfigDefaults(List<String> args) {
    final cmdName = args.firstWhere(
      (a) => !a.startsWith('-'),
      orElse: () => '',
    );
    if (cmdName.isEmpty) return args;
    final command = _resolveCommand(cmdName);
    if (command == null) return args;

    final config = FrxConfig.load(startDir: _rootArg(args));
    return config.applyTo(
      args,
      command.name,
      command.argParser.options.keys.toSet(),
    );
  }

  /// The command registered under [name] or one of its aliases.
  Command<int>? _resolveCommand(String name) {
    final direct = commands[name];
    if (direct != null) return direct;
    for (final c in commands.values) {
      if (c.aliases.contains(name)) return c;
    }
    return null;
  }

  /// The `--root <dir>` / `--root=<dir>` value in [args], if any — so `.frxrc`
  /// is looked up from the same place the command searches.
  static String? _rootArg(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--root' && i + 1 < args.length) return args[i + 1];
      if (args[i].startsWith('--root=')) {
        return args[i].substring('--root='.length);
      }
    }
    return null;
  }
}
