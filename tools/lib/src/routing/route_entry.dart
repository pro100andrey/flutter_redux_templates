/// One route registered in `AppRouter.routes`.
class RouteEntry {
  const RouteEntry({
    required this.routeType,
    required this.path,
    this._fullPath,
    this.initial = false,
    this.parent,
  });

  /// The generated route class referenced as `<Type>.page`, e.g. `HomeRoute`.
  final String routeType;

  /// The path exactly as the `AutoRoute` spells it — `/home`, or the relative
  /// `profile` of a tab child (null if the `AutoRoute` omits `path:`).
  ///
  /// The source fact. To show a user where a route lives, use [fullPath]: a
  /// child's own path is not an address anyone can navigate to.
  final String? path;

  final String? _fullPath;

  /// The path the router actually serves, with a tab child's path joined onto
  /// its shell's — `/account/profile`, not `profile`.
  ///
  /// auto_route treats a child path as relative unless it starts with `/`, so
  /// printing [path] for a nested route states an address that does not exist.
  String? get fullPath => _fullPath ?? path;

  /// Whether the `AutoRoute` carries `initial: true` — the app's entry screen.
  final bool initial;

  /// The shell route this one is nested under (`children:` of a tab shell), or
  /// null for a top-level route.
  final String? parent;
}
