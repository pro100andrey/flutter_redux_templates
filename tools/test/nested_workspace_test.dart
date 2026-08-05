import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/workspace/frx_workspace.dart';

/// Finding the project when it is not the repository.
///
/// Walking up alone assumes the project is at or above where you stand, which
/// holds only when the project *is* the checkout. A template unpacked into
/// somebody else's monorepo is not: `bloom/` is a pub workspace whose own root
/// has no router, and the app sits in `apps/tm_console`. Every command run from
/// the outer root failed with "run this from inside the monorepo" while the
/// project was one directory down.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('frx_nested_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const marker = 'app/lib/navigation/app_router.dart';

  /// Make the origin look like a checkout, which is what the downward search
  /// requires before it will run at all.
  void repo() =>
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: outer\n');

  void project(String at) {
    File(p.join(tmp.path, at, marker))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('class AppRouter {}\n');
  }

  Directory locate(String from) => walkUpForMarker(
    p.join(tmp.path, from),
    marker,
    (origin) => 'nothing at $origin',
  );

  test('the project at the origin is found without searching', () {
    project('.');
    expect(locate('.').path, tmp.path);
  });

  test('walking up still wins from inside the project', () {
    project('.');
    Directory(p.join(tmp.path, 'business/lib/redux'))
      ..createSync(recursive: true);
    expect(locate('business/lib/redux').path, tmp.path);
  });

  test('a project one level down is found from the outer root', () {
    repo();
    project('apps/tm_console');
    expect(locate('.').path, p.join(tmp.path, 'apps/tm_console'));
  });

  test('two projects below are refused, and both are named', () {
    repo();
    project('apps/one');
    project('apps/two');
    expect(
      () => locate('.'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('apps/one'), contains('apps/two'), contains('--root')),
        ),
      ),
    );
  });

  test('naming one of two resolves it', () {
    project('apps/one');
    project('apps/two');
    expect(locate('apps/two').path, p.join(tmp.path, 'apps/two'));
  });

  test('a project is not descended into', () {
    // Its member packages are packages. A nested router below a found project
    // must not turn one project into two and trip the ambiguity error.
    repo();
    project('apps/tm_console');
    project('apps/tm_console/example');
    expect(locate('.').path, p.join(tmp.path, 'apps/tm_console'));
  });

  test('nothing anywhere keeps the caller’s own message', () {
    // The search adds a case; it does not take over the reporting. A project
    // that simply is not there still says what was looked for.
    Directory(p.join(tmp.path, 'empty')).createSync();
    expect(
      () => locate('empty'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('nothing at'),
        ),
      ),
    );
  });

  test('build output and platform shells are not walked', () {
    // Not a preference — a `build/` tree can be enormous, and an `ios/` folder
    // cannot hold a project of ours. Finding one there would also be wrong.
    repo();
    project('build/generated/app');
    expect(() => locate('.'), throwsA(isA<StateError>()));
  });

  test('a directory that is not a repo is not searched at all', () {
    // The cost this bounds: the scan used to run on every failed walk-up, so a
    // command typed in a home directory walked three levels of everything under
    // it to report the same error it used to report instantly. A project could
    // only have been unpacked somewhere that looks like a checkout, so that is
    // the test — and it is two `existsSync` calls, not a walk.
    project('apps/tm_console');
    // No pubspec.yaml and no .git at the origin: nothing here says "repository".
    expect(() => locate('.'), throwsA(isA<StateError>()));
  });

  test('a pubspec at the origin is enough to look', () {
    repo();
    project('apps/tm_console');
    expect(locate('.').path, p.join(tmp.path, 'apps/tm_console'));
  });

  test('a .git at the origin is enough to look', () {
    // `bloom` has both; a checkout that vendors no root pubspec has only this.
    Directory(p.join(tmp.path, '.git')).createSync();
    project('apps/tm_console');
    expect(locate('.').path, p.join(tmp.path, 'apps/tm_console'));
  });

  test('the search stops before it becomes a full-disk walk', () {
    // Stated rather than left to chance: past three levels the scan costs more
    // than the case it serves, so this is a known edge, not a mystery.
    repo();
    project('a/b/c/d');
    expect(() => locate('.'), throwsA(isA<StateError>()));
  });
}
