---
name: frx-add-substate
description: >-
  A new slice of application state — a list or table of things, a search,
  or a single value the app holds onto. Wired by `frx add-substate` (alias
  `as`).
---

# `frx add-substate`

Scaffold an AsyncRedux substate and wire it into AppState (AST).

```
frx add-substate <name>
```

## Before you run it

- The kind decides the shape: `table` for a keyed collection with an
  ordering, `search` for a query with results, `value` for one value. Ask
  which before scaffolding — changing it later is a rewrite.
- It wires the `AppState` field *and* its `initial()` entry, the selectors
  facade and the change log. What dispatches its starter actions is yours.

## Flags

```
-h, --help                     Print this usage information.
    --dry-run                  Show the planned changes without writing.
-f, --force                    Overwrite existing files.
    --[no-]format              Run `dart format` on the changed files.
                               (defaults to on)
    --json                     Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root                     Repo root to search from.
-b, --build-runner             Run build_runner in the artifact's package after writing.
-k, --kind                     Which substate flavour to scaffold.

          [value] (default)    A single nullable `value` field + SetValueAction.
          [search]             A `query` string + `IList<int> view` + SetQueryAction.
          [table]              A byId `IMap` table + view + Add…/Retrieve… actions.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
