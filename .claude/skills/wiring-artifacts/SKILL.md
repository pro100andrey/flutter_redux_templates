---
name: wiring-artifacts
description: >-
  Wiring an artifact of this Flutter AsyncRedux + auto_route monorepo — a state
  slice, a screen and its route, a selector, a navigation hop. Use when creating
  one, when renaming or removing one, when working out how one is wired, or right
  after hand-editing one: writing these files by hand writes the files and misses
  the wiring.
---

# Wiring an artifact of this architecture

Ask which of these four situations you are in, then use the family named beside
it. **Before hand-writing any file of this architecture, run `frx --help` — it
lists every command with what each one wires.** `frx help <command>` gives that
command's flags and what each implies.

| You are… | Use |
| --- | --- |
| about to create an artifact of this architecture | the scaffolders |
| needing to understand how something is wired | the graph, the flow diagrams, and identifier resolution |
| just done editing files by hand | the audit, then the type analyzer |
| renaming or deleting an artifact | rename and removal — both preview, and both need an explicit apply |

The command help is the authority on what exists; this file deliberately keeps no
second copy of it. A copy of the surface has drifted here before, to eight of ten
entries, in the editor extension.

## Why not by hand

Creating a screen by hand is four files and three shared edits. The shared ones
are the ones that are missed or half-done: the `AppState` field *and* its
`initial()` entry, the selector facade's three insertion points, the `AutoRoute`
registration, the auth-guard set.

Every writing command **applies completely or not at all** — a failed write is
indistinguishable from a write never attempted — and every one of them takes
`--json`, which emits the changeset as data: each change with its path, its
operation and a unified diff. With `--dry-run` the same object comes back marked
not applied. A non-zero exit means none of it landed, so you never have to parse
anything to find out whether it worked.

For a feature's worth of artifacts at once, the batch command takes a declaration
of intents and wires them in **one** transaction, in the order written.

## Traps the help does not tell you

- **Action mixins conflict, and the conflict is a compile error.** async_redux
  makes groups of them mutually exclusive by having them collide on a private
  member, so a bad pair fails the build rather than at runtime. Ask the CLI which
  mixins exclude which, and let the scaffolder write the `with` clause — it
  refuses a bad pair up front, which is the check you would otherwise be doing by
  memory.
- **A widget needs its folder named.** The folder is required and open-ended: a
  name that does not exist yet creates it. Ask which folders already hold widgets
  instead of inventing a new home for one — and note that a widget's previews are
  scaffolded alongside it into a mirrored tree, so a widget moved by hand leaves
  its preview behind.
- **Around a live `build_runner watch`, commands stand down.** They hand the build
  over rather than starting a second one, because a second `build_runner` asks the
  incumbent to exit. The fact is reported in the command's own result (`--json`
  carries it), not by the audit — so read it there, at the moment you act. If you
  need generated code *now* and the watch is up, wait for the watch rather than
  killing it.
- **After editing files by hand, run the audit.** It is the safety net for exactly
  the drift the CLI cannot observe: a connector edited by hand, a substate folder
  no longer composed into the state, a `part` whose generated file is missing, a
  declaration sitting in the wrong place. Then run the type analyzer — the audit
  knows this architecture and the analyzer knows Dart, and neither substitutes for
  the other.
- **The graph is a gate you close as you go, not a report you run at the end.**
  The audit and the analyzer both pass on code nothing reaches: a selector no
  reader ever calls, an action no widget dispatches, a slice left unreadable after
  a screen was cut. Only the graph names those, and it names them per feature — so
  read it when you finish each one, while the feature you just wrote is the obvious
  suspect. Run it once at the end and every finding arrives at once, detached from
  the decision that caused it.
- **A private `StatefulWidget` is a widget that never became an artifact.** In
  `ui` a private class is a stateless fragment of the widget above it, or that
  widget's `State` — there is not one private `StatefulWidget` in the package. A
  component with its own lifecycle earns a file in a family folder, which is what
  gives it a preview and a name anything else can reach. Hidden inside a page it
  has neither, and the next screen that needs it copies it instead.
- **A value and the callback that changes it travel as one view-model.** `FieldVm`
  (or `ChoiceVm`, when the value is picked from a finite set) carries the value,
  its `onChanged`, an optional validator and a server-side error together. Split
  into two fields on the view-model it is not merely off-pattern: both are fresh
  closures every build, so a view-model that compares them rebuilds the connector
  on every dispatch. `FieldVm` exists to keep behaviour out of its own `props`.
- **Actions read through the selector facade.** A reducer reaching into
  `state.<slice>.<field>` states the shape of the state twice — once in the slice
  and once in the reducer — and the graph cannot see the read, so the selector
  looks dead and the coupling looks absent. Note that this repository ships no
  example of the rule: every action it carries only writes.

## Orientation

`frx --help` is the authority on the CLI and always travels with it. Two documents
carry what the help cannot, and neither is restated here:

- [`README.md`](../../../README.md) — the architecture: the packages, the layering,
  and what belongs where.
- `tools/README.md` — the CLI in depth: the shared flags, the machine-readable
  output, and the two rules that decide whether a new feature belongs in it. Also
  `tools/vscode/README.md` for the editor extension. **Both live in the template
  repository, not in a project made from it** — `frx create` leaves `tools/`
  behind, because the CLI is installed once and used across every project it
  makes. Reach for `frx --help` when they are not there.

`docs/flows/` is **generated** from the sources — regenerate it, never hand-edit
it. The audit reports it as drift when it falls behind.
