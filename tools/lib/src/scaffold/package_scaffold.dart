/// Everything that makes `<kind>/` a resolved workspace member — and unmakes
/// it.
///
/// The catalogue of kinds is [PackageKind]; the pubspec splices are
/// `pubspec_edit.dart`. Both are re-exported here, because a caller that
/// creates a package needs the kind to name it and a test that checks the
/// splices reaches them through the command that applies them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/changeset.dart';
import '../workspace/frx_workspace.dart';
import 'package_kind.dart';
import 'pubspec_edit.dart';

export 'package_kind.dart';
export 'pubspec_edit.dart';

/// The changes that createPackage [kind] in [repo], or none when it is already
/// there.
///
/// Returned as a list so a caller can splice it ahead of its own writes in
/// one [Changeset] — which is the point. Creating a package is five changes
/// across two directories, and four of them alone leave a workspace that does
/// not resolve; the shared applier makes the whole set atomic, so there is no
/// half-created package to clean up by hand.
List<Change> createPackage(FrxWorkspace repo, PackageKind kind) {
  if (kind.existsIn(repo)) {
    return const [];
  }

  final dir = p.join(repo.root.path, kind.dir);
  final root = p.join(repo.root.path, 'pubspec.yaml');
  final rootBefore = File(root).readAsStringSync();

  return [
    WriteFile(p.join(dir, 'pubspec.yaml'), kind.pubspec(repo)),
    WriteFile(p.join(dir, 'analysis_options.yaml'), kind.analysisOptions),
    if (kind.build case final build?)
      WriteFile(p.join(dir, 'build.yaml'), build),
    WriteFile(p.join(dir, '.gitignore'), PackageKind.gitignore),
    // `.gitkeep` and not a starter source file: what goes in `lib/` is the
    // next command's business, and a placeholder Dart file would be one more
    // thing to delete.
    WriteFile(p.join(dir, 'lib', '.gitkeep'), ''),
    EditFile(
      root,
      before: rootBefore,
      after: addToWorkspaceList(rootBefore, kind.dir),
    ),
    // A member nobody may depend on is a directory `pub get` resolves and no
    // `import` can reach. This used to be the user's to write, and the skill
    // said so; what it could not say is which pubspec — the answer is on the
    // kind.
    ..._declarations(repo, kind),
  ];
}

/// The changes that unmake [kind] a member of the tree at [root]: every
/// declaration of it, its `workspace:` entry, and the directory. None when it
/// is not there.
///
/// The inverse of [createPackage], and what `frx createPackage --without`
/// applies. Kept beside it rather than in the command, because the pair is the
/// point: an omission that forgot a declaration would leave a pubspec pointing
/// at `../models` and a project that does not resolve.
List<Change> omitPackage(String root, PackageKind kind) {
  final dir = p.join(root, kind.dir);
  if (!Directory(dir).existsSync()) {
    return const [];
  }

  final rootPubspec = p.join(root, 'pubspec.yaml');
  final before = File(rootPubspec).readAsStringSync();

  return [
    ..._withdrawals(root, kind),
    EditFile(
      rootPubspec,
      before: before,
      after: removeFromWorkspaceList(before, kind.dir),
    ),
    // Last, so an edit to a pubspec *inside* another omitted package (only
    // `http_client`, which declares `models`) is not written back into a
    // directory a delete has already taken away. Omissions are applied one
    // kind at a time for the same reason.
    DeleteDirectory(dir),
  ];
}

/// The pubspec edits that declare [kind] where the template declares it, plus
/// the ones the new package itself owes.
///
/// Both directions of [PackageKind.dependents], because a package is on both
/// ends of that relation: creating `http_client` has to declare it in
/// `business`, *and* declare `models` inside `http_client`. Reading only the
/// first direction is what left a re-added `http_client` unable to import the
/// models `add-retrofit` writes against — and `models` had to be re-added
/// first for it to happen, which is why the round trip did not catch it.
///
/// Skips a dependent that is not there: `models` is declared by
/// `http_client`, which is itself optional, so "who depends on this" and
/// "who is present" are two questions and only the first is a fixed fact.
List<Change> _declarations(FrxWorkspace repo, PackageKind kind) => [
  for (final dependent in kind.dependents)
    ?_pubspecEdit(
      File(p.join(repo.root.path, dependent, 'pubspec.yaml')),
      (source) => addPathDependency(source, kind.dir),
    ),
];

