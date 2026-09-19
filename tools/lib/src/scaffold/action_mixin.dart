/// What frx knows about a generated action's shape: the body [ActionKind]
/// picks, and the async_redux behaviour mixins `add-action --mixin` can attach
/// — with the facts about them (implications, exclusions, hook overrides) that
/// the template, the CLI's help, the editor and the audit all read from here.
library;

/// The body shape for a generated action.
enum ActionKind {
  sync,
  async,
  waiting;

  static ActionKind parse(String v) =>
      ActionKind.values.byName(v.toLowerCase());
}

/// async_redux behaviour mixins `add-action --mixin` can attach.
///
/// [clause] is the mixin name as it appears in the `with` clause (typed with
/// `<AppState>` by the template); [implies] is a mixin that must precede this
/// one (`NoDialog on CheckInternet`, `UnlimitedRetries on Retry`);
/// [overrideBlock] surfaces the tuning override worth editing right away.
enum ActionMixin {
  /// Check connectivity in `before()`; show the error dialog when offline.
  checkInternet(
    'CheckInternet',
    'Check connectivity first; error dialog when offline',
    hooks: {'before'},
  ),

  /// With [checkInternet]: mark the error dialog-less (`ifOpenDialog: false`).
  noDialog(
    'NoDialog',
    'With checkInternet: fail without the dialog',
    implies: checkInternet,
  ),

  /// Abort silently when offline (no dialog, no error).
  abortWhenNoInternet(
    'AbortWhenNoInternet',
    'Abort silently when offline',
    hooks: {'before'},
  ),

  /// Ignore a dispatch while the same action is already running.
  nonReentrant(
    'NonReentrant',
    'Ignore a dispatch while already running',
    hooks: {'after'},
    knobs: {'nonReentrantKeyParams'},
    overrideBlock:
        '  // One lock per action type: LoadX(a) is ignored while LoadX(b) is\n'
        '  // running. Override to let each instance run on its own:\n'
        '  // Object? nonReentrantKeyParams() => someId;\n\n',
  ),

  /// Retry a failing `reduce()` with exponential backoff.
  retry(
    'Retry',
    'Retry failures with exponential backoff',
    knobs: {'maxRetries', 'initialDelay', 'multiplier', 'maxDelay'},
    overrideBlock:
        '  // TODO(frx): tune the backoff — also initialDelay (350ms),\n'
        '  // multiplier (2) and maxDelay (5s).\n'
        '  @override\n'
        '  int get maxRetries => 3;\n\n',
  ),

  /// With [retry]: keep retrying forever.
  unlimitedRetries(
    'UnlimitedRetries',
    'With retry: never stop retrying',
    implies: retry,
  ),

  /// Wait for a pause in dispatches before running (search-as-you-type).
  debounce(
    'Debounce',
    'Run only after a pause in dispatches',
    knobs: {'debounce', 'lockBuilder'},
    overrideBlock:
        '  // TODO(frx): tune the pause that must elapse before the action runs.\n'
        '  @override\n'
        '  int get debounce => 300; // milliseconds\n\n'
        '  // One lock per action type. Override lockBuilder() to give each\n  // instance its own: Object? lockBuilder() => someId;\n\n',
  ),

  /// Drop dispatches while a recent run is still fresh.
  throttle(
    'Throttle',
    'Drop dispatches while a recent run is fresh',
    hooks: {'after'},
    knobs: {'throttle', 'lockBuilder'},
    overrideBlock:
        '  // TODO(frx): tune how long a run stays fresh (dispatches are dropped).\n'
        '  @override\n'
        '  int get throttle => 1000; // milliseconds\n\n'
        '  // One lock per action type. Override lockBuilder() to give each\n  // instance its own: Object? lockBuilder() => someId;\n\n',
  ),

  /// Skip the run entirely while the last result is still considered fresh.
  fresh(
    'Fresh',
    'Skip the run while the last result is still fresh',
    // Milliseconds, like `debounce` and `throttle` — async_redux declares
    // `int get freshFor => 1000; // Milliseconds`. This used to emit
    // `60; // seconds`, so a scaffolded action stayed fresh for 60ms while its
    // own comment promised a minute, and `Fresh` silently did nothing.
    hooks: {'after'},
    knobs: {'freshFor', 'freshKeyParams'},
    overrideBlock:
        '  // TODO(frx): tune how long the last result stays fresh.\n'
        '  @override\n'
        '  int get freshFor => 60000; // milliseconds (1 minute)\n\n'
        '  // The fresh-key is the action TYPE, so LoadX(a) and LoadX(b) share\n'
        '  // one window and the second is skipped. Override to split them:\n'
        '  // Object? freshKeyParams() => someId;\n\n',
  ),

