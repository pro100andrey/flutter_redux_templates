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
  dispatchAll,

  /// async_redux's `dispatchAndWaitAll([...])`. Missing here, the call was
  /// not a dispatch at all, and every action in its list read as reached by
  /// nobody.
  dispatchAndWaitAll;

  /// The kind called [name], or null for a method that is not a dispatch.
  ///
  /// Asked of every method invocation the dispatch visitor meets, so it is a
  /// lookup rather than a scan of [values].
  static DispatchKind? parse(String name) => _byName[name];

  static final Map<String, DispatchKind> _byName = {
    for (final k in values) k.name: k,
  };

  /// Whether the caller waits for a result (and can branch on the status).
  bool get isRoundTrip =>
      this == DispatchKind.dispatchAndWait ||
      this == DispatchKind.dispatchAndWaitAll;

  /// Whether the call takes a list of actions rather than one.
  bool get takesList =>
      this == DispatchKind.dispatchAll ||
      this == DispatchKind.dispatchAndWaitAll;
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
    this.opaque = false,
  });

  /// How it was dispatched.
  final DispatchKind kind;

  /// The dispatched action — a class name (`RegistrationAction`) or a factory
  /// call (`GoAction.push`).
  final String target;

  /// For a navigation dispatch, the destination route type (`LogInRoute`).
  final String? route;

  /// What was passed to it — `id: id`,
  /// `productId: connector.id, reviewId: reviewId` — or null when the route
  /// takes nothing.
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

  /// True when the dispatched expression is a value rather than a
  /// construction — a parameter, a field, a call's result — so no class can
  /// be read off it, and [target] is only the expression's source.
  ///
  /// Said rather than guessed at: read as a class name, `dispatch(action)`
  /// was a dispatch of a class called `action`, which the graph either
  /// invented a node for or dropped. Either way the action really dispatched
  /// read as reached by nobody. A step marked opaque is a blind spot, and
  /// the graph declares it as one.
  final bool opaque;

  /// True when this dispatch navigates rather than mutating state.
  bool get isNavigation => route != null || target.startsWith('GoAction');

  /// The class the dispatched expression constructs — [target] up to its
  /// first `.`, so `RefreshConsoleAction.forOperator(…)` names
  /// `RefreshConsoleAction`.
  ///
  /// [target] keeps the spelling the source has, because a diagram should say
  /// which constructor was called. But a named constructor or a static factory
  /// still makes an instance of the class in front of it, and it is the class
  /// that has a file and a node: looked up by the full spelling, every
  /// `X.named()` was a dispatch of something frx could not find.
  String get className {
    final dot = target.indexOf('.');
    return dot < 0 ? target : target.substring(0, dot);
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'target': target,
    if (route != null) 'route': route,
    if (routeArgs != null) 'routeArgs': routeArgs,
    'awaited': awaited,
    if (condition != null) 'condition': condition,
    if (trigger != null) 'trigger': trigger,
    if (opaque) 'opaque': true,
  };
}

/// One user-facing interaction: a view-model callback and what it dispatches.
class UseCase {
  const UseCase({required this.name, required this.steps, this.owner});

  /// The `_Vm` field the widget calls, e.g. `onPressedRegister`.
  final String name;

  final List<DispatchStep> steps;

  /// The connector that declares it, when that is not the page's own.
  ///
  /// Null for a use case on the route connector itself, which is every use case
  /// on a page that connects to the store in one place. A page composed of
  /// regions has one per region instead, and saying which is the whole value: a
  /// diagram that attributed sixteen interactions to a connector holding no
  /// view-model would be a tidier drawing of something untrue.
  final String? owner;

  /// How to name this interaction in a diagram: `email.onChanged` when every
  /// step came from the same inner callback, else just the field name.
  String get label {
    final trigger = steps.first.trigger;
    if (trigger == null) {
      return name;
    }
    return steps.every((s) => s.trigger == trigger) ? '$name.$trigger' : name;
  }

  /// [label] with the region in front of it, where there is one.
  ///
  /// The lane already says which connector handles the call, but the line above
  /// it says what the *user* did — and a composed screen has eight regions with
  /// an `onOpen` each. Three identical `onOpen` rows, distinguishable only by
  /// which lane the next arrow lands in, is a smaller version of the problem
  /// this traversal exists to fix.
  ///
  /// The `Connector` suffix is dropped: the reader is looking at a screen, not
  /// at a class list, and `ActiveFront ▸ onOpen` reads as a place on it.
  String get qualifiedLabel {
    final owner = this.owner;
    if (owner == null) {
      return label;
    }
    final region = owner.endsWith('Connector')
        ? owner.substring(0, owner.length - 'Connector'.length)
        : owner;
    return '$region ▸ $label';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'label': label,
    if (owner != null) 'owner': owner,
    'steps': [for (final s in steps) s.toJson()],
  };
}

/// A place in `AppState`: a substate, and the field inside it when the
/// reference names one.
///
/// `field` is null when the whole substate is meant — the flat write
/// `state.copyWith(logIn: …)` replaces it, and `state.logIn` handed to a
/// function reads all of it.
typedef StateField = ({String substate, String? field});

/// One `copyWith` target.
typedef StateWrite = StateField;

/// One `state.<substate>.<field>` read.
typedef StateRead = StateField;

extension StateFieldLabel on StateField {
  /// `logIn.email`, or just `logIn` for the whole substate.
  String get label => field == null ? substate : '$substate.$field';
}

/// What one action does, read from its own file.
class ActionInfo {
  const ActionInfo({
    required this.className,
    this.mixins = const [],
    this.isAsync = false,
    this.writes = const [],
    this.dispatches = const [],
    this.throwsUserException = false,
    this.file,
    this.declaresClass = true,
    this.line,
    this.column,
  });

