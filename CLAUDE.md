# CLAUDE.md

Guidance for agents working in this repository.

## Before hand-writing a file of this architecture, check `frx`

**Run `frx --help` first — it lists every command with what each one wires.**

This monorepo has a CLI that creates *and wires* every artifact of its
architecture: a state slice, a screen and its route, an action, a field, a
computed selector, a navigation hop, a connector, a widget, a service, an API
client. Writing those files by hand writes the files and misses the wiring — the
state slot and its `initial()` entry, the selector facade, the route
registration, the auth-guard membership. Wiring one navigation hop is five edits
across two packages, four of which leave code that does not compile on their own.

This rule is unconditional, and it applies to editing an existing artifact as much
as to creating one: **after any hand edit, run the audit** (`frx doctor`), then
`dart analyze`. The audit knows this architecture; the analyzer knows Dart.
