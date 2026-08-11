# The hand-write prohibition lives on the situation, not beside it

**Status:** done
**Labels:** ready-for-agent, defect
**Blocked by:** None.
**Landed in:** working tree on `architecture-review-follow-ups`, not yet
committed.

## What to build

The bit that decides whether a skill says *"Wired by … Do NOT hand-write this
artifact"* or the toothless *"Answered by"*, stored on the structure that already
exists per command instead of in a second set keyed by the same names.

It has already come apart. `add-package` extends `WritingCommand`
(`add_package_command.dart:22`) and `package_scaffold.dart:197-201` says creating
a package is *"five changes across two directories, and four of them alone leave
a workspace that does not resolve"* — exactly what the prohibition is for. Its
skill carries no prohibition:

```
Answered by `frx add-package` (alias `apkg`).
```

## Acceptance criteria

- [x] The bit cannot be left undecided — done as `_Situation.wired` /
      `_Situation.read` with no unnamed constructor, rather than as a required
      `bool wires`. See Notes.
- [x] `_writes` (`skill_gen.dart:393-411`) is deleted
- [x] `.claude/skills/frx-add-package/SKILL.md` carries the prohibition
- [x] `make skills` run; `skills_freshness_test.dart` green
- [x] `dart analyze` clean, `dart test` green (888), `frx doctor` clean

## Notes

**The mechanism of the drift, which is the reason for the shape.** `_writes` is
read at exactly two places — `skill_gen.dart:198` and `:200` — and both are
inside `_skill()`, where the `_Situation` is already in hand as `s`. The bit was
looked up by name in a set 620 lines above the object it describes.
`add-package` *has* a `_Situation` (`skill_gen.dart:1031`); it is simply not the
structure the bit lived in. Required, on that object, the drift stops being
something to remember and becomes something that does not compile.

**Three alternatives, and why none of them.**

- *Add `add-package` to the set.* Fixes one instance, leaves the mechanism.
- *Pin the set with a test against `cmd is WritingCommand`.* Catches drift after
  somebody writes it, and needs an allowlist of its own. The precedent quoted for
  it — `_notInTheEditor` in `extension_contract_test.dart:310-342` — does not
  transfer: that one holds two sides written in *different languages* which
  cannot share a declaration. Both sides here are in one file.
- *A `wiresArtifact` property on `WritingCommand`.* Does not close. `batch` and
  `rename` wire artifacts and do not extend `WritingCommand`, so it needs a
  second mechanism for them — two mechanisms for one predicate. It would also put
  the skill generator's question ("must an agent be stopped from writing this by
  hand?") onto the command hierarchy, where nothing else asks it.

**Two constructors, not a required flag — and the analyzer paid for the split
immediately.** The guarantee is the same: with no unnamed constructor, a
situation cannot be written without choosing. What is better is the call site,
where `_Situation.wired(…)` says what it means and `wires: true` would have to be
read as a position. The moment the two existed, `dart analyze` reported that
`context` and `paths` are never passed to `_Situation.read` — which is true and
worth saying in the type: `context` describes what an artifact *is*, `paths`
fires on the file being edited, and a command that writes no artifact has
neither. `_Situation.read` now takes neither.

**The exception list goes to zero.** `update-skills` looked like an exception and
is not one: it has no `_Situation`, `generate()` skips commands that have none,
so the bit is never asked for it. `batch` and `rename` declare `wires: true` like
any other entry.

**Refused: moving the skill prose out to `.md` assets.** The file is 1,494 lines,
about 1,140 of them Markdown, and that reads as the problem. Measured, it is not.
Nine of the ten literal blocks are raw strings (`r'''`), so the whole file holds
8 `\'` escapes and no `\$` — the Markdown is stored very nearly verbatim. `frx`
ships as a compiled binary (`make dist`, and it self-updates), so the prose has
to travel *inside* it either way; assets would mean a second packed `.g.dart`
beside `template.g.dart` and a third artifact moving per prose edit, which is
worse than what exists. And the runtime cost of generating all 30 skills on every
debounced audit is 15 ms of a 628 ms `frx doctor` (~2.4%), measured by toggling
`.frx-owned` in a scratch project. Nothing here to win.
