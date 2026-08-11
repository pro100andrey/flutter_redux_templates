/// Replacing the installed `frx` with a newer release.
///
/// ## The one place frx touches the network
///
/// Every other command reads and writes the filesystem and nothing else, which
/// is a property worth naming rather than assuming: frx runs in a container
/// with no route out, behind a proxy that refuses unknown hosts, on a laptop on
/// a plane, and nothing about it changes. `upgrade` gives that up — but only
/// inside itself. There is no background check, no "a new version is available"
/// line appended to unrelated commands, and no telemetry: the network is
/// reached when, and only when, somebody types the command whose entire purpose
/// is to reach it.
///
/// ## What it does, and what it refuses
///
/// It resolves the latest release the way `install.sh` does — through the
/// redirect `/releases/latest` performs, not the JSON API, whose sixty requests
/// an hour are counted per IP and therefore shared with everyone behind the
/// same NAT — verifies the download against the release's `checksums.txt`, and
/// replaces the running executable.
///
/// It refuses rather than guesses when it is not the thing being upgraded: run
/// through `dart run`, there is no `frx` binary to replace, and rewriting the
/// Dart SDK's own executable is the one outcome nobody wants.
///
/// ## It needs `tar`
///
/// The one thing here frx does not do itself. bsdtar reads both archive formats
/// and ships with macOS, every Linux worth naming and Windows since 1803, so
/// the alternative is a second archive implementation to keep correct for a
/// dependency that is already present. A machine without it gets a sentence
/// saying so — and its absence is reported rather than crashed on, which is a
/// distinction this file got wrong once already.
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// What an upgrade attempt concluded.
enum UpgradeStatus {
  /// Already on the newest release.
  current,

  /// A newer release exists; with `--check`, nothing was downloaded.
  available,

  /// The binary was replaced.
  upgraded,

  /// Nothing was attempted, and [UpgradeResult.message] says why.
  refused,
}

/// The outcome, with everything a caller needs to report it.
class UpgradeResult {
  const UpgradeResult(this.status, {this.from, this.to, this.message});

  final UpgradeStatus status;
  final String? from;
  final String? to;

  /// Why it refused, or what it did. Never null for [UpgradeStatus.refused].
  final String? message;

  Map<String, Object?> toJson() => {
    'status': status.name,
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (message != null) 'message': message,
  };
}

