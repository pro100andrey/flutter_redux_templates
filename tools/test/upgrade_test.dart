import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/upgrade/upgrade.dart';

/// Upgrading the binary in place.
///
/// Against a real HTTP server rather than a stubbed client: the parts that can
/// actually be wrong here are the redirect read, the checksum round-trip, the
/// unpack and the rename over a running file — and a fake client would confirm
/// none of them. The server serves a release built in a temp directory, so the
/// test exercises the same bytes-to-binary path a user gets and reaches nothing
/// outside localhost.
void main() {
  late Directory root;
  late HttpServer server;
  late String base;

  /// Everything a release consists of: an archive per asset, and the
  /// `checksums.txt` the upgrade refuses to proceed without.
  Future<void> publish(String version, String slug, String payload) async {
    final staging = Directory(p.join(root.path, 'staging'))
      ..createSync(recursive: true);
    final exe = File(
      p.join(staging.path, Platform.isWindows ? 'frx.exe' : 'frx'),
    )..writeAsStringSync(payload);

    final ext = Platform.isWindows ? '.zip' : '.tar.gz';
    final asset = 'frx-$version-$slug$ext';
    final assetFile = File(p.join(root.path, 'serve', asset))
      ..parent.createSync(recursive: true);

    // `-C <dir>` *before* the member, which is the form both GNU tar and
    // bsdtar read the same way. Trailing it after the file list happens to work
    // on one of them and is a coin toss to reason about on the other.
    final tar = Process.runSync('tar', [
      if (Platform.isWindows) ...['-a', '-cf'] else '-czf',
      assetFile.path,
      '-C',
      staging.path,
      p.basename(exe.path),
    ]);
    expect(
      tar.exitCode,
      0,
      reason:
          'tar exited ${tar.exitCode}: ${tar.stderr}\n'
          'These fixtures build a release with the system tar, which is also '
          'what `frx upgrade` unpacks with — without it the feature cannot '
          'work and neither can its tests.',
    );

    final digest = sha256.convert(assetFile.readAsBytesSync());
    File(p.join(root.path, 'serve', 'checksums.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('$digest  $asset\n');
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('frx_upgrade_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      // `/releases/latest` answers the way github.com does — a redirect whose
      // Location names the tag — because that redirect is what the upgrader
      // reads, and a JSON stub would test a code path that does not exist.
      if (req.uri.path == '/releases/latest') {
        final tag = File(p.join(root.path, 'latest.txt')).readAsStringSync();
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '$base/releases/tag/$tag');
        await req.response.close();
        return;
      }
      final file = File(p.join(root.path, 'serve', p.basename(req.uri.path)));
      if (!file.existsSync()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      // A mirror that labels `.tar.gz` with `Content-Encoding: gzip` — the
      // misconfiguration that made Dart inflate what curl stores verbatim.
      if (File(p.join(root.path, 'gzip-encoding')).existsSync() &&
          req.uri.path.endsWith('.tar.gz')) {
        req.response.headers.set('content-encoding', 'gzip');
      }
      req.response.add(file.readAsBytesSync());
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  void latest(String tag) =>
      File(p.join(root.path, 'latest.txt')).writeAsStringSync(tag);

  /// A stand-in for the installed binary, in a directory the test owns.
  File installed(String contents) {
    final f =
        File(p.join(root.path, 'bin', Platform.isWindows ? 'frx.exe' : 'frx'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(contents);
    return f;
  }

  Upgrader upgrader(String current, File exe) => Upgrader(
    currentVersion: current,
    executable: exe,
    downloadBase: '$base/download',
    releasesUrl: '$base/releases/latest',
  );

  test('a lower published release is not an upgrade', () async {
    // `!=` called every difference an upgrade. A source build made after a
    // version bump lands but before its tag is published — where this
    // repository sits for most of a release — was told to upgrade *backwards*,
    // and `--check` exited 1 at it, which is what a gating script acts on.
    latest('v0.3.0');
    final exe = installed('newer local build');

    final result = await upgrader('0.4.0', exe).run(check: true);

    expect(result.status, UpgradeStatus.current);
    expect(exe.readAsStringSync(), 'newer local build');
  });

  test('a prerelease ranks below the release it precedes', () {
    expect(compareVersions('0.4.0-beta.1', '0.4.0'), lessThan(0));
    expect(compareVersions('0.4.0', '0.3.9'), greaterThan(0));
    expect(compareVersions('0.4.0', '0.4.0'), 0);
    expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
  });

  test('a pinned version installs downwards too', () async {
    // The comparison guards the *resolved* latest. Naming a version is how you
    // go back to one, so a pin is carried out in whichever direction it points.
    latest('v0.3.0');
    await publish('0.3.0', Upgrader.platformSlug!, 'the older build');
    final exe = installed('current');

    final result = await upgrader('0.4.0', exe).run(pinned: '0.3.0');

    expect(result.status, UpgradeStatus.upgraded);
    expect(exe.readAsStringSync(), 'the older build');
  });

  test('a mirror that gzip-encodes the archive still verifies', () async {
    // Dart advertises `accept-encoding: gzip` and inflates the reply, so a
    // server setting `Content-Encoding` from the file extension handed it the
    // inner tar while handing curl the archive — every checksum failing as
    // "tampered with" against a mirror `install.sh` reads without complaint.
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'served through a mirror');
    File(p.join(root.path, 'gzip-encoding')).writeAsStringSync('on');
    final exe = installed('old');

    final result = await upgrader('0.3.0', exe).run();

    expect(result.status, UpgradeStatus.upgraded);
    expect(exe.readAsStringSync(), 'served through a mirror');
  });

  test('a failed install leaves no half-written binary behind', () async {
    // The staged copy sits *beside* the real binary, in the directory on PATH.
    // Without cleanup a failure leaves a truncated executable there that
    // outlives the run and is one typo away from being executed. Here the copy
    // succeeds and the rename cannot: the target is a non-empty directory.
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'new');
    final blocked = Directory(p.join(root.path, 'bin', 'frx'))
      ..createSync(recursive: true);
    File(p.join(blocked.path, 'occupied')).writeAsStringSync('in the way');

    await expectLater(
      upgrader('0.3.0', File(blocked.path)).run(),
      throwsA(isA<UpgradeException>()),
    );
    expect(
      File('${blocked.path}.new').existsSync(),
      isFalse,
      reason:
          'the staging copy is swept when the install it was staged for does '
          'not happen',
    );
  });

  test('reads the latest version out of the redirect', () async {
    latest('v0.4.0');
    expect(await upgrader('0.3.0', installed('old')).latestVersion(), '0.4.0');
  });

  test('a tag without the v prefix reads the same', () async {
    latest('0.4.0');
    expect(await upgrader('0.3.0', installed('old')).latestVersion(), '0.4.0');
  });

  test('--check reports without touching the binary', () async {
    latest('v0.4.0');
    final exe = installed('old');
    final result = await upgrader('0.3.0', exe).run(check: true);

    expect(result.status, UpgradeStatus.available);
    expect(result.to, '0.4.0');
    expect(
      exe.readAsStringSync(),
      'old',
      reason: '--check is a question, and a question that writes is a trap',
    );
  });

  test('already current is said plainly, not upgraded to itself', () async {
    latest('v0.3.0');
    final result = await upgrader('0.3.0', installed('old')).run();
    expect(result.status, UpgradeStatus.current);
  });

  test('a newer release replaces the binary', () async {
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'brand new frx');
    final exe = installed('old');

    final result = await upgrader('0.3.0', exe).run();

    expect(result.status, UpgradeStatus.upgraded);
    expect(result.from, '0.3.0');
    expect(result.to, '0.4.0');
    expect(exe.readAsStringSync(), 'brand new frx');
  });

  test('the replacement is executable', () async {
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, '#!/bin/sh\necho hi\n');
    final exe = installed('old');
    await upgrader('0.3.0', exe).run();

    if (!Platform.isWindows) {
      // Read through `stat()`, not the `stat` *command*: its flags are
      // BSD-only here (`-f %Lp`) and GNU-only elsewhere (`-c %a`), so the
      // command form is a test that passes on the author's machine and fails
      // on Linux — which is exactly what it did.
      expect(
        exe.statSync().mode & 0x1FF,
        0x1ED, // 0o755
        reason:
            'an unpacked archive carries its own bits, and tar is not the '
            'only path here — the staged copy is chmod-ed on purpose',
      );
    }
  });

  test('--version installs the release it names', () async {
    latest('v0.9.9'); // ignored: the pin wins
    await publish('0.4.0', Upgrader.platformSlug!, 'pinned build');
    final exe = installed('old');

    final result = await upgrader('0.3.0', exe).run(pinned: 'v0.4.0');

    expect(result.to, '0.4.0');
    expect(exe.readAsStringSync(), 'pinned build');
  });

  test('a tampered archive replaces nothing', () async {
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'good');
    // Rewrite the asset after its checksum was recorded — a download that
    // arrived corrupt, or one somebody swapped.
    final ext = Platform.isWindows ? '.zip' : '.tar.gz';
    File(
      p.join(root.path, 'serve', 'frx-0.4.0-${Upgrader.platformSlug}$ext'),
    ).writeAsBytesSync(utf8.encode('not the archive you verified'));
    final exe = installed('old');

    await expectLater(
      upgrader('0.3.0', exe).run(),
      throwsA(
        isA<UpgradeException>().having(
          (e) => e.message,
          'message',
          contains('checksum mismatch'),
        ),
      ),
    );
    expect(
      exe.readAsStringSync(),
      'old',
      reason: 'the check is worth nothing if it fires after the replacement',
    );
  });

  test('a release with no checksums.txt is refused', () async {
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'good');
    File(p.join(root.path, 'serve', 'checksums.txt')).deleteSync();
    final exe = installed('old');

    await expectLater(
      upgrader('0.3.0', exe).run(),
      throwsA(isA<UpgradeException>()),
    );
    expect(exe.readAsStringSync(), 'old');
  });

  test('a missing asset names the release rather than the transport', () async {
    latest('v0.4.0'); // published nothing
    await expectLater(
      upgrader('0.3.0', installed('old')).run(),
      throwsA(
        isA<UpgradeException>().having(
          (e) => e.message,
          'message',
          contains('frx-0.4.0-'),
        ),
      ),
    );
  });

  test('running under `dart run` is refused, not attempted', () async {
    // `resolvedExecutable` is the SDK's own binary there, and replacing it with
    // a copy of frx is the one outcome nobody could want.
    latest('v0.4.0');
    final sdk = File(p.join(root.path, 'bin', 'dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('the dart sdk');

    final result = await upgrader('0.3.0', sdk).run();

    expect(result.status, UpgradeStatus.refused);
    expect(result.message, contains('dart run'));
    expect(sdk.readAsStringSync(), 'the dart sdk');
  });

  test('the running binary keeps working while it is replaced', () async {
    // Renamed over, not written through: a process mid-read of its own image
    // must not see it change under it. The old inode is kept open here to make
    // that concrete.
    latest('v0.4.0');
    await publish('0.4.0', Upgrader.platformSlug!, 'new');
    final exe = installed('old');
    final open = exe.openSync();
    addTearDown(open.closeSync);

    await upgrader('0.3.0', exe).run();

    expect(
      utf8.decode(open.readSync(3)),
      'old',
      reason: 'the handle still points at the image it was opened on',
    );
    expect(exe.readAsStringSync(), 'new');
  });
}