  /// Run one at a time, in dispatch order — a FIFO queue, shared by every
  /// `Sequential` action unless the key says otherwise.
  sequential(
    'Sequential',
    'Run one at a time, in dispatch order (a queue per key)',
    hooks: {'before', 'after'},
    knobs: {'sequentialKeyParams', 'discardQueueOnError'},
    overrideBlock:
        '  // One queue for every Sequential action: they run in dispatch order,\n'
        '  // one at a time, whatever their type. Override to queue per key:\n'
        '  // Object? sequentialKeyParams() => someId;\n\n'
        '  // Whether a failure aborts what is queued behind it (default: no).\n'
        '  // Do not `await dispatchAndWait` another action of the same queue\n'
        '  // from here — it would wait for its own turn, forever.\n'
        '  // bool discardQueueOnError(Object error) => true;\n\n',
  ),

  /// Retry forever, treating "offline" as just another failure to retry —
  /// a single mixin replacing [checkInternet] + [retry] + [unlimitedRetries].
  unlimitedRetryCheckInternet(
    'UnlimitedRetryCheckInternet',
    'Retry forever, treating offline as a failure to retry',
    knobs: {'initialDelay', 'multiplier', 'maxDelay', 'maxDelayNoInternet'},
    overrideBlock:
        '  // TODO(frx): tune initialDelay / multiplier / maxDelay / maxDelayNoInternet.\n',
  );

  const ActionMixin(
    this.clause,
    this.summary, {
    this.implies,
    this.overrideBlock = '',
    this.knobs = const {},
    // Given by no entry since async_redux 28.3.1 — see the field. Kept for
    // the next mixin that does not chain, which is a one-word change here
    // rather than the parameter, the field, the audit and `list-mixins` back.
    // ignore: unused_element_parameter
    this.swallowsAfter = false,
    this.hooks = const {},
  });

  /// The identifier used in the generated `with` clause.
  final String clause;

  /// One line on what it does, for a picker or `--help`.
  ///
  /// Here rather than in each consumer: the CLI's `allowedHelp`, the editor's
  /// multi-select and the wizard all showed their own hand-typed copy, and two
  /// of the three had drifted to eight of the ten mixins.
  final String summary;

  /// A mixin this one is declared `on` — must be present and precede it.
  final ActionMixin? implies;

  /// Tuning override(s) emitted into the class body.
  final String overrideBlock;

  /// The lifecycle hooks this mixin overrides — `before`, `after`, or both.
  ///
  /// [swallowsAfter] answers "does putting this last break the chain"; this
  /// answers "is there a chain here at all". They are different questions and
  /// the audit needs both: an action that writes its own `after()` without
  /// `super.after()` ends the chain in front of *every* mixin it applies, not
  /// only the ones that would have ended it themselves — `with NonReentrant`
  /// plus a bare `after()` leaks the reentrancy key just as surely, with no
  /// `WaitingAction` anywhere in the clause.
  ///
  /// Derived from the package source by `action_template_test`, like the rest
  /// of what frx knows about async_redux.
  final Set<String> hooks;

  /// Whether the mixin overrides `after()` **without** calling `super.after()`.
  ///
  /// Dart calls one `after()` per class — the last mixin's. One of these placed
  /// last therefore ends the chain, and every earlier mixin's cleanup is simply
  /// never run. That is not a hazard the analyzer can see: through async_redux
  /// 28.1, `with WaitingAction, NonReentrant` compiled, analyzed clean, and
  /// left the wait barrier raised for the rest of the session.
  ///
  /// So it is data, in the catalogue, next to [implies] and [exclusiveGroups] —
  /// the two other facts frx transcribes from async_redux. It is why `action`
  /// emits `WaitingAction` last (unconditionally: last is safe whether or not
  /// one of these is present, and a rule with no branch cannot take the wrong
  /// one). `list-mixins` prints it, and the `action-mixin-order` audit check
  /// enforces the position in files frx did not write.
  ///
  /// `action_template_test` derives the set from the package source and checks
  /// the emitted clause against it, so a mixin that gains or loses its
  /// `super.after()` upstream cannot leave either this flag or the order stale.
  /// Which is how it went to false everywhere: async_redux 28.3.1 made every
  /// `after()` it declares chain to `super`, and the test said so. The flag
  /// stays, because the next mixin may not.
  final bool swallowsAfter;

