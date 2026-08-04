# Remove the NUL byte and guard against non-text sources

**Status:** done
**Labels:** ready-for-agent, defect
**Blocked by:** None — can start immediately.
**Landed in:** `bfbf125`, and `6f94b11` for the audit-resilience defect found in review.

## What to build

A repository whose source files are all findable by search, and a guard that
keeps them that way.

`FrxWorkspace` held a literal NUL byte in a memo-key string literal. Dart is
fine with it; every tool that decides "binary" by scanning for NUL is not. The
file was `data` to `file(1)`, and `grep -I` skipped it entirely — so
`notSubstateDirs`, `isSubstateDir`, `packageRootOf` and the marker constant
returned zero hits repo-wide. `dart analyze` was clean and 690 tests passed.

## Acceptance criteria

- [x] The NUL is gone; `file` reports the source as text
- [x] `grep -rn notSubstateDirs tools/lib` finds the declaration
- [x] A `doctor` check reports any source that fails to decode as UTF-8 or
      carries a control byte, naming the file and the offset
- [x] A test covers the same rule repository-wide, including untracked-but-not-
      ignored files
- [x] The check is registered in `auditChecks` and has an id
- [x] `dart analyze` clean, `dart test` green

## Notes

The memo key is a record now, so there is no separator to choose.

Found in review and fixed in `6f94b11`: the audit **died** on the file class
this check exists to name — one undecodable source and `frx doctor` exited with
an unhandled `FileSystemException`, discarding every finding including this
check's own. Running the check first did not prevent it; `audit()` returns one
list after the loop. Each check is guarded now and a check that throws becomes
a finding.
