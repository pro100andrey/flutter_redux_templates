---
name: frx-add-enum
description: >-
  A fixed set of values — a status, a priority, a mode. Wired by `frx
  add-enum` (alias `ae`).
---

# `frx add-enum`

Scaffold a plain enum in the models package.

```
frx add-enum <name> -v <value> [-v <value> …]
```

## Flags

```
-h, --help           Print this usage information.
    --dry-run        Show the planned changes without writing.
-f, --force          Overwrite existing files.
    --[no-]format    Run `dart format` on the changed files.
                     (defaults to on)
    --json           Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root           Repo root to search from.
-v, --value          An enum value (repeatable, ≥1), e.g. -v pending -v done.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