  /// The async_redux members [overrideBlock] names — as data, not prose.
  ///
  /// The block is a string, so a renamed member on the package side would
  /// leave frx writing a `TODO` about a knob that no longer exists, and nothing
  /// would notice: a wrong name in a comment is still valid Dart.
  /// `action_template_test` checks this set against what async_redux declares.
  final Set<String> knobs;

  /// Sets of mixins async_redux declares mutually exclusive.
  ///
  /// Enforced by having each member of a group declare the same private member,
  /// so `dart analyze` reports the combination as
  /// `private_collision_in_mixin_application`. Mirrored here so `add-action`
  /// refuses it up front instead of scaffolding a file the gate will reject —
  /// which is what it used to do for, say, `-m debounce -m retry`.
  ///
  /// `Sequential` is the exception that has only the runtime half: its marker
  /// names no partner, so the analyzer lets `with Sequential, Debounce`
  /// through and the first dispatch asserts (in debug). The pairs below are
  /// what `_incompatible<Sequential, …>` in its `before()` names, and the
  /// refusal up front is the only one a release build gets.
  ///
  /// **The analyzer refuses it; the compiler does not.** Measured, because a
  /// first pass at this comment claimed the opposite in both directions: the
  /// CFE builds `with NonReentrant, Throttle` happily, so `flutter test` on
  /// such a file runs and async_redux's own `assert` inside
  /// `_incompatible<T1, T2>` throws on the first dispatch — in a debug build,
  /// and not at all in a release one. So the guard is the analyzer, and the
  /// runtime is a backstop that a release build does not have.
  ///
  /// The marker method's *name* is the readable source of the rule, which is
  /// what `action_template_test` derives the groups from.
  static const List<Set<ActionMixin>> exclusiveGroups = [
    {fresh, throttle, nonReentrant, unlimitedRetryCheckInternet},
    {checkInternet, abortWhenNoInternet, unlimitedRetryCheckInternet},
    {debounce, retry, unlimitedRetryCheckInternet},
    {sequential, debounce},
    {sequential, unlimitedRetryCheckInternet},
  ];

  /// Every mixin this one cannot be combined with, implications included.
  ///
  /// Pairwise is exact here: [expand] adds each mixin's [implies] chain
  /// independently, so a set conflicts exactly when some pair in its expansion
  /// shares a group. That is what lets a picker filter by set membership
  /// instead of re-running [conflictIn] over every candidate — and lets the
  /// rule stay here, where async_redux's own constraint is mirrored, rather
  /// than being re-encoded in an editor.
  ///
  /// `noDialog` conflicts with `abortWhenNoInternet` for this reason: it does
  /// not share a group with it, but the `checkInternet` it implies does.
  Set<ActionMixin> get conflictsWith => {
    for (final other in ActionMixin.values)
      if (other != this && conflictIn(expand([name, other.name])) != null)
        other,
  };

  /// The first conflicting pair among [mixins], or null when they compose.
  static (ActionMixin, ActionMixin)? conflictIn(List<ActionMixin> mixins) {
    for (final group in exclusiveGroups) {
      final clash = mixins.where(group.contains).toList();
      if (clash.length > 1) {
        return (clash[0], clash[1]);
      }
    }
    return null;
  }

  static ActionMixin parse(String v) => ActionMixin.values.byName(v);

  /// Expands [names] into mixins with every [implies] inserted before its
  /// dependent, deduplicated, in a stable order.
  static List<ActionMixin> expand(Iterable<String> names) {
    // Insertion-ordered, so the set is both the deduplication and the order.
    final out = <ActionMixin>{};
    void add(ActionMixin m) {
      if (m.implies case final implied?) {
        add(implied);
      }
      out.add(m);
    }

    names.map(parse).forEach(add);
    return out.toList();
  }
}
