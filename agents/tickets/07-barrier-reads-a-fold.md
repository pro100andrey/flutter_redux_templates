# The barrier reads a fold, not a list of two

**Status:** done
**Labels:** ready-for-agent, defect
**Blocked by:** #09 in practice, though not on paper — see Notes.
**Landed in:** `d388718`.

## What to build

A modal barrier that covers every waiting action, instead of the two somebody
remembered to name.

`top_level_page_connector.dart:40` reads `login.isWaiting || registration
.isWaiting`. Four actions mix in `WaitingAction`; two of them are not in that
line, so **tapping "reset password" or "forgot password" gives two seconds of
nothing**. Both have an `isWaiting` selector — written by `add_action_command
.dart:199` — that nothing reads, and `frx graph` reports both as dead, correctly.

`Wait.isWaitingAny` (`async_redux/lib/src/wait.dart:104`, `_flags.isNotEmpty`)
answers the whole question without naming anything, so the fold replaces the list
rather than moving it.

## Acceptance criteria

- [x] `bool get isBusy => state.wait.isWaitingAny;` on `extension
      SelectComposites on Selectors`, beside `canEnterApp`
- [x] `top_level_page_connector` reads it; the two-name disjunction is gone
- [x] The barrier appears for `ForgotPasswordAction` and `ResetPasswordAction` —
      the defect this closes, asserted rather than eyeballed
- [x] `business/test/selectors_test.dart` covers `isBusy` in both directions,
      through the `_Reader with Selectors` stand-in it already has — plus a
      local `_LaterAction`, which is the property a list could not have
- [x] `dart analyze` clean, `dart test` green, `frx doctor` clean

## Notes

**Measured before choosing the fold.** Exactly four actions mix in
`WaitingAction` — `LogInWithEmailAction`, `RegistrationAction`,
`ForgotPasswordAction`, `ResetPasswordAction` — and nothing dispatches
`WaitAction` directly outside the mixin. So `isWaitingAny` is *today* exactly the
set the barrier should cover, and it already covers the two the hand-written line
misses. A future action that wants to wait without blanking the screen would not
mix in `WaitingAction`; if one ever does, a second mixin is the answer, not a
list here.

**#09 turned out to come first, and the reality tier is why.** With `isBusy`
written and nothing else changed, `reality_test`'s *"the blind spots are the ones
we know about"* failed on a new `selector-body` kind: the selector-body scrape
matched only `_state.<field>`, the extension-type spelling, and a composite on
the `Selectors` mixin has no `_state` to reach — so every composite reading state
directly was invisible to the graph. The test offers "fix the reader or add the
kind to `_knownUnresolvedKinds` with the reason", and the second was not
available honestly: that list's own doc says it holds blind spots *unfixable
parse-only*, and this one is fixable, by #09. So #09 landed first and no entry
was added. Afterwards `frx graph` reports
`selector:SelectComposites.isBusy -> substate:wait` and `unresolved` is back to
`pop-destination` alone.

**Why not keep an explicit set on the facade.** That was the first proposal, and
it is the shape that produced the defect: a list somebody has to remember, plus a
fifth wiring hop in `add-action` to maintain it. `frx add-action -k waiting`
currently wires four of five places correctly; the fifth should stop existing
rather than be automated.

**A consequence, accepted rather than overlooked.** With the barrier on the fold,
`frx graph` reports all four per-substate `isWaiting` getters as unread — three
of them outright (`registration`, `forgotPassword`, `resetPassword`) and
`login.isWaiting` as *"read only by selectors nothing reads"*, because its one
remaining reader is `canEnterApp`, which the template has never read. That last
part is not caused by this change: `canEnterApp` was already an orphan before it,
and the first version of this note claimed `login.isWaiting` "survives", which
the graph does not agree with.

They are for per-screen indication — a spinner in a button — which no page in
this template takes: `LogInPage` and `RegistrationPage` declare only fields and
callbacks. `add-action -k waiting` keeps writing the getter, and the skill states
the stance this rests on: *"a selector nothing reads is reported by the graph as
a fact, not a defect: in a template it can be API for whoever builds on it."*
Whether the template should *demonstrate* per-screen waiting is a separate
decision, and a UI one; it is deliberately not in this ticket.
