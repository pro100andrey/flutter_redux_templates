import 'dart:io';

import '../redux/app_state_source.dart';
import '../routing/routes_source.dart';
import '../util/casing.dart';
import 'page_artifact.dart';
import 'substate_artifact.dart';

/// Whether a name refers to a substate or a page.
enum ArtifactKind { substate, page }

/// The result of resolving a name to a [ArtifactKind]: either a [kind], or an
/// [error] message paired with the exit [code] the command should return.
class Resolution {
  const Resolution.resolved(this.kind) : error = null, code = 0;
  const Resolution.failure(this.error, this.code) : kind = null;

  final ArtifactKind? kind;
  final String? error;
  final int code;

  bool get ok => kind != null;
}

/// Locates the wiring sources and decides whether a name is a substate or a
/// page — the shared front half of `remove` and `rename`.
///
/// Each source is located independently (a repo missing one file can still
/// operate on the other kind); the sources are then exposed for the command's
/// own work while [resolve] answers the substate-vs-page question uniformly,
/// including the "matches both" (exit 64) and "nothing wired" (exit 70) cases.
class TargetResolver {
  const TargetResolver(this.appState, this.routes, {String? origin})
    : _origin = origin;

  final AppStateSource? appState;
  final RoutesSource? routes;

  /// The search origin (`--root` or the current directory) — surfaced in the
  /// "not inside a frx project" message.
  final String? _origin;

  /// Locates both wiring sources from [root] (or the current directory),
  /// tolerating a missing one (its `locate` throws [StateError] → null).
  ///
  /// The one place that still *walks* for these files rather than taking them
  /// from a resolved workspace, and it is asking a different question: not
  /// "where is this file inside the monorepo I have" but "is there a project of
  /// either kind above me". A reader that already holds a workspace uses
  /// `AppStateSource.of` / `RoutesSource.of`, which cannot answer with a file
  /// outside it.
  factory TargetResolver.locate(String? root) => TargetResolver(
    _tryLocate(() => AppStateSource.locate(startDir: root)),
    _tryLocate(() => RoutesSource.locate(startDir: root)),
    origin: root,
  );

  static T? _tryLocate<T>(T Function() locate) {
    try {
      return locate();
    } on StateError {
      return null;
    }
  }

  /// True when a substate field of this name (with a `…State` type, so
  /// framework fields like `wait` are excluded) is composed into `AppState`.
  bool isSubstate(Casing name) {
    final field = SubstateArtifact(name).field;
    return appState != null &&
        appState!.readSubstates().any((s) => s.field == field && s.isSubstate);
  }

  /// True when a route of this name is registered in `AppRouter`.
  bool isPage(Casing name) {
    final routeType = PageArtifact(name).routeType;
    return routes != null &&
        routes!.readRoutes().any((r) => r.routeType == routeType);
  }

  /// Resolves [name] to a kind. [forced] (`--kind`) overrides auto-detection;
  /// otherwise a name matching both kinds is ambiguous (exit 64) and a name
  /// matching neither is not wired (exit 70).
  Resolution resolve(Casing name, {String? forced}) {
    if (appState == null && routes == null) {
      return Resolution.failure(
        'Not inside a frx project — found neither app_state.dart nor '
        'app_router.dart walking up from ${_origin ?? Directory.current.path}.',
        70,
      );
    }
    if (forced != null) {
      return Resolution.resolved(ArtifactKind.values.byName(forced));
    }
    final substate = isSubstate(name);
    final page = isPage(name);
    if (substate && page) {
      return Resolution.failure(
        '"${name.pascal}" matches both a substate (${SubstateArtifact(name).field}) '
        'and a page (${PageArtifact(name).routeType}). '
        'Disambiguate with --kind substate|page.',
        64,
      );
    }
    if (substate) return const Resolution.resolved(ArtifactKind.substate);
    if (page) return const Resolution.resolved(ArtifactKind.page);
    return Resolution.failure(
      'Nothing named "${name.pascal}" is wired — no substate field '
      '"${SubstateArtifact(name).field}" in AppState and no route '
      '"${PageArtifact(name).routeType}" in AppRouter. '
      '(Pass --kind to act on an orphan by name.)',
      70,
    );
  }
}
