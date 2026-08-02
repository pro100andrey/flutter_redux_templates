---
name: wiring-artifacts
description: >-
  Router for this Flutter AsyncRedux + auto_route monorepo — picks which `frx`
  command wires the artifact you are about to write, and carries the rules that
  belong to no single command. Use when several artifacts are needed at once,
  when it is unclear which command owns a change, right after hand-editing files
  of this architecture, or when deleting anything that is not a substate or a
  page.
---

# Wiring artifacts of this architecture

Every artifact this architecture has is created and wired by one `frx` command,
and each command carries its own skill — how the artifact is written here, and
what its help does not say. Those skills reach you on their own: they fire on
the situation, and the file-editing ones fire again on the file. Reading them
ahead of time is not how they work and not how they are counted.

`frx --help` lists the commands. This file carries what belongs to no single one.

Names take any casing — `myProfile`, `my_profile`, `MyProfile` and `my-profile`
all resolve to the same artifact.

## More than one artifact at once

`frx batch` takes the intents as data and wires them in **one** transaction, in
the order written. A shell loop over the same commands is the usual substitute
and is not the same thing: it has no rollback boundary, so a failure at the
fifth intent leaves the first four wired and the state half-built. Batch covers
the creation commands only — `rename` and `remove` are refused with the reason.

## The rules that belong to no single command

- **A write applies completely or not at all.** A failed write is
  indistinguishable from a write never attempted, so a zero exit means the whole
  changeset landed and you never have to parse anything to find out. Exit `64` is
  a usage error, `70` is "cannot do this here". What sits outside the
  transaction: `dart format`, the `docs/flows` refresh and `build_runner` run
  after it and roll nothing back.
- **After editing files by hand, run the audit, then the type analyzer.** The
  audit knows this architecture and the analyzer knows Dart; neither substitutes
  for the other. The way this one is lost is not skipping it but spacing it — run
  it once before starting and once when done and the whole middle went
  unmeasured, every finding surfacing where any of a hundred edits could have
  caused it.
- **The graph is a gate you close as you go.** The audit and the analyzer both
  pass on code nothing reaches: a selector no reader calls, an action no widget
  dispatches. The moment is precise — the feature compiles, and you have not
  started the next one.
- **Deleting anything that is not a substate or a page is manual.** `frx remove`
  knows those two. A widget, a connector, a service, a model, an enum, a theme
  extension comes out with `rm`, and nothing unwires it: what still imports it is
  yours to find, and a widget leaves its mirrored preview behind. So `rm` and
  then the audit, in the same breath.
- **Around a live `build_runner watch`, commands stand down.** They hand the
  build over rather than starting a second one. The fact is reported in the
  command's own result (`--json` carries it as `build.handedToWatch`), not by the
  audit — read it there, at the moment you act. An *orphaned* watch is the
  converse: it regenerates nothing, and the audit reports it.
- **`ui` is data-driven and knows no domain.** It depends on neither `models` nor
  `business`; a widget draws what it is handed. The connector is the seam where a
  domain value becomes a primitive, a formatted string or a `ui`-local render
  model. See `frx-add-widget` and `frx-add-connector`.

## Writing the body, not just the file

A command scaffolds the file and its wiring. How the body is written afterwards
is this architecture's own, and in several places it is the opposite of what
async_redux's documentation shows — `@freezed` rather than a hand-written
`copy()`, an `extension type` facade rather than memoised selector functions,
`extends Action` rather than `extends ReduxAction`.

Read **`asyncredux-in-this-template`** before filling in a reducer, a connector
or a state class, and whenever recalled async_redux knowledge is about to be
applied here. Each command's own skill carries the rules for its artifact.

## Project defaults

A `.frxrc` at the repo root sets the house style once — `buildRunner`, `format`,
`substateKind`, and a `placement` block that silences an audit rule by id. An
explicit flag always wins.

## Orientation

- [`README.md`](../../../README.md) — the architecture and the full command map.
- `frx --help` — the authority, and it always travels with the CLI.
- `docs/flows/` is **generated** from the sources. Regenerate it, never hand-edit
  it; the audit reports it as drift when it falls behind.