/// Every pubspec under [root] that declares [kind], with the declaration
/// gone.
///
/// **Found rather than looked up.** [PackageKind.dependents] is what
/// [createPackage] declares, because it has nothing to read; an omission has
/// the tree in front of it, and a declaration it failed to withdraw is a
/// pubspec pointing at a directory that is no longer there — `pub get` fails
/// and the project cannot be opened. Deriving it means the guard holds for a
/// workspace whose members this catalogue never heard of; that the two agree
/// for the template is a test rather than an assumption.
List<Change> _withdrawals(String root, PackageKind kind) => [
  for (final entity in Directory(root).listSync())
    if (entity is Directory && p.basename(entity.path) != kind.dir)
      ?_pubspecEdit(
        File(p.join(entity.path, 'pubspec.yaml')),
        (source) => removePathDependency(source, kind.dir),
      ),
];

/// The edit [change] makes to the pubspec at [file], or null when there is
/// no such file or the change comes back a no-op — the two "nothing to do"
/// cases a declaration and a withdrawal share.
EditFile? _pubspecEdit(File file, String Function(String source) change) {
  if (!file.existsSync()) {
    return null;
  }
  final before = file.readAsStringSync();
  final after = change(before);
  return after == before
      ? null
      : EditFile(file.path, before: before, after: after);
}

/// For each package in [omitted], the Dart files in [files] — an archive or a
/// tree, keyed by `/`-separated relative path — that import it.
///
/// **The safety rule of leaving a package out**, and derived rather than
/// declared: a package can go when nothing outside it names it. `storage` is
/// optional in the same sense `models` is — its own pubspec, its own
/// `add-package` — and `business` imports it in four places, so dropping it
/// produces a project that does not compile. A list of what may be dropped
/// would be a second copy of that fact and would go stale the first time
/// somebody wires `http_client` up.
///
/// **A package being omitted is not an importer**, however much it imports.
/// `http_client` declares `models` and `add-retrofit` writes
/// `package:models/…` into it; counting that would refuse
/// `--without models,http_client` — the combination the option exists for —
/// naming files inside a directory the same run is deleting.
///
/// Bytes rather than strings, and content rather than a parse: the planned
/// shape this used to read carries no content at all for an entry mold copies
/// verbatim, so a Dart file in that class was invisible to the one check
/// standing between `--without` and a project that does not compile.
Map<PackageKind, List<String>> packageImportersOf(
  Map<String, List<int>> files,
  List<PackageKind> omitted,
) {
  if (omitted.isEmpty) {
    return const {};
  }

  // The needles once, not once per file: the archive is the whole template.
  final insideOmitted = [for (final kind in omitted) '${kind.dir}/'];
  final imports = {for (final kind in omitted) kind: 'package:${kind.dir}/'};

  final found = {for (final kind in omitted) kind: <String>[]};
  for (final MapEntry(key: path, value: bytes) in files.entries) {
    if (!path.endsWith('.dart') || insideOmitted.any(path.startsWith)) {
      continue;
    }

    // Malformed input is replaced rather than thrown on: a file that does not
    // decode is not one an import can be read out of, and the audit is what
    // reports it.
    final source = utf8.decode(bytes, allowMalformed: true);
    for (final MapEntry(key: kind, value: import) in imports.entries) {
      if (source.contains(import)) {
        found[kind]!.add(path);
      }
    }
  }

  for (final importers in found.values) {
    importers.sort();
  }
  return found..removeWhere((_, importers) => importers.isEmpty);
}

/// Whether the relative [path] sits under the package directory [dir].
/// Archive paths are `/`-separated whatever the host is.
bool isUnderPackageDir(String dir, String path) => path.startsWith('$dir/');
