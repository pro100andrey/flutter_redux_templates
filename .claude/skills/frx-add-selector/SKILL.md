---
name: frx-add-selector
description: >-
  A value computed from state rather than stored in it — a count, a
  filtered list, a derived flag; anything a screen reads that the state
  does not hold directly. Wired by `frx add-selector` (alias `asel`).
---

# `frx add-selector`

Add a computed getter to a substate's Select<Pascal> selector.

```
frx add-selector <substate> <name>
```

## Before you run it

- `--expr` is the getter body and defaults to reading the state field of
  the same name; `--type` tightens the return type from `Object?`. No
  codegen — selectors are hand code.
- A selector nothing reads is reported by the graph as a fact, not a
  defect: in a template it can be API for whoever builds on it.

## Flags

```
-h, --help           Print this usage information.
    --dry-run        Show the planned changes without writing.
    --diff           Print a unified diff of the change.
    --[no-]format    Run `dart format` on the changed files.
                     (defaults to on)
    --json           Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root           Repo root to search from.
-t, --type           The getter return type. Tighten it from the default.
                     (defaults to "Object?")
-e, --expr           The getter body expression. Defaults to reading the state field of the same name (`_state.<substate>.<name>`).
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
