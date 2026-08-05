# The CLI's contract as data, not prose

**Status:** done
**Labels:** architecture
**Blocked by:** #01, #03
**Landed in:** `b5085c5`, with exit codes added in `6f94b11`.

## What to build

The extension reading the CLI's contract instead of restating it, so drift
becomes impossible rather than asserted.

## Acceptance criteria

- [x] The CLI emits kinds, marker, remedy ids **and exit codes** as data
- [x] The extension's copies are generated, guarded by the same freshness
      pattern skills and template already use
- [x] The `--kind` sets that no test covered are covered
- [x] CI keeps its Node-only constraint
- [x] The contract-test check the seam made impossible is retired
- [x] `dart analyze` clean, `dart test` green, `tsc --noEmit` clean

## Notes

`completions_command` already proved the seam — it reads `option.allowed` off
the parser, so shell completion cannot drift. `ContractGen` now writes
`vscode/src/generated/contract.ts` the same way.

Values are the contract; the prose beside them is the editor's. They are joined
by `Record<Kind<'x'>, …>`, so the compiler enforces it — verified rather than
assumed: adding a fourth substate kind fails `tsc` until somebody writes what it
does.

**Still hand-written in the extension, and each needs its own decision about
what the CLI should emit:** `naming.ts` (the casing rules), `codelens.ts` (the
file layout), `menu.ts` (28 label/description pairs).
