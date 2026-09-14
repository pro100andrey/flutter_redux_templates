import '../redux/edit_outcome.dart';

/// The outcome of wiring a page into `AppRouter`.
class RouteWireResult implements EditOutcome {
  const RouteWireResult({
    required this.source,
    required this.changes,
    required this.alreadyWired,
    this.warnings = const [],
  });

  /// The same route was already registered — [source] is the file as it
  /// stands, and nothing was changed.
  const RouteWireResult.wired(this.source)
    : changes = const [],
      alreadyWired = true,
      warnings = const [];

  /// The full, edited `app_router.dart` source (unchanged if [alreadyWired]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when the same route was already registered — nothing was changed.
  final bool alreadyWired;

  @override
  bool get unchanged => alreadyWired;

  /// Non-fatal problems the caller should surface (e.g. `--public` requested
  /// but the guard's `_authArea` set could not be located).
  final List<String> warnings;
}

/// The outcome of unwiring a page from `AppRouter`.
class RouteUnwireResult with Unwiring {
  const RouteUnwireResult({
    required this.source,
    required this.changes,
    required this.found,
    this.warnings = const [],
  });

  /// No route of that type was registered — [source] is the file as it
  /// stands.
  const RouteUnwireResult.absent(this.source)
    : changes = const [],
      found = false,
      warnings = const [];

  /// The full, edited `app_router.dart` source (unchanged when not [found]).
  @override
  final String source;

  /// Human-readable descriptions of the edits made.
  @override
  final List<String> changes;

  /// True when a route of the given type was registered and was removed.
  @override
  final bool found;

  /// Non-fatal problems the caller should surface (e.g. a removed tab shell
  /// whose child pages were left in place).
  final List<String> warnings;
}
