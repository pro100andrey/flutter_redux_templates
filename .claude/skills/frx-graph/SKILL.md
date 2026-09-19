---
name: frx-graph
description: >-
  What reaches what — who can change this slice, what breaks if it is
  touched, and which selectors or actions nothing reaches at all. Answered
  by `frx graph` (alias `g`).
---

# `frx graph`

Emit the whole app as one graph (nodes, edges, and what frx could not resolve).

```
frx graph [--json] [--focus <artifact>] [--direction inbound]
```

## Before you run it

- `--focus` takes a node id, a symbol or a bare name; `-d inbound` answers
  "what breaks if I touch this" and is unbounded by default.
- The `unresolved` section matters as much as the edges: a missing edge and
  a relation that does not exist look identical, so the gaps are named
  rather than dropped.
- **"No dispatcher found" is not always dead code.** The walk starts at
  connectors, actions and service dispatchers, so an action dispatched from
  anywhere else — the boot in `run_env.dart` being the one the template
  itself needs — is reported as reached by nobody. Check where it is
  dispatched before deleting it; a substate's `Retrieve…Action` is the
  expected case.
- **Every action class is a node**, including a private step declared
  beside the action that dispatches it. Its id is qualified by the file's
  main action — `action:setup.InstallSkillsAction._AgentWorking` — because
  two files in one substate may each declare a `_Started`; `--focus` on the
  bare name answers with both ids.
- **Ask about a field, not a slice.** `--focus session.token -d inbound`
  keeps only what touches that field — the setters writing it, the
  selectors and reducers reading it, and the persistor, which restores all
  of it — where `--focus substate:session` on a slice with fifty fields
  returns the whole app. A `reads` edge is drawn for a direct
  `state.session.token` in a reducer or a connector as much as for a
  selector, so a selector on the "nothing reads it" list beside a reducer
  reading the same field is a dead selector, not a dead field — and
  `field:setup.agentErrorOn written, nothing reads it` on the same list is
  a field to remove along with its selector and every write of it (`frx
  remove agentErrorOn --kind field --state setup`).

## Flags

```
-h, --help                    Print this usage information.
    --json                    Emit the graph as JSON (the machine-readable form).
    --focus                   Only the subgraph around one artifact. Takes a node id (page:logIn), a symbol (LogInRoute, SetEmailAction), a bare name (log_in), or one field of a substate (session.token) — what touches that field, not the whole slice.
-d, --direction               With --focus: which way to follow the edges.

          [inbound]           What depends on it — "what breaks if I touch this". Unbounded unless --depth says otherwise.
          [outbound]          What it reaches.
          [both] (default)    Everything around it (the default).

    --depth                   With --focus: how many hops out to follow, or `all` for as far as the edges go.
                              (defaults to "1")
    --fail-on-orphans         Exit 1 when the "nothing reaches" list is not empty — a gate for CI. Advice rather than drift, which is why doctor does not report it: `add-action -k waiting` writes an isWaiting getter nothing reads yet, and a check that fired on frx's own output would be noise.
    --root                    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
