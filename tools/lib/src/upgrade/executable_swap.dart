/// Putting a new binary where the running one is, without ever leaving the
/// path empty and without ever writing through a running image.
library;

import 'dart:io';

import 'upgrade_exception.dart';

/// Put [fresh] where [executable] is, without ever leaving the path empty.
///
/// Rename, not copy-over-in-place: an in-place write to a running executable
/// is a corrupt process on POSIX and simply refused on Windows. Renaming
/// swaps the directory entry, so anything already running keeps the old inode
/// and finishes normally.
void replaceExecutable(File executable, {required File fresh}) {
  final target = executable.path;
  final staged = File('$target.new');

  try {
    fresh.copySync(staged.path);
    if (!Platform.isWindows) {
      runTool(
        'chmod',
        ['755', staged.path],
        missing:
            'chmod is not on PATH, so the new binary cannot be made '
            'executable',
      );
    }

    if (Platform.isWindows) {
      _swapOnWindows(executable, staged);
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
      'cannot write beside $target — ${_reason(e)}. '
      'Install it somewhere you own, or re-run with the rights to replace '
      'it.',
    );
  }
}

/// Windows locks a running image, so the old one is renamed aside rather
/// than deleted; the leftover is swept on the next upgrade.
void _swapOnWindows(File executable, File staged) {
  final target = executable.path;
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
        'cannot move $target aside — ${_reason(e)}. '
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
      '${_reason(e)}. The old one is unchanged.',
    );
  }
}

/// The OS's own words for what went wrong, falling back to Dart's.
String _reason(FileSystemException e) => e.osError?.message ?? e.message;

/// Remove a staging file, best effort. Its absence is the desired state, so
/// failing to reach it is not worth a second error on top of the first.
void _discard(File staged) {
  try {
    if (staged.existsSync()) {
      staged.deleteSync();
    }
  } on FileSystemException {
    // Nothing further to try, and the caller is already reporting a
    // failure.
  }
}
