# A selector's body is read as code, not as text

**Status:** done
**Labels:** ready-for-agent, defect
**Blocked by:** None — and #07 turned out to need it first, see that ticket.
**Landed in:** `d388718`.

## What to build

`_SelectorVisitor._collect` derives what a selector reads by running three
regexes over `m.body.toSource()` (`graph_reader.dart:877`, `:878-880`, `:884`).
Text does not distinguish a string literal from code, so it misreads one.

Reproduced, using nothing but the product's own commands:

```sh
frx create fproj --target /tmp/fproj
frx add-selector session label --type String --expr "'token'" --root /tmp/fproj
frx graph --root /tmp/fproj --json
```

`SelectSession.label` returns the *string* `'token'` and reads no state at all.
The graph says:

```
selector:SelectSession.label -> substate:session   kind=reads  via=label
```

`_bareRef` matched `token` inside the quotes, and `_inheritFromSiblings` folded
the neighbouring `SelectSession.token`'s reads into it. In the same output the
reason another selector is dead changes with it: `SelectSession.token` goes from
*"nothing reads it"* to *"read only by selectors nothing reads"*. Where the
phantom reader is itself read by a connector, a dead selector is reported alive.

The other half of this same file already does it properly — `selectorUsesIn`
(`graph_reader.dart:775`) walks the AST, and its doc at `:762-765` says text
scanning was the wrong instrument for that direction. Both halves, one file,
opposite methods.

## Acceptance criteria

- [x] `_stateField`, `_waitingFor` and `_bareRef` are replaced by a walk over the
      body's AST (`_BodyReader`); a string literal contributes nothing
- [x] A test pins the reproduction above — three cases in `graph_test.dart`: the
      quoting getter reads nothing, the quoted one still reads its own slice, and
      a composite reaching state through `state` resolves
- [x] `_PersistorVisitor` gets the same treatment: `persistDifference`'s
      constructed `RegExp` over `node.body.toSource()` is now `_ParamFieldReads`,
      which handles `newState.session` and `lastPersistedState?.theme` — a
      `PrefixedIdentifier` and a `PropertyAccess` respectively
- [x] `checks.dart` calls `repo.substateDirsIn()` instead of spelling
      `directoriesIn` + `isSubstateDir` again — see Notes
- [x] The stale doc comment says `on Selectors`, which is what the facade has
      been since `33b8082`
- [x] `dart analyze` clean, `dart test` green (888), `frx doctor` clean

## Notes

**The cleanup rides along, and it is smaller than it was reported to be.**
`checks.dart:185` re-spells the substate-folder rule that `substateDirsIn()`
exists to hold — `frx_workspace.dart:231-238` names that duplication as the thing
it was extracted to end. It was first raised as a *divergence* risk, on the
grounds that the audit derives it from `AppStateSource.reduxDir` and the helper
from `FrxWorkspace.businessRedux`. That is wrong: `AppStateSource.of(repo)`
builds the file as `p.join(repo.root.path, 'business/lib/redux/app_state.dart')`
(`app_state_source.dart:84-85`), so the two directories are identical by
construction — and `of`'s own doc at `:76-83` says it exists precisely so the two
markers cannot answer differently. What is left is one spelling too many. Three
lines.

**Refused: one `ArtifactIndex` above `SourceIndex`.** Raised as "four methods
answer *is this a connector*". Checked, and the count does not hold. Three of
them answer one question — which file backs a route (`route_map.dart:243`,
`checks.dart:466`, `placement.dart:147`) — and serve consumers with deliberately
different tolerance. The fourth, `flow_reader.dart:141`, answers a *different*
question: which connector does this unit construct, i.e. composition. And there
is a fifth concept that is not a duplicate at all — `NodeKind.consumer`
(`graph_reader.dart:602`), a deliberate catch-all whose comment at `:585-588`
explains it exists so that selectors read only by an *unrouted* connector are not
reported dead. Verified: `frx graph` on this repo emits
`consumer:TopLevelPageConnector` and keeps `login.isWaiting` alive through it.

The performance half does not hold either. `TargetResolver.locate` really does
run outside the `inSourceIndex` scope (`graph_command.dart:162`), and `frx which`
really does re-enter `readSubstates()`/`readRoutes()` per candidate
(`naming_convention.dart:86-112`). Measured on this repo, five runs of a kernel
snapshot each:

```
graph (no focus)              477.6 ms
graph --focus login (leaky)   482.7 ms     → +1%
which LoginState (leaky ×6)   282.8 ms
list-substates (one read)     281.7 ms     → +1 ms
```

The floor is VM startup; `app_state.dart` and `app_router.dart` parse in
microseconds. Correct literally, worth nothing.

**Refused: a pass registry for graph and flow, like the audit's `Check`.** The
argument was test cost — a 172-line fixture builder in `graph_test` rebuilt per
read, four more builders in `flow_test`. Measured, it inverts:

```
graph_test       2.1 s / 62 tests      no registry
flow_test        1.6 s / 38 tests      no registry
route_map_test   1.5 s / 28 tests      no registry
doctor_test      6.7 s / 17 tests      HAS the registry
```

The slow suite is the one that already has the seam, and it is slow because it
shells out, not because of its shape. At ~34 ms a test nobody is paying for the
absence. What was real in that candidate is the regex/AST mismatch above, and
that is a defect, not an architecture.
