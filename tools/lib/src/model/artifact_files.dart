import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'artifact_name.dart';

/// Where an artifact of a **file-set kind** lives, derived once.
///
/// The kinds with a wiring story of their own already have a home for this:
/// `SubstateArtifact` and `PageArtifact` answer every question about a substate
/// or a page, paths included, because so many commands ask. The four here have
/// no wiring — `add-model`, `add-enum`, `add-service` and `add-retrofit` write
/// files and register nothing — so each one derived its own path inline, and
/// `RemovableResolver` derived the same path backwards to delete it.
///
/// **That the two agreed was a property of two expressions, not of one.** The
/// round-trip test held them together, which is the right guard and the wrong
/// place to *state* the convention: a test can only report a disagreement that
/// has already been written. Stating it once means there is nothing to disagree
/// about — the same move [ArtifactName] made for the suffix rules, which is
/// what the round trip caught the last time these two sides drifted.
///
/// Suffix-stripping is [ArtifactName]'s and stays there; this joins a stem to a
/// directory. A caller hands in the name as the user typed it.
abstract final class ArtifactFiles {
  /// `models/lib/<snake>.dart` — where `add-model` and `add-enum` both write.
  ///
  /// One method for two commands because it is one path: a freezed model and a
  /// plain enum are one file in one directory, and `remove --kind model` covers
  /// both for exactly that reason.
  static String model(FrxWorkspace repo, Casing name) =>
      p.join(repo.modelsLib.path, '${name.snake}.dart');

  /// The build_runner output beside a [model] — `<snake>.freezed.dart`,
  /// `<snake>.g.dart` — sorted, and only what is on disk.
  ///
  /// Part of the set rather than an afterthought of removal: left behind, a
  /// `part of 'task.dart'` whose source is gone stops the package compiling on
  /// a file the user never wrote.
  static List<String> modelGenerated(FrxWorkspace repo, Casing name) {
    final dir = repo.modelsLib;
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where(
          (path) =>
              FrxWorkspace.isGenerated(path) &&
              p.basename(path).startsWith('${name.snake}.'),
        )
        .toList()
      ..sort();
  }

  /// `business/lib/redux/services/<stem>/` — the folder holding both halves.
  ///
  /// The stem, not the typed name: `Sync` and `SyncService` are one artifact,
  /// and the add site stripping while the remove site did not is precisely the
  /// defect this concentration exists to make unwritable.
  static Directory serviceDir(FrxWorkspace repo, Casing name) => Directory(
    p.join(repo.businessServices.path, ArtifactName.serviceStem(name).snake),
  );

  /// The service and the dispatcher that holds the store, in write order.
  static ({String service, String dispatcher}) serviceFiles(
    FrxWorkspace repo,
    Casing name,
  ) {
    final stem = ArtifactName.serviceStem(name);
    final dir = serviceDir(repo, name).path;
    return (
      service: p.join(dir, '${stem.snake}.dart'),
      dispatcher: p.join(dir, '${stem.snake}_dispatcher.dart'),
    );
  }

  /// `http_client/lib/api/<snake>.dart`.
  ///
  /// No removal reads it — `remove` has no `retrofit` kind — and it is here
  /// anyway, because the reason the other three moved is that the path was
  /// stated at the add site, and a fourth one left behind is the next
  /// disagreement waiting for a second reader.
  static String retrofit(FrxWorkspace repo, Casing name) =>
      p.join(repo.httpApi.path, '${name.snake}.dart');
}