/// Orders two `x.y.z[-pre]` versions: negative, zero or positive, like any
/// comparator.
///
/// Enough semver to answer "is this newer", and no more: the numeric triple
/// compared component-wise, and a build carrying a `-suffix` ranked below the
/// same triple without one, because that is what a prerelease is. A component
/// that is not a number sorts as 0 rather than throwing — a version string frx
/// cannot parse should not stop an upgrade from being *reported*, and the
/// install is gated on the checksum either way.
int compareVersions(String a, String b) {
  (List<int>, bool) parse(String v) {
    final dash = v.indexOf('-');
    final core = dash < 0 ? v : v.substring(0, dash);
    return (
      [for (final part in core.split('.')) int.tryParse(part) ?? 0],
      dash >= 0,
    );
  }

  final (left, leftPre) = parse(a);
  final (right, rightPre) = parse(b);
  for (var i = 0; i < 3; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  if (leftPre == rightPre) return 0;
  return leftPre ? -1 : 1;
}

/// Raised for a failure the caller should report as-is rather than interpret.
class UpgradeException implements Exception {
  UpgradeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Upgrades the running `frx`.
///
/// Everything ambient arrives through the constructor so the whole thing can be
/// exercised against a release served over localhost: the base URL, the binary
/// to replace, and the version to compare against. Without that seam the only
/// test of a self-replacing binary is publishing one.
class Upgrader {
  Upgrader({
    required this.currentVersion,
    required this.executable,
    String? downloadBase,
    String? releasesUrl,
    this.repo = 'pro100andrey/flutter_redux_templates',
  }) : _downloadBase =
           downloadBase ?? Platform.environment['FRX_DOWNLOAD_BASE'],
       _releasesUrl = releasesUrl;

  /// What the running binary reports — `frxVersion` in production.
  final String currentVersion;

  /// The file to replace. `Platform.resolvedExecutable` in production.
  final File executable;

  final String repo;
  final String? _downloadBase;
  final String? _releasesUrl;

  /// The platform slug the release assets are named with, or null when this
  /// platform has no build.
  ///
  /// From `Abi.current()` rather than `uname`: it is the ABI the running binary
  /// was compiled for, which is the question being asked — a `uname` on an ARM
  /// Mac running an x64 binary under Rosetta would answer about the machine and
  /// hand back an archive the process cannot exec.
  static String? get platformSlug => switch (Abi.current()) {
    Abi.macosArm64 => 'macos-arm64',
    Abi.macosX64 => 'macos-x64',
    Abi.linuxX64 => 'linux-x64',
    Abi.linuxArm64 => 'linux-arm64',
    Abi.windowsX64 => 'windows-x64',
    _ => null,
  };

  /// The archive extension for this platform: a zip on Windows, where it is
  /// what opens with no extra tool.
  static String get _archiveExt => Platform.isWindows ? '.zip' : '.tar.gz';

  /// Whether the running process is an installed binary at all.
  ///
  /// Under `dart run`, `resolvedExecutable` is the Dart SDK's own binary —
  /// upgrading would overwrite the SDK with a copy of frx.
  bool get _isCompiledBinary {
    final name = p.basenameWithoutExtension(executable.path);
    return name != 'dart' && name != 'dartaotruntime';
  }

  /// The newest published version, from the redirect `/releases/latest` sends.
  Future<String> latestVersion() async {
    final url = Uri.parse(
      _releasesUrl ?? 'https://github.com/$repo/releases/latest',
    );
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final location = response.headers.value('location');
      if (location == null) {
        throw UpgradeException(
          'github.com did not redirect $url to a release. Pass --version to '
          'name one, or check https://github.com/$repo/releases.',
        );
      }
      final match = RegExp(r'/tag/v?([^/]+?)/?$').firstMatch(location);
      if (match == null) {
        throw UpgradeException(
          '$url redirected to "$location", which names no release tag — which '
          'is what a repository with no published release looks like.',
        );
      }
      return match.group(1)!;
    } on SocketException catch (e) {
      throw UpgradeException('could not reach github.com — ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Check, and upgrade unless [check].
  Future<UpgradeResult> run({bool check = false, String? pinned}) async {
    if (!_isCompiledBinary) {
      return UpgradeResult(
        UpgradeStatus.refused,
        from: currentVersion,
        message:
            'this frx is running through `dart run`, so there is no installed '
            'binary to replace. Install one first — see tools/README.md — or '
            'upgrade the checkout with git.',
      );
    }

    final slug = platformSlug;
    if (slug == null) {
      return UpgradeResult(
        UpgradeStatus.refused,
        from: currentVersion,
        message:
            'no release is built for ${Abi.current()}. Build from source: '
            '`dart compile exe bin/frx.dart`.',
      );
    }

    // A pin is an instruction, not a suggestion: naming a version is how you go
    // back to one, so it is installed whichever direction it points. Only the
    // resolved-latest path is a *comparison*.
    if (pinned != null) {
      final target = pinned.replaceFirst(RegExp('^v'), '');
      if (target == currentVersion) {
        return UpgradeResult(
          UpgradeStatus.current,
          from: currentVersion,
          to: target,
        );
      }
      if (check) {
        return UpgradeResult(
          UpgradeStatus.available,
          from: currentVersion,
          to: target,
        );
      }
      await _install(target, slug);
      return UpgradeResult(
        UpgradeStatus.upgraded,
        from: currentVersion,
        to: target,
      );
    }

    final target = await latestVersion();

    // Ordered, not compared for inequality. `!=` called every difference an
    // upgrade, so a source build made after a version bump lands but before its
    // tag is published — the state this repository is in for most of a release —
    // was told to "upgrade" *backwards*, and `--check` exited 1 at it, which is
    // what a gating script acts on.
    if (compareVersions(target, currentVersion) <= 0) {
      return UpgradeResult(
        UpgradeStatus.current,
        from: currentVersion,
        to: target,
      );
    }
    if (check) {
      return UpgradeResult(
        UpgradeStatus.available,
        from: currentVersion,
        to: target,
      );
    }

    await _install(target, slug);
    return UpgradeResult(
      UpgradeStatus.upgraded,
      from: currentVersion,
      to: target,
    );
  }

  /// Download, verify, and put the new binary where the old one is.
  Future<void> _install(String version, String slug) async {
    final asset = 'frx-$version-$slug$_archiveExt';
    final base =
        _downloadBase ?? 'https://github.com/$repo/releases/download/v$version';

    final tmp = Directory.systemTemp.createTempSync('frx_upgrade_');
    try {
      final archive = File(p.join(tmp.path, asset));
      await _download('$base/$asset', archive);
      await _verify(archive, asset, base);
      _unpack(archive, tmp);

      final unpacked = File(
        p.join(tmp.path, Platform.isWindows ? 'frx.exe' : 'frx'),
      );
      if (!unpacked.existsSync()) {
        throw UpgradeException('$asset did not contain a frx executable');
      }
      _replace(unpacked);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  Future<void> _download(String url, File into) async {
    // `autoUncompress = false`, which is what makes this agree with `curl`.
    // Dart advertises `accept-encoding: gzip` and transparently inflates what
    // comes back; a server that sets `Content-Encoding: gzip` from the file
    // extension — a common misconfiguration for `.tar.gz` — therefore hands
    // Dart the *inner* tar while handing curl the archive, and every checksum
    // fails as "tampered with" against a mirror `install.sh` reads fine.
    final client = HttpClient()..autoUncompress = false;
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != HttpStatus.ok) {
        throw UpgradeException(
          'could not download ${p.basename(into.path)} — HTTP '
          '${response.statusCode} from $url',
        );
      }
      final sink = into.openWrite();
      await response.pipe(sink);
    } on SocketException catch (e) {
      throw UpgradeException('could not download $url — ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Compare the download against the release's own `checksums.txt`.
  ///
  /// Not optional and not a flag. The binary is about to replace the one on
  /// `PATH` without anybody watching, and a transfer that half-succeeded is
  /// indistinguishable from one that did not until it is run.
  Future<void> _verify(File archive, String asset, String base) async {
    final manifest = File(p.join(archive.parent.path, 'checksums.txt'));
    await _download('$base/checksums.txt', manifest);

    final line = manifest
        .readAsLinesSync()
        .where((l) => l.trimRight().endsWith(asset))
        .firstOrNull;
    if (line == null) {
      throw UpgradeException('$asset is not listed in checksums.txt');
    }
    final expected = line.split(RegExp(r'\s+')).first.toLowerCase();
    final actual = sha256.convert(archive.readAsBytesSync()).toString();
    if (actual != expected) {
      throw UpgradeException(
        'checksum mismatch for $asset — the download is corrupt or tampered '
        'with. Nothing was replaced.',
      );
    }
  }

  /// Unpack with the system `tar`.
  ///
  /// bsdtar reads both formats and ships with macOS, every Linux worth naming
  /// and Windows since 1803, so this costs no dependency. A missing `tar` is
  /// reported rather than worked around: the alternative is a second archive
  /// implementation to keep correct.
  void _unpack(File archive, Directory into) {
    final result = _run('tar', [
      Platform.isWindows ? '-xf' : '-xzf',
      archive.path,
      '-C',
      into.path,
    ], missing: 'tar is not on PATH, so the archive cannot be unpacked');
    if (result.exitCode != 0) {
      throw UpgradeException(
        'could not unpack ${p.basename(archive.path)} — tar exited '
        '${result.exitCode}. ${result.stderr}',
      );
    }
  }

  /// `Process.runSync` with the one failure it does not report through its
  /// result turned into one that is.
  ///
  /// A binary that is absent throws `ProcessException`, and nothing above this
  /// catches it: the docstring promised a missing `tar` would be "reported
  /// rather than worked around", and what actually happened was an unhandled
  /// exception, a Dart stack trace and exit 255 — the shape of a crash, for a
  /// condition the tool understands perfectly well.
  static ProcessResult _run(
    String executable,
    List<String> arguments, {
    required String missing,
  }) {
    try {
      return Process.runSync(executable, arguments);
    } on ProcessException catch (e) {
      throw UpgradeException('$missing (${e.message}).');
    }
  }

  /// Put [fresh] where [executable] is, without ever leaving the path empty.
  ///
  /// Rename, not copy-over-in-place: an in-place write to a running executable
  /// is a corrupt process on POSIX and simply refused on Windows. Renaming
  /// swaps the directory entry, so anything already running keeps the old inode
  /// and finishes normally.
  void _replace(File fresh) {
    final target = executable.path;
    final staged = File('$target.new');

    try {
      fresh.copySync(staged.path);
      if (!Platform.isWindows) {
        _run(
          'chmod',
          ['755', staged.path],
          missing:
              'chmod is not on PATH, so the new binary cannot be made '
              'executable',
        );
      }

      if (Platform.isWindows) {
        // Windows locks a running image, so the old one is renamed aside rather
        // than deleted; the leftover is swept on the next upgrade.
        final stale = File('$target.old');
        if (stale.existsSync()) {
          try {
            stale.deleteSync();
          } on FileSystemException {
            /* still held by a process that has not exited */
          }
        }
        var movedAside = false;
        if (executable.existsSync()) {
          try {
            executable.renameSync(stale.path);
            movedAside = true;
          } on FileSystemException catch (e) {
            throw UpgradeException(
              'cannot move $target aside — ${e.osError?.message ?? e.message}. '
              'Close anything running frx and try again; nothing was changed.',
            );
          }
        }
        try {
          staged.renameSync(target);
        } on FileSystemException catch (e) {
          // The old binary is already out of the way, so failing here would
          // otherwise leave the install directory with no frx at all and no
          // word about where it went. Put it back.
          if (movedAside) {
            try {
              stale.renameSync(target);
            } on FileSystemException {
              throw UpgradeException(
                'could not install the new binary, and could not put the old '
                'one back: it is at ${stale.path}. Rename it to $target.',
              );
            }
          }
          throw UpgradeException(
            'could not install the new binary — '
            '${e.osError?.message ?? e.message}. The old one is unchanged.',
          );
        }
        return;
      }

      staged.renameSync(target);
    } on UpgradeException {
      _discard(staged);
      rethrow;
    } on FileSystemException catch (e) {
      // A copy that ran out of disk leaves a truncated `frx.new` beside the
      // real binary — a half-written executable in the directory on PATH, which
      // outlives the run that made it and is one typo away from being run.
      _discard(staged);
      throw UpgradeException(
        'cannot write beside $target — ${e.osError?.message ?? e.message}. '
        'Install it somewhere you own, or re-run with the rights to replace it.',
      );
    }
  }

  /// Remove a staging file, best effort. Its absence is the desired state, so
  /// failing to reach it is not worth a second error on top of the first.
  static void _discard(File staged) {
    try {
      if (staged.existsSync()) staged.deleteSync();
    } on FileSystemException {
      /* nothing further to try, and the caller is already reporting a failure */
    }
  }
}
