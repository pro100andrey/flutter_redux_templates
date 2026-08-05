# Where an artifact lives, said once

**Status:** done
**Labels:** ready-for-agent, defect, architecture
**Blocked by:** #01
**Landed in:** `d7e6735`, with two defects of its own fixed in `6f94b11` and the agent-facing rule documented in `9eca090`.

## What to build

`add` derives paths forward, `remove` derives them backward, and they agreed
only because they were written to agree. Nothing tested that they still did.

## Acceptance criteria

- [x] A test proves add and remove agree for every kind — scaffolded by the real
      `add-*`, removed by the name a user would type, asserting the file set
      comes back empty
- [x] `RemovableResolver` reads the widget naming rule instead of re-deriving it
- [x] The suffix rules are stated once and read both ways
- [~] "Each artifact kind answers which files am I from one place" — only the
      *naming* moved. `model`, `enum` and `service` still join their own paths
      at the add sites; see Notes.

## Notes

Two live defects found by the round-trip test, both silent:

- A widget's file is named after its class, so `-k field` wrote
  `pin_form_field.dart` while `remove Pin --kind widget` looked for `pin.dart`
  and exited 70. Only the kinds that add no suffix round-tripped, which is why
  every existing test passed.
- `add` never stripped and `remove` always did, so `add-action
  ArchiveTaskAction` scaffolded `ArchiveTaskActionAction`.

Two more introduced while fixing those and caught in review (`6f94b11`): the
scaffolder began stripping twice while removal stripped once, and `service` was
declared to have "no suffix rule" when `add-service` writes `class <Name>Service`
— so `SyncService` made `SyncServiceService`.

**Left open deliberately.** The remaining duplication is `'<snake>.dart'` joined
to a `FrxWorkspace` directory, with no suffix rule left to get backwards, and
`codelens.ts` still derives the layout in TypeScript — that belongs with #06.
