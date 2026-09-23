import 'package:path/path.dart' as p;

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
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      final lib = slash <= 0 ? null : packages[rest.substring(0, slash)];
      if (lib == null) {
        return null;
      }

      final target = p.normalize(p.join(lib, rest.substring(slash + 1)));
      final moved = moveOf(target);
      if (moved == null || !p.isWithin(lib, moved)) {
        return null;
      }
      return 'package:${rest.substring(0, slash)}/'
          '${_posix(p.relative(moved, from: lib))}';
    }

    if (uri.contains(':')) {
      return null; // dart:, or a scheme frx does not move files in
    }

    final target = p.normalize(p.join(p.dirname(from), uri));
    final newFrom = moveOf(from) ?? from;
    final newTarget = moveOf(target) ?? target;
    // Still naming the right file from where the directive now stands — the
    // common case for a moved file's import of something that stayed, when it
    // moved sideways. Kept byte for byte.
    if (p.equals(p.normalize(p.join(p.dirname(newFrom), uri)), newTarget)) {
      return null;
    }
    return _posix(p.relative(newTarget, from: p.dirname(newFrom)));
  }

  /// A URI's path is `/`-separated whatever the platform's is.
  static String _posix(String path) => p.split(path).join('/');
}
