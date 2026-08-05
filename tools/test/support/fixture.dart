import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tools/src/util/casing.dart';

/// Builds a minimal-but-real fixture monorepo in a temp directory, mirroring
/// the shapes the AST sources parse (`app_state.dart`, `selectors.dart`,
/// `app_router.dart`) so tests exercise the same code paths as the live repo.
///
/// Call [create] in `setUp` and [dispose] in `tearDown`. [root] is the repo
/// root to hand commands via `--root`.
class Fixture {
  Fixture._(this.root);

  final Directory root;

  /// Creates the fixture tree under a fresh temp dir.
  static Fixture create() {
    final root = Directory.systemTemp.createTempSync('frx_fixture_');
    final f = Fixture._(root);
    f._write();
    return f;
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  String path(String relative) => p.join(root.path, relative);

  File file(String relative) => File(path(relative));

  String read(String relative) => file(relative).readAsStringSync();

  void _write() {
    // --- workspace root ------------------------------------------------------
    // The fixture had no root pubspec, so it modelled a set of packages rather
    // than a workspace. `add-package` splices into the `workspace:` list, and a
    // fixture with no list to splice into would have failed for a reason the
    // real repo cannot have. The comment is here on purpose: the splice is a
    // `yaml_edit` edit precisely so prose like this survives it.
    _put('pubspec.yaml', '''
name: frx_fixture
publish_to: none

environment:
  sdk: ^3.12.0

# Pub workspaces. Each listed directory holds a pubspec with
# `resolution: workspace`.
workspace:
  - models
  - http_client
  - ui
  - business
  - app
''');

    // --- business ------------------------------------------------------------
    _put('business/pubspec.yaml', 'name: business\n');
    _put('business/lib/redux/app_state.dart', _appState);
    _put('business/lib/redux/selectors.dart', _selectors);

    // Two wired substates on disk, as real @freezed state classes so field /
    // selector edits have something to parse.
    for (final s in const ['connectivity', 'log_in']) {
      _put('business/lib/redux/$s/models/${s}_state.dart', _stateModel(s));
    }

    // --- app -----------------------------------------------------------------
    _put('app/pubspec.yaml', 'name: app\n');
    _put('app/lib/navigation/app_router.dart', _appRouter);
    for (final c in const ['log_in', 'home']) {
      _put(
        'app/lib/connectors/${c}_page_connector.dart',
        '@RoutePage()\nclass ${_pascal(c)}PageConnector {}\n',
      );
    }

    // --- ui ------------------------------------------------------------------
    _put('ui/pubspec.yaml', 'name: ui\n');
    for (final page in const ['log_in', 'home']) {
      _put('ui/lib/pages/${page}_page.dart', '// $page page\n');
    }
    // Keep the widgets dir present for add-widget targets.
    _put('ui/lib/widgets/.keep', '');

    // --- models / http_client (for add-model / add-retrofit targets) ---------
    _put('models/pubspec.yaml', 'name: models\n');
    _put('models/lib/.keep', '');
    _put('http_client/pubspec.yaml', 'name: http_client\n');
    _put('http_client/lib/api/.keep', '');
  }

  void _put(String relative, String content) {
    File(path(relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Deliberately the CLI's own [Casing], not a local reimplementation: this
  /// used to be a private `snake.split('_')…` that computed expected class
  /// names by a *different* algorithm than the code under test, so the two
  /// could disagree without a single test noticing.
  static String _pascal(String snake) => Casing.parse(snake).pascal;

  /// A real `@freezed` state class for substate [snake] (one nullable field).
  static String _stateModel(String snake) {
    final pascal = _pascal(snake);
    return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${snake}_state.freezed.dart';

@freezed
abstract class ${pascal}State with _\$${pascal}State {
  const factory ${pascal}State({String? value}) = _${pascal}State;
}
''';
  }

  // --- fixture sources (already dart-formatted) ------------------------------

  static const _appState = '''
import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'connectivity/models/connectivity_state.dart';
import 'log_in/models/log_in_state.dart';

export 'selectors.dart';

part 'app_state.freezed.dart';

@freezed
abstract class AppState with _\$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LogInState logIn,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    connectivity: ConnectivityState(),
    logIn: LogInState(),
    wait: Wait.empty,
  );
}
''';

  static const _selectors = '''
import 'app_state.dart';

mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectLogIn get logIn => SelectLogIn(state);
}

extension type SelectConnectivity(AppState _state) {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectLogIn(AppState _state) {
  String? get email => _state.logIn.email;
}
''';

  static const _appRouter = '''
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';

import '../connectors/home_page_connector.dart';
import '../connectors/log_in_page_connector.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'PageConnector|Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._store);

  final Store<AppState> _store;

  @override
  List<AutoRouteGuard> get guards => [_AuthGuard(_store)];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LogInRoute.page, path: '/log-in'),
    AutoRoute(page: HomeRoute.page, path: '/home'),
  ];
}

