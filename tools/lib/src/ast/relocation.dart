import 'package:path/path.dart' as p;

import '../workspace/workspace_uri.dart';

/// Where files go in a rename, and what that does to the URIs naming them.
///
/// `rename` used to rewrite URIs by *token*: every `/`- or `.`-separated
/// segment spelling the old snake name became the new one. Renaming the
/// `connectivity` substate therefore also rewrote
/// `redux/services/connectivity/connectivity.dart` — a service folder the
/// rename never moved — and renaming `theme` pointed every `ui/lib/theme/…`
/// import at a folder that did not exist. A segment is not a file.
///
/// This asks the question a URI actually poses: which file does it name, and
/// does that file (or the one holding the directive) move? Only then is the
/// URI rewritten, and it is rewritten to the file's new place rather than by
/// substitution — so a moved file's relative imports stay right from where it
/// now stands, whatever depth that is.
class Relocation {
  const Relocation({required this.moveOf, this.packages = const {}});

  /// The path an absolute path will have after the rename, or null when it
  /// stays where it is.
  final String? Function(String path) moveOf;

  /// Package name → its absolute `lib/` directory, for `package:` URIs.
  final Map<String, String> packages;

  /// [uri], written in the file at [from], as it must read after the rename —
  /// or null when it reads the same.
  String? rewrite(String uri, {required String from}) {
    final target = workspaceTarget(uri, from: from, packages: packages);
    if (target == null) {
      return null;
    }

    if (uri.startsWith('package:')) {
      // The same package, or nothing: a move never changes which package a
      // file is in, and a URI that would have to is not this rule's to write.
      final name = uri.substring('package:'.length).split('/').first;
      final moved = moveOf(target);
      return moved == null
          ? null
          : packageUriOf(moved, {name: packages[name]!});
    }

    final newFrom = moveOf(from) ?? from;
    final newTarget = moveOf(target) ?? target;
    // Still naming the right file from where the directive now stands — the
    // common case for a moved file's import of something that stayed, when it
    // moved sideways. Kept byte for byte.
    if (p.equals(p.normalize(p.join(p.dirname(newFrom), uri)), newTarget)) {
      return null;
    }
    return uriPath(p.relative(newTarget, from: p.dirname(newFrom)));
  }
}
