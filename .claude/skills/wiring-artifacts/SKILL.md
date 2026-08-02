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

# Which command wires what

Every row has its own skill (`frx-<command>`), which carries that command's
flags and its traps. This table is the map; reach for the row's skill when you
act on it.

| You are about to write… | Use |
| --- | --- |
| a slice of application state | `frx add-substate` |
| a field on a slice that already exists | `frx add-field` |
| a value computed from state | `frx add-selector` |
| something that changes state | `frx add-action` |
| a screen and its route | `frx add-page` |
| a tabbed shell over several screens | `frx add-tabs` |
| getting from one screen to another | `frx add-nav` |
| a reusable piece of UI | `frx add-widget` |
| a store connection for a dumb widget | `frx add-connector` |
| a data shape | `frx add-model` |
| a fixed set of values | `frx add-enum` |
| a service and its dispatcher | `frx add-service` |
| an HTTP API client | `frx add-retrofit` |
| theme values | `frx add-theme-extension` |
| several of the above at once | `frx batch` |
| a rename of a substate or page | `frx rename` |
| a deletion of a substate or page | `frx remove` |
| an audit of the project | `frx doctor` |
| what reaches what, and what nothing reaches | `frx graph` |
| what happens when the user taps | `frx flow` |
| what artifact an identifier belongs to | `frx which` |
| an inventory of state slices | `frx list-substates` |
| an inventory of routes | `frx list-routes` |
| where widgets live | `frx list-widget-dirs` |
| which action mixins conflict | `frx list-mixins` |
| codegen running continuously | `frx watch` |

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
- **A private `StatefulWidget` is a widget that never became an artifact.** In
  `ui` a private class is a stateless fragment of the widget above it, or that
  widget's `State`. A component with its own lifecycle earns a file in a family
  folder, which is what gives it a preview and a name anything else can reach.
- **A value and the callback that changes it travel as one view-model.**
  `FieldVm` (or `ChoiceVm`, when the value is picked from a finite set) carries
  the value, its `onChanged`, an optional validator and a server-side error
  together. Split into two fields they are fresh closures every build, so the
  view-model rebuilds the connector on every dispatch.
- **Actions read through the selector facade.** A reducer reaching into
  `state.<slice>.<field>` states the shape of the state twice, and the graph
  cannot see the read, so the selector looks dead and the coupling looks absent.

## Project defaults

A `.frxrc` at the repo root sets the house style once — `buildRunner`, `format`,
`substateKind`, and a `placement` block that silences an audit rule by id. An
explicit flag always wins.

## Orientation

- [`README.md`](../../../README.md) — the architecture and the full command map.
- `frx --help` — the authority, and it always travels with the CLI.
- `docs/flows/` is **generated** from the sources. Regenerate it, never hand-edit
  it; the audit reports it as drift when it falls behind.
