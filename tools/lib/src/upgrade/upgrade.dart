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

import 'package:path/path.dart' as p;

import 'executable_swap.dart';
import 'release_fetch.dart';
import 'upgrade_exception.dart';
import 'version_order.dart';

export 'upgrade_exception.dart' show UpgradeException;
export 'version_order.dart' show compareVersions;

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
    this._releasesUrl,
    this.repo = 'pro100andrey/flutter_redux_templates',
  }) : _downloadBase =
           downloadBase ?? Platform.environment['FRX_DOWNLOAD_BASE'];

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
    .macosArm64 => 'macos-arm64',
    .macosX64 => 'macos-x64',
    .linuxX64 => 'linux-x64',
    .linuxArm64 => 'linux-arm64',
    .windowsX64 => 'windows-x64',
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
  Future<String> latestVersion() {
    final url = Uri.parse(
      _releasesUrl ?? 'https://github.com/$repo/releases/latest',
    );
    return withHttpClient(
      (client) async {
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
        final match = _releaseTag.firstMatch(location);
        if (match == null) {
          throw UpgradeException(
            '$url redirected to "$location", which names no release tag — '
            'which is what a repository with no published release looks like.',
          );
        }
        return match.group(1)!;
      },
      unreachable: (reason) => 'could not reach github.com — $reason',
    );
  }

  /// The tag a release page's URL ends in, with or without its `v`.
  static final _releaseTag = RegExp(r'/tag/v?([^/]+?)/?$');

  /// The `v` a pinned version may be spelled with.
  static final _vPrefix = RegExp('^v');

  /// Check, and upgrade unless [check].
  Future<UpgradeResult> run({bool check = false, String? pinned}) async {
    if (!_isCompiledBinary) {
      return _refuse(
        'this frx is running through `dart run`, so there is no installed '
        'binary to replace. Install one first — see tools/README.md — or '
        'upgrade the checkout with git.',
      );
    }

    final slug = platformSlug;
    if (slug == null) {
      return _refuse(
        'no release is built for ${Abi.current()}. Build from source: '
        '`dart compile exe bin/frx.dart`.',
      );
    }

    final String target;
    final bool differs;
    if (pinned != null) {
      // A pin is an instruction, not a suggestion: naming a version is how you
      // go back to one, so it is installed whichever direction it points. Only
      // the resolved-latest path is a *comparison*.
      target = pinned.replaceFirst(_vPrefix, '');
      differs = target != currentVersion;
    } else {
      target = await latestVersion();
      // Ordered, not compared for inequality. `!=` called every difference an
      // upgrade, so a source build made after a version bump lands but before
      // its tag is published — the state this repository is in for most of a
      // release — was told to "upgrade" *backwards*, and `--check` exited 1 at
      // it, which is what a gating script acts on.
      differs = compareVersions(target, currentVersion) > 0;
    }

    if (!differs) {
      return _outcome(UpgradeStatus.current, to: target);
    }
    if (check) {
      return _outcome(UpgradeStatus.available, to: target);
    }
    await _install(target, slug);
    return _outcome(UpgradeStatus.upgraded, to: target);
  }

  UpgradeResult _refuse(String message) => UpgradeResult(
    UpgradeStatus.refused,
    from: currentVersion,
    message: message,
  );

  UpgradeResult _outcome(UpgradeStatus status, {required String to}) =>
      UpgradeResult(status, from: currentVersion, to: to);

  /// Download, verify, and put the new binary where the old one is.
  Future<void> _install(String version, String slug) async {
    final asset = 'frx-$version-$slug$_archiveExt';
    final base =
        _downloadBase ?? 'https://github.com/$repo/releases/download/v$version';

    final tmp = Directory.systemTemp.createTempSync('frx_upgrade_');
    try {
      final fresh = await fetchReleaseBinary(
        base: base,
        asset: asset,
        into: tmp,
      );
      replaceExecutable(executable, fresh: fresh);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }
}