  final String className;

  /// Where in [file] the class is declared, 1-based, when the reader had the
  /// tree to say. Not part of the JSON: a file holding one action opens at the
  /// top, and only the graph — where a file may hold several — needs to point
  /// at the right one.
  final int? line;
  final int? column;

  /// Whether the file actually declared a class, or [className] is the file
  /// name standing in for one.
  ///
  /// A file under `actions/` need not hold an action: this template's own
  /// pattern is a `mixin … on Action` carrying a shared `reduce()`, and one of
  /// those was reported as an artifact nothing reaches — a mixin is never
  /// dispatched, so the finding could only ever be false. Consumers that build
  /// nodes skip a file where this is false.
  final bool declaresClass;

  /// async_redux behaviour mixins (`WaitingAction`, `CheckInternet`, `Retry`…).
  final List<String> mixins;

  /// Whether `reduce()` is async (a round trip the diagram should show).
  final bool isAsync;

  /// The AppState fields it writes, from `state.copyWith(<field>: …)`.
  ///
  /// **Structured, because it has two readers.** This was a `String?` that
  /// `_qualify` built by joining `'<substate>.<field>'` with `', '`, and
  /// `graph_reader` split it back apart on the same separator to raise one edge
  /// per substate touched. A *rendering* choice was the only channel between
  /// two readers of one fact: change the separator, or a field name containing
  /// one, and the graph silently loses its write edges with nothing failing.
  ///
  /// [writesLabel] keeps the string, so the JSON and the diagrams say exactly
  /// what they always did.
  final List<StateWrite> writes;

  /// `logIn.email, logIn.password` — the display form, and the only form the
  /// `--json` contract and the mermaid renderers ever wanted.
  String? get writesLabel =>
      writes.isEmpty ? null : writes.map((w) => w.label).join(', ');

  /// Actions it dispatches itself (cascades).
  final List<DispatchStep> dispatches;

  final bool throwsUserException;

  /// Absolute path of the action file, for click-to-open in the viewer.
  final String? file;

  Map<String, Object?> toJson() => {
    'class': className,
    'mixins': mixins,
    'isAsync': isAsync,
    'writes': ?writesLabel,
    'dispatches': [for (final d in dispatches) d.toJson()],
    'throwsUserException': throwsUserException,
    if (file != null) 'file': file,
  };
}

/// A connector whose file dispatches more than the walk could attribute to a
/// use case.
///
/// The whole value of this type is that it is *said*. Whatever the reader
/// follows, something will eventually be written in a shape it does not — and
/// the failure mode is not a wrong diagram but a plausible one: a region with
/// no use case gets no lane and leaves the drawing entirely, so a map missing
/// six of eleven regions reads exactly like the map of a page that has five. An
/// empty file is obvious; a quietly shortened map is not.
///
/// So the arithmetic is deliberately crude. Count every `dispatch*(` in the
/// file, subtract the ones that reached a use case, and report the remainder
/// without claiming to know what it is. A number that is too high costs a line
/// of output; a number that is silently zero costs what this type exists for.
class UntracedDispatch {
  const UntracedDispatch({required this.connectorClass, required this.count});

  /// The connector whose file holds them — a region, or the route connector.
  final String connectorClass;

  /// How many dispatch call sites in that file no use case accounts for.
  final int count;

  /// `1 dispatch` / `3 dispatches` — one spelling for the three renderers, so
  /// the diagram, the exported doc and the terminal cannot disagree about it.
  String get calls => count == 1 ? '1 dispatch' : '$count dispatches';

  Map<String, Object?> toJson() => {
    'connectorClass': connectorClass,
    'count': count,
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
    this.regions = const [],
    this.regionFiles = const {},
    this.untraced = const [],
  });

  /// The page's base name, e.g. `registration`.
  final String page;

  final String connectorClass;
  final String pageClass;
  final List<UseCase> useCases;

  /// Every action reached from [useCases], by class name.
  final Map<String, ActionInfo> actions;

  final String? connectorFile;

  /// The nested connectors this page is composed of, in the order they are
  /// reached, excluding the route connector itself.
  ///
  /// A page that connects to the store in one place has none. A page that hands
  /// its slots to region connectors has one entry per region actually reached —
  /// which is what a reader needs to tell "this page dispatches nothing" from
  /// "the frame dispatches nothing and its six regions do".
  final List<String> regions;

  /// The file each of [regions] was read from, by class name.
  ///
  /// So a reader attributing a use case can name the file that holds it: a
  /// use case carries its region's class in [UseCase.owner], and a gap in one
  /// region was reported against the page's own file — where the dispatch is
  /// not — for want of this.
  final Map<String, String> regionFiles;

  /// Connectors that dispatch more than this flow accounts for.
  ///
  /// Empty is the ordinary case and means what it says: everything the files
  /// dispatch is drawn. A non-empty entry is the map admitting a gap in itself
  /// — see [UntracedDispatch].
  final List<UntracedDispatch> untraced;

  bool get isEmpty => useCases.isEmpty;

  Map<String, Object?> toJson() => {
    'page': page,
    'connectorClass': connectorClass,
    'pageClass': pageClass,
    if (connectorFile != null) 'connectorFile': connectorFile,
    if (regions.isNotEmpty) 'regions': regions,
    'useCases': [for (final u in useCases) u.toJson()],
    'actions': {for (final e in actions.entries) e.key: e.value.toJson()},
    if (untraced.isNotEmpty) 'untraced': [for (final u in untraced) u.toJson()],
  };
}
