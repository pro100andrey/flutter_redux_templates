import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// End-to-end round-trip locks: run the real `frx` binary against a fixture
/// repo and assert that add→remove and rename→rename-back return the wired
/// source files byte-for-byte. These exercise the full command path the
/// refactor rewrites, so they are the primary regression net.
void main() {
  late Fixture fx;

  setUp(() {
    fx = Fixture.create();
    // Canonicalize the wiring files so a later `dart format` (run by the
    // scaffolders) can't change unrelated lines and break byte comparisons.
    Process.runSync('dart', [
      'format',
      fx.path('business/lib/redux/app_state.dart'),
      fx.path('business/lib/redux/selectors.dart'),
      fx.path('app/lib/navigation/app_router.dart'),
    ]);
  });
  tearDown(() => fx.dispose());

  test('add-substate → remove is byte-clean on AppState + selectors', () async {
    final appStateBefore = fx.read('business/lib/redux/app_state.dart');
    final selectorsBefore = fx.read('business/lib/redux/selectors.dart');

    final add = await runFrx(fx, ['add-substate', 'profile', '-k', 'value']);
    expect(add.exitCode, 0, reason: add.stderr.toString());
    expect(
      fx
          .file('business/lib/redux/profile/models/profile_state.dart')
          .existsSync(),
      isTrue,
    );
    // Sanity: the wiring really changed before we assert it reverts.
    expect(fx.read('business/lib/redux/app_state.dart'), isNot(appStateBefore));

    final remove = await runFrx(fx, ['remove', 'profile', '--force']);
    expect(remove.exitCode, 0, reason: remove.stderr.toString());

    expect(fx.read('business/lib/redux/app_state.dart'), appStateBefore);
    expect(fx.read('business/lib/redux/selectors.dart'), selectorsBefore);
    expect(
      Directory(fx.path('business/lib/redux/profile')).existsSync(),
      isFalse,
    );
  });

  test(
    'add-page → remove is byte-clean on AppRouter and drops files',
    () async {
      final routerBefore = fx.read('app/lib/navigation/app_router.dart');

      final add = await runFrx(fx, ['add-page', 'settings', '--public']);
      expect(add.exitCode, 0, reason: add.stderr.toString());
      expect(fx.file('ui/lib/pages/settings_page.dart').existsSync(), isTrue);
      expect(
        fx.file('app/lib/connectors/settings_page_connector.dart').existsSync(),
        isTrue,
      );
      expect(
        fx.read('app/lib/navigation/app_router.dart'),
        isNot(routerBefore),
      );

      final remove = await runFrx(fx, [
        'remove',
        'settings',
        '--kind',
        'page',
        '--force',
      ]);
      expect(remove.exitCode, 0, reason: remove.stderr.toString());

      expect(fx.read('app/lib/navigation/app_router.dart'), routerBefore);
      expect(fx.file('ui/lib/pages/settings_page.dart').existsSync(), isFalse);
      expect(
        fx.file('app/lib/connectors/settings_page_connector.dart').existsSync(),
        isFalse,
      );
    },
  );

  test('rename substate → rename-back is byte-clean on AppState', () async {
    final add = await runFrx(fx, ['add-substate', 'profile', '-k', 'value']);
    expect(add.exitCode, 0, reason: add.stderr.toString());
    final afterAdd = fx.read('business/lib/redux/app_state.dart');

    final fwd = await runFrx(fx, ['rename', 'profile', 'member', '--force']);
    expect(fwd.exitCode, 0, reason: fwd.stderr.toString());
    expect(
      fx
          .file('business/lib/redux/member/models/member_state.dart')
          .existsSync(),
      isTrue,
    );
    expect(
      Directory(fx.path('business/lib/redux/profile')).existsSync(),
      isFalse,
    );
    expect(
      fx.read('business/lib/redux/app_state.dart'),
      contains('MemberState'),
    );

    final back = await runFrx(fx, ['rename', 'member', 'profile', '--force']);
    expect(back.exitCode, 0, reason: back.stderr.toString());

    expect(fx.read('business/lib/redux/app_state.dart'), afterAdd);
    expect(
      fx
          .file('business/lib/redux/profile/models/profile_state.dart')
          .existsSync(),
      isTrue,
    );
  });

  test(
    'a mutating command leaves docs/flows fresh, so doctor stays quiet',
    () async {
      // The export is opt-in: creating the directory is what turns it on.
      expect((await runFrx(fx, ['flow', '--md'])).exitCode, 0);
      expect(File(fx.path('docs/flows/README.md')).existsSync(), isTrue);

      // Adding a page changes the routes the index describes. Before this was
      // wired, frx left its own output stale and doctor asked you to run a
      // second command to undo drift frx had just caused.
      expect((await runFrx(fx, ['add-page', 'profile'])).exitCode, 0);

      expect(
        fx.read('docs/flows/README.md'),
        contains('ProfilePage'),
        reason: 'the index picked up the new page without a second command',
      );
      expect(File(fx.path('docs/flows/profile.md')).existsSync(), isTrue);

      final doctor = await runFrx(fx, ['doctor', '--json']);
      expect(
        (doctor.stdout as String),
        isNot(contains('flow-docs')),
        reason: 'nothing left for doctor to report',
      );
    },
  );

  test('any mutating command leaves docs/flows fresh, not just the six', () async {
    // The refresh used to be a per-command decision — six of them called it by
    // name and the rest did not, with the list kept in a comment. Applying a
    // change now refreshes, so no command can be the one that forgot.
    //
    // `add-substate` is the probe because it is one that never refreshed. Note
    // what this does *not* claim: adding a substate cannot itself move the
    // export, which renders pages and what their actions write. What changed is
    // that the command no longer leaves an export stale that it found stale.
    expect((await runFrx(fx, ['flow', '--md'])).exitCode, 0);
    final fresh = fx.read('docs/flows/README.md');

    File(fx.path('docs/flows/README.md')).writeAsStringSync(
      fresh.replaceFirst('LogInPage', 'StaleNameThatIsNotThere'),
    );
    var doctor = await runFrx(fx, ['doctor', '--json']);
    expect(
      doctor.stdout as String,
      contains('flow-docs'),
      reason: 'the export really is stale before the command runs',
    );

    expect((await runFrx(fx, ['add-substate', 'cart'])).exitCode, 0);
    expect(fx.read('docs/flows/README.md'), fresh);

    doctor = await runFrx(fx, ['doctor', '--json']);
    expect(doctor.stdout as String, isNot(contains('flow-docs')));
  });

  test('remove takes --apply, and still answers to the retired --force', () {
    // `--force` means "overwrite" for every scaffolder, so spelling "actually
    // do it" the same way made `add-page --force` and `remove --force`
    // opposites. Renamed, but not broken for anyone already scripting it.
    Future<void> writesWith(List<String> flag) async {
      final fresh = Fixture.create();
      addTearDown(fresh.dispose);
      expect((await runFrx(fresh, ['add-substate', 'cart'])).exitCode, 0);
      expect((await runFrx(fresh, ['remove', 'cart', ...flag])).exitCode, 0);
      expect(
        Directory(fresh.path('business/lib/redux/cart')).existsSync(),
        isFalse,
        reason: '${flag.join()} applied the removal',
      );
    }

    return Future.wait([
      writesWith(['--apply']),
      writesWith(['--force']),
    ]);
  });

  test('remove without --apply only previews', () async {
    expect((await runFrx(fx, ['add-substate', 'cart'])).exitCode, 0);
    final res = await runFrx(fx, ['remove', 'cart']);
    expect(res.exitCode, 0);
    expect(res.stdout, contains('re-run with --apply'));
    expect(
      Directory(fx.path('business/lib/redux/cart')).existsSync(),
      isTrue,
      reason: 'a destructive command still previews by default',
    );
  });

  test('the export stays opt-in — no docs/flows, no docs written', () async {
    expect((await runFrx(fx, ['add-page', 'profile'])).exitCode, 0);
    expect(
      Directory(fx.path('docs')).existsSync(),
      isFalse,
      reason: 'a repo that never asked for the export must not grow one',
    );
  });

  group('a failed write is indistinguishable from one never attempted', () {
    // Wiring a page is five edits across two packages, four of which alone
    // leave code that does not compile — so these three cases are the defining
    // risk, not a corner case. Each seals a directory the command is about to
    // write into, so the failure lands *after* the applier has already done
    // work, and then asserts the whole repo is byte-identical.

    /// Every path under the fixture, files as bytes and directories as null.
    Map<String, List<int>?> tree() {
      final out = <String, List<int>?>{};
      for (final e in fx.root.listSync(recursive: true, followLinks: false)) {
        out[p.relative(e.path, from: fx.root.path)] = e is File
            ? e.readAsBytesSync()
            : null;
      }
      return out;
    }

    /// Makes [relative] unwritable for the rest of the test.
    ///
    /// Undone in `addTearDown` rather than at the end of the body: a failed
    /// expectation would otherwise leave the fixture undeletable, turning one
    /// failure into a second, unrelated one.
    void seal(String relative) {
      final target = fx.path(relative);
      Process.runSync('chmod', ['a-w', target]);
      addTearDown(() => Process.runSync('chmod', ['u+w', target]));
    }

    test('a write that fails part-way creates nothing', () async {
      // `add-page` writes the ui page, writes the connector, and edits the
      // router. Sealing the connectors directory fails the second write.
      seal('app/lib/connectors');
      final before = tree();

      final res = await runFrx(fx, ['add-page', 'settings', '--public']);

      expect(res.exitCode, 70, reason: res.stderr.toString());
      expect(res.stderr, contains('nothing was written'));
      expect(tree(), before);
    });

    test('a move that fails part-way puts the earlier moves back', () async {
      // Renaming a page moves the ui page first and the connector second.
      // Sealing the connectors directory fails the second move with the first
      // already carried out — and with the reference edits already written.
      seal('app/lib/connectors');
      final before = tree();

      // `home` rather than `log_in`, which names both a page and a substate and
      // would need a `--kind` this test has no reason to be about.
      final res = await runFrx(fx, ['rename', 'home', 'dashboard', '--apply']);

      expect(res.exitCode, 70, reason: res.stderr.toString());
      expect(tree(), before);
    });

    test('a delete that fails part-way restores what it removed', () async {
      // Deletes run first, so a later failure is the case that used to leave
      // files removed with their replacements never written.
      expect((await runFrx(fx, ['add-substate', 'cart'])).exitCode, 0);
      seal('business/lib/redux/app_state.dart');
      final before = tree();

      final res = await runFrx(fx, ['remove', 'cart', '--apply']);

      expect(res.exitCode, 70, reason: res.stderr.toString());
      expect(
        Directory(fx.path('business/lib/redux/cart')).existsSync(),
        isTrue,
        reason: 'the folder the delete pass removed is back',
      );
      expect(tree(), before);
    });
  }, skip: Platform.isWindows ? 'needs POSIX file modes' : null);
}
