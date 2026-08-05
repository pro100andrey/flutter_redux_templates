---
name: frx-add-model
description: >-
  A data shape the app passes around — a freezed model, or a sealed union
  when the value is one of several cases. Wired by `frx add-model` (alias
  `am`). Do NOT hand-write this artifact or edit the files it wires — run
  the command.
---

# `frx add-model`

Scaffold a freezed model (or sealed union) in the models package.

```
frx add-model <name> [--serializable] [-c <case> …]
```

## Before you run it

- `-c <case>` twice or more makes it a sealed union with one factory per
  case. Three answers as three cases beat a nullable field with a flag
  beside it.

## Flags

```
-h, --help            Print this usage information.
    --dry-run         Show the planned changes without writing.
-f, --force           Overwrite existing files.
    --[no-]format     Run `dart format` on the changed files.
                      (defaults to on)
    --json            Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root            Repo root to search from.
-b, --build-runner    Run build_runner in the artifact's package after writing.
    --serializable    Also generate fromJson/toJson (adds the .g.dart part).
-c, --case            Union case name (repeatable, ≥2) — makes the model a sealed union with one factory per case, e.g. -c loading -c success.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
