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

**The three that were still hand-written have had their decision**, and it was
a different one each time:

- `codelens.ts` — **generated.** `LAYOUT` carries the conventional directories
  and file suffixes, read off `FrxWorkspace` and `PageArtifact` at a sentinel
  root, so a folder that moves in Dart moves here. This was the quiet one: a
  renamed directory did not break the file, the lens just stopped appearing.
- `naming.ts` — **kept, and pinned by evidence.** A casing conversion is an
  algorithm, and an algorithm is not emittable as data; calling the CLI per
  keystroke to validate a name is not a trade worth making. `NAMING_CASES` is
  the CLI's own answer for the input class the editor is handed (snake, off
  disk), asserted by `vscode/test/naming.test.ts`.
- `menu.ts` — **kept, and it is not a copy of a contract.** The set of command
  ids is already pinned by `extension_contract_test`, harder than generation
  would pin it. What is left is label, codicon and a row description, which are
  the editor's register: `add-widget`'s help is an imperative for a terminal
  and a QuickPick row wants a noun phrase.

A fourth copy turned up while doing it: `PACKAGE_KINDS` in `create.ts`, three
rows of directory and blurb, carrying its own justification ("`add-package`
takes its kind as a positional, so there is no `--kind` list to harvest") —
true of the parser and beside the point, since the catalogue is an enum. Now
`PACKAGES`, with the codicons a `Record` over the union so a fourth package
fails `tsc` until somebody picks one.

Both removals are pinned the way `ARTIFACT_KINDS` is: a test whose job is to
stop the duplicate coming back.
