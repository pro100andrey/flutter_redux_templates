---
name: frx-add-connector
description: >-
  Connecting a dumb widget to the store — the `StoreConnector` that builds
  its view-model. Wired by `frx add-connector` (alias `ac`).
---

# `frx add-connector`

Scaffold a StoreConnector for a ui widget.

```
frx add-connector <name>
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
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
