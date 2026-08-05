# Put rename and batch back on the write path

**Status:** done
**Labels:** architecture
**Blocked by:** #01
**Landed in:** `6b7fc1d`

## What to build

One write path for every writing command. `rename` and `batch` both opted out
of `WritingCommand` and re-implemented parts of the tail.

## Acceptance criteria

- [x] The preview-gate sentence is written once
- [x] `batch`'s post-apply pair comes from the same place as `apply`'s
- [x] The parts genuinely rename's own stay rename's own
- [ ] "`rename` builds a `WritePlan` and stops" — **refused**, see Notes
- [ ] "Whatever of `frx_command_test.dart` becomes structural is retired" —
      nothing became structural, so it stands
- [x] `dart analyze` clean, `dart test` green

## Notes

Also closed: `applying(results)` (`--apply || --force`, derived inline in both
destructive commands), and `batch` rendering its plan from the transaction's
flat path lists — every change printed as `write`, including the overwrites,
edits and moves that its own `--json` named correctly.

**The premise did not survive checking.** "A 199-line private copy of
`runChangeset`" is wrong: about 43 lines overlap. The rest is rename's own — a
parse-tree sweep, a plan whose unit is "N references in M files", a moves
pre-flight the generic collision guard does not cover, and post-apply pruning
plus `dart fix`. Moving it needs three new callbacks on an interface that
already takes eight optional parameters, to serve one caller.
