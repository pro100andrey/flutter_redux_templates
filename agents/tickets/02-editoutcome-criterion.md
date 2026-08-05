# Apply the criterion EditOutcome already states

**Status:** done
**Labels:** ready-for-agent, architecture
**Blocked by:** #01 — search has to work before touching six modules by name.
**Landed in:** `6b0ad76`

## What to build

`ast_edit.dart` has said since it was written that "a module whose callers do
not read the specific word returns `Edited` instead of making another class for
the same three fields". Nine result classes existed and nobody had checked the
rule against the callers.

## Acceptance criteria

- [x] Result classes whose distinguishing field no production caller reads are
      replaced by `Edited` / `Unwired`
- [x] Classes whose field IS read keep it, and the doc names the callers
- [x] `.warnings` carriers keep their type — it crosses into the extension
- [x] Tests that asserted on a removed field assert through `unchanged`
- [x] `dart analyze` clean, `dart test` green

## Notes

Measured, production readers only: `.found` 0 across three classes, `.retyped`
0 anywhere, `.alreadyWired` 1 across four, `.alreadyPresent` 2, `.warnings` 3.

Nine module-specific types down to three. `SelectorsAddResult` stays and earns
it: `alreadyPresent` is **not** `unchanged` — a retyped selector is present and
changed at once, so reading `unchanged` there would print "Nothing to do" after
a rewrite.

Two unwire results collapsed into a shared `Unwired` rather than into `Edited`,
because `found` is the word their tests are written in. Tests are callers.
