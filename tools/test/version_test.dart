import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tools/src/version.dart';

/// `frx --version` says what was installed.
///
/// The constant and `pubspec.yaml` are two statements of one fact, and the
/// constant's own doc has said "keep in sync with `version:`" since it was
/// written — with nothing checking. That is the shape this repository has paid
/// for repeatedly: a rule stated in prose beside the thing it governs.
///
/// It matters more here than it looks. `dart install` takes the version from
/// the pubspec; `--version` prints the constant. When they part, the binary on
/// PATH reports a version it is not, and the only symptom is that a fix you
/// know you made is not in the tool you are running — which reads as the fix
/// being wrong.
///
/// A constant and not a read of the pubspec at runtime, because after `dart
/// install` the pubspec no longer sits beside the executable.
void main() {
  final toolsRoot = Directory.current.absolute.path;

  test('the version constant matches the pubspec', () {
    final pubspec = File(p.join(toolsRoot, 'pubspec.yaml')).readAsStringSync();
    final declared = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(declared, isNotNull, reason: 'no `version:` in tools/pubspec.yaml');
    expect(
      frxVersion,
      declared!.group(1),
      reason:
          'frxVersion and pubspec.yaml disagree, so `frx --version` reports '
          'something the installed binary is not. Change both, in '
          'lib/src/version.dart and pubspec.yaml.',
    );
  });

  test('the extension declares the same version', () {
    // A third statement of the same fact, and the one that reaches users who
    // never see this repository. The release ships both halves under one tag,
    // and the editor reads the CLI's contract out of generated constants — the
    // `--kind` sets, the doctor remedy ids — so a marketplace build paired with
    // an older binary offers kinds that binary rejects. The release workflow
    // refuses a tag the three disagree with; this catches the drift at the
    // commit that introduces it, which is where it is cheap to fix.
    final manifest = File(
      p.join(toolsRoot, 'vscode', 'package.json'),
    ).readAsStringSync();
    final declared = RegExp(
      r'^\s*"version"\s*:\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(manifest);

    expect(
      declared,
      isNotNull,
      reason: 'no `"version"` in vscode/package.json',
    );
    expect(
      declared!.group(1),
      frxVersion,
      reason:
          'the extension and the CLI ship on one tag, and their versions have '
          'parted. Change all three: tools/pubspec.yaml, '
          'tools/lib/src/version.dart and tools/vscode/package.json.',
    );
  });

  test('the version is a version', () {
    // Cheap, and it catches the paste that drops a digit or leaves a `^`.
    expect(
      RegExp(r'^\d+\.\d+\.\d+(?:[-+].+)?$').hasMatch(frxVersion),
      isTrue,
      reason: '"$frxVersion" is not a semantic version',
    );
  });
}
