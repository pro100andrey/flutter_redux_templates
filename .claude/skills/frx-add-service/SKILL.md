---
name: frx-add-service
description: >-
  A service and the Redux dispatcher that lets it reach the store. Wired by
  `frx add-service` (alias `asvc`). Do NOT hand-write this artifact or edit
  the files it wires — run the command.
---

# `frx add-service`

Scaffold a service + Redux dispatcher under redux/services.

```
frx add-service <name>
```

## Before you run it

- The suffix is optional and idempotent: `Sync` and `SyncService` scaffold
  the same artifact. Do not strip it yourself, and do not add it — pass the
  name as you have it. `frx remove` reads the same rule, so whichever
  spelling created it removes it.

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
