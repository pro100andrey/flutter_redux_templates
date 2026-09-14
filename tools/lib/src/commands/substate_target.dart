import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/substate_artifact.dart';
import '../util/casing.dart';
import '../workspace/frx_workspace.dart';
import 'writing_command.dart';

/// A substate named on the command line, found by the file that makes it one.
///
/// `add-field` and `remove --kind field` both edit `<slice>_state.dart`, and
/// both answered a misspelled slice with the same sentence — written twice,
/// which is one more place than a sentence that names another command should
/// be in.
extension SubstateTarget on WritingCommand {
  /// The `--state` value, as the substate name it has to be.
  ///
  /// Parsed, not interpolated: `--state _shared` reached `Casing.parse` raw
  /// and threw a `FormatException` the runner does not map, so a bad flag
  /// value exited 255 with a stack trace where every other command exits 64
  /// with a sentence.
  Casing requireSubstate(String raw) {
    try {
      return Casing.parse(raw);
    } on FormatException catch (e) {
      usageException('Invalid --state "$raw": ${e.message}');
    }
  }

  /// The state file of [artifact] under [repo], or the refusal that says it is
  /// not there.
  ///
  /// Asked before anything reads the file. In `add-field` the `--force` check
  /// parses it, and it used to run first: `add-field <typo> x:int? --force`
  /// died with an unhandled `PathNotFoundException` and a stack trace, where
  /// the same typo without `--force` got the refusal two lines down. A guard
  /// that only holds for some flag combinations is not a guard.
  File requireStateFile(FrxWorkspace repo, SubstateArtifact artifact) {
    final stateFile = artifact.stateFile(repo.businessRedux);
    if (!stateFile.existsSync()) {
      refuse(
        'Substate "${artifact.name.snake}" has no '
        '${p.relative(stateFile.path)} — is the name right? '
        '(see `frx list-substates`).',
      );
    }
    return stateFile;
  }
}
