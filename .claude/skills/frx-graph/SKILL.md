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

## Flags

```
-h, --help                    Print this usage information.
    --json                    Emit the graph as JSON (the machine-readable form).
    --focus                   Only the subgraph around one artifact. Takes a node id (page:logIn), a symbol (LogInRoute, SetEmailAction) or a bare name (log_in).
-d, --direction               With --focus: which way to follow the edges.

          [inbound]           What depends on it — "what breaks if I touch this". Unbounded unless --depth says otherwise.
          [outbound]          What it reaches.
          [both] (default)    Everything around it (the default).

    --depth                   With --focus: how many hops out to follow, or `all` for as far as the edges go.
                              (defaults to "1")
    --root                    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
