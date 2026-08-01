import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

import 'support/fixture.dart';

/// The folder list behind `--dir` completion and the extension's picker. It is
/// a suggestion, not the allowed set — `--dir` also takes a name that does not
/// exist yet — so what matters is that it only ever suggests real homes.
void main() {
  late Fixture fx;

  setUp(() => fx = Fixture.create());
  tearDown(() => fx.dispose());

  void put(String relative) {
    final f = File(p.join(fx.root.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('// x\n');
  }

  List<String> dirs() => FrxWorkspace(fx.root).widgetDirs();

  test('a folder holding widgets is suggested', () {
    put('ui/lib/buttons/button.dart');
    put('ui/lib/tiles/demo_tile.dart');
    expect(dirs(), containsAll(['buttons', 'tiles']));
  });

  test('an empty folder is not — it is no established home', () {
    // The fixture ships `ui/lib/widgets/.keep`: the folder the old default
    // created and nobody filled.
    expect(dirs(), isNot(contains('widgets')));
  });

  test('a folder with no .dart file is not suggested', () {
    put('ui/lib/assets/logo.svg');
    expect(dirs(), isNot(contains('assets')));
  });

  test('pages are excluded — add-page owns them, and wires the route', () {
    put('ui/lib/pages/home_page.dart');
    expect(dirs(), isNot(contains('pages')));
  });

  test('the non-widget layers are excluded', () {
    put('ui/lib/theme/common.dart');
    put('ui/lib/models/value_changed.dart');
    put('ui/lib/generated/assets.gen.dart');
    expect(dirs(), isNot(anyElement(isIn(['theme', 'models', 'generated']))));
  });

  test('the previews mirror is excluded, not offered as a home', () {
    put('ui/lib/previews/buttons/button.dart');
    expect(dirs(), isNot(contains('previews')));
  });

  test('the list is sorted, so the picker order is stable', () {
    put('ui/lib/tiles/a.dart');
    put('ui/lib/alerts/a.dart');
    put('ui/lib/inputs/a.dart');
    final got = dirs();
    expect(got, orderedEquals([...got]..sort()));
  });

  test('a ui package with no lib yields nothing rather than throwing', () {
    Directory(p.join(fx.root.path, 'ui', 'lib')).deleteSync(recursive: true);
    expect(dirs(), isEmpty);
  });

  test(
    'a non-widget folder is refused as --dir, not just unsuggested',
    () async {
      // The exclusion list governs what is offered; without it also guarding the
      // command, `--dir previews` writes a widget into its own mirror and its
      // preview into previews/previews/.
      for (final dir in ['previews', 'pages', 'theme', 'models']) {
        final res = await runFrx(fx, [
          'add-widget',
          'card',
          '-k',
          'view',
          '--dir',
          dir,
        ]);
        expect(res.exitCode, 64, reason: 'expected --dir $dir to be refused');
        expect(res.stderr, contains('not a widget folder'));
      }
    },
  );

  test('an existing folder is targetable as it is named', () async {
    // widgetDirs lists basenames verbatim, so a folder that predates the
    // convention must still be usable — otherwise completion offers a value
    // the command rejects.
    put('ui/lib/myWidgets/legacy.dart');
    expect(dirs(), contains('myWidgets'));
    final res = await runFrx(fx, [
      'add-widget',
      'card',
      '-k',
      'view',
      '--dir',
      'myWidgets',
    ]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    expect(fx.file('ui/lib/myWidgets/card.dart').existsSync(), isTrue);
  });

  test('a new folder still has to follow the convention', () async {
    final res = await runFrx(fx, [
      'add-widget',
      'card',
      '-k',
      'view',
      '--dir',
      'myCards',
    ]);
    expect(res.exitCode, 64);
    expect(res.stderr, contains('my_cards'));
  });
}
