/// The data behind a use-case diagram: what a page's callbacks dispatch, and
/// what each of those actions does.
///
/// Everything here is read from the source AST (parse-only, no resolution), so
/// it is always true of the code as written — see `flow_reader.dart`.
library;

/// How an action was dispatched. Drives the arrow style in the diagram:
/// `dispatchAndWait` is a round-trip, the rest are fire-and-forget.
enum DispatchKind {
  dispatch,
  dispatchSync,
  dispatchAndWait,
  dispatchAll;

  static DispatchKind? parse(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// Whether the caller waits for a result (and can branch on the status).
  bool get isRoundTrip => this == DispatchKind.dispatchAndWait;
}

/// A single `dispatch*(...)` call.
class DispatchStep {
  const DispatchStep({
    required this.kind,
    required this.target,
    this.route,
    this.routeArgs,
    this.awaited = false,
    this.condition,
    this.trigger,
  });

  /// How it was dispatched.
  final DispatchKind kind;

  /// The dispatched action — a class name (`RegistrationAction`) or a factory
  /// call (`GoAction.push`).
  final String target;

  /// For a navigation dispatch, the destination route type (`LogInRoute`).
  final String? route;

  /// What was passed to it — `id: id`, `productId: connector.id, reviewId:
  /// reviewId` — or null when the route takes nothing.
  ///
  /// On a parameterised route this is the half worth reading: `ProductRoute`
  /// says where you land, and only this says which product.
  final String? routeArgs;

  /// Whether the call site awaited it.
  final bool awaited;

  /// The enclosing `if` condition, when this dispatch is guarded — rendered as
  /// an `alt` block (e.g. `status.isCompletedOk`).
  final String? condition;

  /// The inner callback this dispatch sits in, when the view-model field wraps
  /// one — e.g. `onChanged` for a `FieldVm`. Sharpens `email` into
  /// `email.onChanged` in the diagram.
  final String? trigger;

  /// True when this dispatch navigates rather than mutating state.
  bool get isNavigation => route != null || target.startsWith('GoAction');

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'target': target,
    if (route != null) 'route': route,
    if (routeArgs != null) 'routeArgs': routeArgs,
    'awaited': awaited,
    if (condition != null) 'condition': condition,
    if (trigger != null) 'trigger': trigger,
  };
}

/// One user-facing interaction: a view-model callback and what it dispatches.
class UseCase {
  const UseCase({required this.name, required this.steps});

  /// The `_Vm` field the widget calls, e.g. `onPressedRegister`.
  final String name;

  final List<DispatchStep> steps;

  /// How to name this interaction in a diagram: `email.onChanged` when every
  /// step came from the same inner callback, else just the field name.
  String get label {
    final trigger = steps.first.trigger;
    if (trigger == null) return name;
    return steps.every((s) => s.trigger == trigger) ? '$name.$trigger' : name;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'label': label,
    'steps': [for (final s in steps) s.toJson()],
  };
}

/// What one action does, read from its own file.
class ActionInfo {
  const ActionInfo({
    required this.className,
    this.mixins = const [],
    this.isAsync = false,
    this.writes,
    this.dispatches = const [],
    this.throwsUserException = false,
    this.file,
  });

  final String className;

  /// async_redux behaviour mixins (`WaitingAction`, `CheckInternet`, `Retry`…).
  final List<String> mixins;

  /// Whether `reduce()` is async (a round trip the diagram should show).
  final bool isAsync;

  /// The AppState field it writes, from `state.copyWith(<field>: …)`.
  final String? writes;

  /// Actions it dispatches itself (cascades).
  final List<DispatchStep> dispatches;

  final bool throwsUserException;

  /// Absolute path of the action file, for click-to-open in the viewer.
  final String? file;

  Map<String, Object?> toJson() => {
    'class': className,
    'mixins': mixins,
    'isAsync': isAsync,
    if (writes != null) 'writes': writes,
    'dispatches': [for (final d in dispatches) d.toJson()],
    'throwsUserException': throwsUserException,
    if (file != null) 'file': file,
  };
}

/// A page's whole flow: its interactions plus the actions they reach.
class PageFlow {
  const PageFlow({
    required this.page,
    required this.connectorClass,
    required this.pageClass,
    required this.useCases,
    required this.actions,
    this.connectorFile,
  });

  /// The page's base name, e.g. `registration`.
  final String page;

  final String connectorClass;
  final String pageClass;
  final List<UseCase> useCases;

  /// Every action reached from [useCases], by class name.
  final Map<String, ActionInfo> actions;

  final String? connectorFile;

  bool get isEmpty => useCases.isEmpty;

  Map<String, Object?> toJson() => {
    'page': page,
    'connectorClass': connectorClass,
    'pageClass': pageClass,
    if (connectorFile != null) 'connectorFile': connectorFile,
    'useCases': [for (final u in useCases) u.toJson()],
    'actions': {for (final e in actions.entries) e.key: e.value.toJson()},
  };
}
