import 'dart:io';

import 'package:path/path.dart' as p;

/// The nearest directory at or above [start] holding [marker] — a path
/// relative to the directory, `pubspec.yaml` or `app/lib/navigation/…` — or
/// null when no ancestor up to the filesystem root does.
///
/// The one walk-up loop. The monorepo root, the package root a build_runner
/// run needs and the `.frxrc` a command reads its defaults from all climb the
/// same way; they differ only in what they look for and in what a miss means,
/// and each caller says that part for itself.
Directory? nearestAncestorWith(Directory start, String marker) {
  var dir = start;
  while (true) {
    if (File(p.join(dir.path, marker)).existsSync()) {
      return dir;
    }

    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}
