/// Getting a release's binary onto the disk: download the archive, verify it
/// against the release's own `checksums.txt`, unpack it.
///
/// Everything here is about the bytes between github.com and a temp
/// directory; what happens to the binary afterwards is `executable_swap`'s,
/// and which release to fetch is the `Upgrader`'s.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'upgrade_exception.dart';

/// Runs [body] against a client that reads the wire the way `curl` does, and
/// reports a host it cannot reach through [unreachable] rather than a
/// `SocketException`.
///
/// `autoUncompress = false` is what makes this agree with `curl`. Dart
/// advertises `accept-encoding: gzip` and transparently inflates what comes
/// back; a server that sets `Content-Encoding: gzip` from the file extension —
/// a common misconfiguration for `.tar.gz` — therefore hands Dart the *inner*
/// tar while handing curl the archive, and every checksum fails as "tampered
/// with" against a mirror `install.sh` reads fine.
Future<T> withHttpClient<T>(
  Future<T> Function(HttpClient client) body, {
  required String Function(String reason) unreachable,
}) async {
  final client = HttpClient()..autoUncompress = false;
  try {
    return await body(client);
  } on SocketException catch (e) {
    throw UpgradeException(unreachable(e.message));
  } finally {
    client.close(force: true);
  }
}

/// The frx executable out of the release asset [asset] under [base], fetched,
/// verified and unpacked into [into].
///
/// Throws [UpgradeException] when the archive cannot be fetched, does not
/// match the release's checksum, or holds no executable.
Future<File> fetchReleaseBinary({
  required String base,
  required String asset,
  required Directory into,
}) async {
  final archive = File(p.join(into.path, asset));
  await _download('$base/$asset', archive);
  await _verify(archive, asset, base);
  _unpack(archive, into);

  final unpacked = File(
    p.join(into.path, Platform.isWindows ? 'frx.exe' : 'frx'),
  );
  if (!unpacked.existsSync()) {
    throw UpgradeException('$asset did not contain a frx executable');
  }
  return unpacked;
}

Future<void> _download(String url, File into) => withHttpClient(
  (client) async {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      throw UpgradeException(
        'could not download ${p.basename(into.path)} — HTTP '
        '${response.statusCode} from $url',
      );
    }
    final sink = into.openWrite();
    await response.pipe(sink);
  },
  unreachable: (reason) => 'could not download $url — $reason',
);

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
  final expected = line.split(_columns).first.toLowerCase();
  final actual = sha256.convert(archive.readAsBytesSync()).toString();
  if (actual != expected) {
    throw UpgradeException(
      'checksum mismatch for $asset — the download is corrupt or tampered '
      'with. Nothing was replaced.',
    );
  }
}

/// What separates the digest from the file name on a `checksums.txt` line.
final _columns = RegExp(r'\s+');

/// Unpack with the system `tar`.
///
/// bsdtar reads both formats and ships with macOS, every Linux worth naming
/// and Windows since 1803, so this costs no dependency. A missing `tar` is
/// reported rather than worked around: the alternative is a second archive
/// implementation to keep correct.
void _unpack(File archive, Directory into) {
  final result = runTool('tar', [
    if (Platform.isWindows) '-xf' else '-xzf',
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
