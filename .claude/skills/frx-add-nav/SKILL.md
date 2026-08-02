---
name: frx-add-nav
description: >-
  Getting from one screen to another — a tap that opens another page. Wired
  by `frx add-nav` (alias `an`). Do NOT hand-write this artifact or edit
  the files it wires — run the command.
paths:
  - "app/lib/connectors/*.dart"
  - "app/lib/navigation/*.dart"
---

# `frx add-nav`

Wire a navigation hop from one page to another (AST).

```
frx add-nav <from> <to>
```

## Before you run it

- Five edits across two packages, four of which alone leave code that does
  not compile. `--kind` picks the `GoAction` factory: `push`, `replace` or
  `navigate`.

## Flags

```
-h, --help           Print this usage information.
    --dry-run        Show the planned changes without writing.
    --diff           Print a unified diff of the change.
    --[no-]format    Run `dart format` on the changed files.
                     (defaults to on)
    --json           Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root           Repo root to search from.
    --via            Callback name on the source page. Defaults to onTap<Destination>.
-k, --kind           Which GoAction factory the callback dispatches.
                     [push (default), replace, navigate]
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
