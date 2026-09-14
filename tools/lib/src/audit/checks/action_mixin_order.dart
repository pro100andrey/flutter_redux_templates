import 'package:path/path.dart' as p;

import '../../ast/mixin_chain_reader.dart';
import '../../ast/source_index.dart';
import '../../scaffold/artifact_templates.dart';
import '../../workspace/frx_workspace.dart';
import '../finding.dart';

/// A `with` clause whose `WaitingAction` cleanup never runs.
///
/// **The only check here about what the code *does* rather than what is out of
/// sync or in the wrong folder,** and it is here because nothing else can see
/// it. Dart calls one `after()` per class — the last mixin's — and
/// [ActionMixin.swallowsAfter] marks the async_redux mixins that override it
/// without calling `super.after()`. So
///
///     class SendVoiceAction extends Action with WaitingAction, NonReentrant
///
/// parses, analyzes clean, passes its tests, and leaves the wait barrier raised
/// forever: `NonReentrant.after()` releases its own lock and returns, so
/// `WaitingAction.after()` is never reached and every widget reading
/// `isWaitingForType<T>()` stays disabled for the rest of the session. That is
/// a dead button, from a `with` clause the analyzer has no opinion about.
///
/// `add-action` now emits `WaitingAction` last, so frx cannot write this shape
/// again. This check is for the other ways to get it: a hand-edited clause, a
/// file scaffolded by an older frx that is still in the tree, and an action
/// that writes its own `before()`/`after()` — a class member beats the whole
/// `with` clause, so forgetting `super` there ends the chain no matter how the
/// mixins are ordered.
///
/// **It also checks the base mixin, and that half is the load-bearing one.**
/// Putting `WaitingAction` last is only correct because the project's own
/// `WaitingAction` chains `super` in both hooks — and that file is the app's,
/// not frx's. In a clone whose `WaitingAction` still swallows the chain, last
/// position moves the loss rather than fixing it: the barrier comes down and
/// the reentrancy lock is never released, so the action never runs a second
/// time. Both halves have to hold, so both are reported.
///
/// An error rather than a silenceable warning: it names async_redux's own
/// mixins doing what async_redux's own source says they do, so unlike the
/// placement rules there is no project that legitimately means it.
void checkActionMixinOrder(FrxWorkspace repo, List<Finding> into) {
  if (!repo.businessLib.existsSync()) {
    return;
  }

  final swallowers = {
    for (final m in ActionMixin.values)
      if (m.swallowsAfter) m.clause,
  };

  /// Which of `before`/`after` [applied] gets from its mixins — the hooks whose
  /// chain an override in the class body would end.
  ///
  /// `WaitingAction` is the app's own and carries both; the rest is
  /// [ActionMixin.hooks], derived from async_redux. A clause with neither has
  /// no chain to break: `ReduxAction`'s own hooks are empty, so an action with
  /// no mixins may override them however it likes.
  Set<String> hooksOwedBy(MixinApplication applied) => {
    if (applied.mixins.contains('WaitingAction')) ...['before', 'after'],
    for (final m in ActionMixin.values)
      if (applied.mixins.contains(m.clause)) ...m.hooks,
  };

  // The textual pre-filter the placement sweep uses: it decides whether to
  // parse, never what to report. A file naming none of these can neither
  // misplace `WaitingAction`, declare it, nor end a chain it does not have.
  final names = {'WaitingAction', for (final m in ActionMixin.values) m.clause};

  for (final file in sourceIndex.filesUnder(repo.businessLib)) {
    final source = sourceIndex.sourceOf(file);
    if (!names.any(source.contains)) {
      continue;
    }
    final where = p.relative(file.path);

    for (final hook in hookOverridesOf(file, 'WaitingAction')) {
      if (hook.chainsSuper) {
        continue;
      }
      into.add(
        Finding.error(
          '$where — WaitingAction.${hook.name}() does not call '
          'super.${hook.name}(), so it ends the chain: mixed in last, as '
          '`add-action` emits it, whatever it sits in front of never runs '
          '(NonReentrant keeps its lock, Throttle and Fresh keep theirs). '
          'Add `super.${hook.name}()`.',
          file: file.path,
        ),
      );
    }

    for (final applied in mixinApplicationsIn(file)) {
      for (final swallower in applied.after('WaitingAction')) {
        if (!swallowers.contains(swallower)) {
          continue;
        }
        into.add(
          Finding.error(
            '$where — ${applied.className} applies $swallower after '
            'WaitingAction, and $swallower.after() does not call '
            'super.after(). The wait barrier goes up and never comes down: '
            'isWaitingForType<${applied.className}>() stays true once the '
            'action has run. Put WaitingAction last.',
            file: file.path,
          ),
        );
      }

      // The same defect with no mixin ordering involved. A class member wins
      // over the whole `with` clause, so an action that writes its own hook
      // and forgets `super` ends the chain in front of everything — measured
      // both ways: a bare `after()` leaves the barrier up for good, and a bare
      // `before()` means it never goes up at all.
      //
      // Not only `WaitingAction`, which is where this started. `NonReentrant`
      // releases its key in `after()` and `CheckInternet` does its work in
      // `before()`; an action that overrides either hook without `super` eats
      // that too, and the key it leaks is the one that stops the action ever
      // running again.
      final owed = hooksOwedBy(applied);
      for (final hook in applied.hooks) {
        if (hook.chainsSuper || !owed.contains(hook.name)) {
          continue;
        }
        final eaten = [
          if (applied.mixins.contains('WaitingAction')) 'WaitingAction',
          for (final m in ActionMixin.values)
            if (applied.mixins.contains(m.clause) &&
                m.hooks.contains(hook.name))
              m.clause,
        ];
        into.add(
          Finding.error(
            '$where — ${applied.className} overrides ${hook.name}() without '
            'calling super.${hook.name}(), which ends the chain ahead of its '
            'own mixins: ${eaten.join(', ')}.${hook.name}() never runs. '
            'Add `super.${hook.name}()`.',
            file: file.path,
          ),
        );
      }
    }
  }
}