class _AuthGuard extends AutoRouteGuard {
  const _AuthGuard(this._store);

  final Store<AppState> _store;

  static const _authArea = {
    LogInRoute.name,
  };

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    resolver.next();
  }
}
''';
}

/// Runs the CLI as a subprocess. Returns the completed process result; [args]
/// are the CLI arguments (`--root <fixture>` is appended when not already set).
///
/// Prefer `runInProcess` from `in_process.dart` — since the console moved
/// behind a sink, a command test is a function call rather than a spawn. This
/// stays for what a zone cannot reach: anything asserting on a command that
/// shells out, and the fidelity check in `commands_test.dart` that runs both
/// and requires the same bytes.
Future<ProcessResult> runFrx(Fixture fixture, List<String> args) async =>
    Process.run('dart', [
      await _snapshot(),
      ...args,
      if (!args.contains('--root')) ...['--root', fixture.root.path],
    ]);

/// Runs the CLI with `Directory.current` set to the fixture root (for commands
/// that resolve by cwd, like `__complete`). No `--root` is appended.
Future<ProcessResult> runFrxIn(Fixture fixture, List<String> args) async =>
    Process.run('dart', [
      await _snapshot(),
      ...args,
    ], workingDirectory: fixture.root.path);

/// The CLI compiled to a kernel snapshot, built once and reused.
///
/// The suite shells out ~36 times, and `dart run bin/frx.dart` re-compiles the
/// CLI — `analyzer` and all — on every call: ~4.9s each, which is where the
/// wall-clock went. A kernel snapshot costs ~2.5s to build once and ~0.2s per
/// run. Kept under `.dart_tool/` (already ignored) and rebuilt whenever a
/// source file is newer than it, so a stale binary can never mask an edit.
Future<String>? _pending;
Future<String> _snapshot() => _pending ??= _buildSnapshot();

Future<String> _buildSnapshot() async {
  final out = File(p.join('.dart_tool', 'frx_test', 'frx.dill')).absolute;
  if (!_isStale(out)) return out.path;

  out.parent.createSync(recursive: true);
  // Stage the build in a unique directory beside the target and rename it into
  // place. `dart test` runs suites as isolates of ONE process, so they share a
  // pid — a pid-tagged temp name is not unique, and concurrent builds would
  // clobber each other's output. `createTempSync` is unique by construction,
  // and staging next to the target keeps the rename on one filesystem.
  final stage = out.parent.createTempSync('build_');
  try {
    final tmp = File(p.join(stage.path, 'frx.dill'));
    final r = await Process.run('dart', [
      'compile',
      'kernel',
      File(p.join('bin', 'frx.dart')).absolute.path,
      '-o',
      tmp.path,
    ]);
    if (r.exitCode != 0) {
      throw StateError('could not compile the CLI for tests:\n${r.stderr}');
    }
    tmp.renameSync(out.path);
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
  return out.path;
}

/// Whether [snapshot] is missing or older than any `lib/` or `bin/` source.
bool _isStale(File snapshot) {
  if (!snapshot.existsSync()) return true;
  final built = snapshot.lastModifiedSync();
  for (final dir in [Directory('lib'), Directory('bin')]) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.lastModifiedSync().isAfter(built)) return true;
    }
  }
  return false;
}
