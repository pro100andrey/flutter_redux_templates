import 'package:args/command_runner.dart';

import '../scaffold/artifact_templates.dart';
import '../util/prompt.dart' as prompt;
import 'options.dart';
import '../util/console.dart';

/// `frx new` — an interactive wizard over the scaffolders: pick an artifact,
/// answer a few prompts, and the equivalent flag-driven command runs. The
/// built command line is echoed first, so the wizard doubles as a tutor for
/// the direct CLI.
class NewCommand extends Command<int> {
  NewCommand() {
    argParser.addOption('root', help: kRootHelp);
  }

  @override
  String get name => 'new';

  @override
  String get description =>
      'Interactive wizard — pick an artifact and answer prompts.';

  @override
  String get invocation => 'frx new';

  @override
  List<String> get aliases => ['i'];

  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9 _-]*$');
  static const _nameHint = 'letters/digits/spaces/_/-, starting with a letter';

  @override
  Future<int> run() async {
    final List<String> args;
    try {
      args = _build();
    } on prompt.AbortException {
      console.out.writeln('\nAborted.');
      return 64;
    }

    final root = argResults?['root'] as String?;
    if (root != null) args.addAll(['--root', root]);

    console.out
      ..writeln()
      ..writeln('> frx ${args.join(' ')}')
      ..writeln();
    return await runner!.run(args) ?? 0;
  }

  /// Prompts for one artifact and returns the argv for its command.
  List<String> _build() {
    final type = prompt.choose('What to scaffold', {
      'substate': 'AsyncRedux substate wired into AppState',
      'page': 'Page + @RoutePage() connector + route',
      'action': 'ReduxAction into a substate',
      'tabs': 'AutoTabsScaffold shell + tab pages',
      'model': 'freezed model (or sealed union)',
      'enum': 'plain enum',
      'widget': 'dumb StatelessWidget',
      'connector': 'StoreConnector for a widget',
      'service': 'service + Redux dispatcher pair',
      'retrofit': 'Retrofit @RestApi client',
      'theme-extension': 'ThemeExtension',
    });

    final name = prompt.ask(
      'Name (any casing)',
      pattern: _name,
      hint: _nameHint,
    );

    switch (type) {
      case 'substate':
        final kind = prompt.choose('Kind', {
          'value': 'single nullable value + SetValueAction',
          'search': 'query + IList<int> view + SetQueryAction',
          'table': 'byId IMap table + view + Add…/Retrieve… actions',
        });
        return ['add-substate', name, '-k', kind, ..._buildRunner()];
      case 'page':
        final public = prompt.confirm('Public (reachable while logged out)?');
        return ['add-page', name, if (public) '--public', ..._buildRunner()];
      case 'action':
        final state = prompt.ask(
          'Substate (its folder under redux)',
          pattern: _name,
          hint: _nameHint,
        );
        final kind = prompt.choose('Kind', {
          'sync': 'AppState? reduce()',
          'async': 'Future<AppState?> reduce() async',
          'waiting': 'extends Action with WaitingAction',
        });
        final mixins = prompt.askList(
          'Mixins, comma-separated '
          '(${ActionMixin.values.map((m) => m.name).join(', ')})',
        );
        return [
          'add-action',
          name,
          '-s',
          state,
          '-k',
          kind,
          for (final m in mixins) ...['-m', m],
        ];
      case 'tabs':
        final tabs = prompt.askList(
          'Tab pages, comma-separated (≥2)',
          min: 2,
          hint: 'e.g. home, profile',
        );
        return [
          'add-tabs',
          name,
          for (final t in tabs) ...['-t', t],
          ..._buildRunner(),
        ];
      case 'model':
        final cases = prompt.askList(
          'Union cases, comma-separated (empty = plain model)',
        );
        final json = prompt.confirm('With fromJson/toJson?');
        return [
          'add-model',
          name,
          if (json) '--json',
          for (final c in cases) ...['-c', c],
          ..._buildRunner(),
        ];
      case 'enum':
        final values = prompt.askList(
          'Values, comma-separated (≥1)',
          min: 1,
          hint: 'e.g. pending, done',
        );
        return [
          'add-enum',
          name,
          for (final v in values) ...['-v', v],
        ];
      case 'retrofit' || 'theme-extension':
        return ['add-$type', name, ..._buildRunner()];
      default: // widget, connector, service — name-only.
        return ['add-$type', name];
    }
  }

  List<String> _buildRunner() =>
      prompt.confirm('Run build_runner after?', def: true) ? ['-b'] : const [];
}
