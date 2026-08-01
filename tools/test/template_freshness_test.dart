import 'dart:convert';
import 'dart:io';

import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/template/template.g.dart';

/// The embedded template must be the repository it was packed from.
///
/// `frx create` unpacks an archive frozen into `lib/src/template/template.g.dart`,
/// so every change to the monorepo leaves that archive one commit behind until it
/// is repacked. This is the same guard `frx doctor` puts on `docs/flows/`: a
/// derived artifact is only trustworthy if something fails when it drifts.
///
/// **It lives in a test rather than in `doctor` on purpose.** The audit runs on
/// every debounced file event in the editor, and this check has to read and gzip
/// the whole repository — a cost that belongs to CI, not to typing.
///
/// **Compared by content, not by bytes.** Two packs of an identical tree do not
/// produce identical archives: gzip framing and tar headers carry timestamps. So
/// the archives are decoded and their `files` maps compared, which is the claim
/// that actually matters — that the captured *content* is current.
void main() {
  test('the embedded template matches the repository', () async {
    final repoRoot = p.dirname(Directory.current.absolute.path);
    final manifest = Manifest.fromFile(p.join(repoRoot, 'mold.yaml'));

    final fresh = const ArchiveReader().read(
      await const Bundler().bundle(projectDir: repoRoot, manifest: manifest),
    );
    final embedded = const ArchiveReader().read(
      base64Decode(kFrxTemplateBase64),
    );

    const repack = 'Repack it: cd tools && make template';

    // Named before compared, so a failure says *which* file rather than "some
    // 963 KB of bytes differ".
    final added = fresh.files.keys.toSet().difference(
      embedded.files.keys.toSet(),
    );
    final gone = embedded.files.keys.toSet().difference(
      fresh.files.keys.toSet(),
    );
    expect(
      added,
      isEmpty,
      reason: 'files the template has not captured yet. $repack',
    );
    expect(gone, isEmpty, reason: 'files the template still carries. $repack');

    final changed = [
      for (final entry in fresh.files.entries)
        if (!_sameBytes(entry.value, embedded.files[entry.key]!)) entry.key,
    ]..sort();
    expect(
      changed,
      isEmpty,
      reason: 'files whose content has moved on. $repack',
    );
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
