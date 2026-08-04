---
name: frx-watch
description: >-
  Running codegen continuously while working, instead of after each write.
  Answered by `frx watch` (alias `wa`).
---

# `frx watch`

Run build_runner watch (whole workspace, or one --package).

```
frx watch [arguments]
```

## Flags

```
-h, --help       Print this usage information.
-p, --package    Watch a single package (e.g. business) instead of the whole workspace.
    --print      Print the command that would run, then exit (don't watch).
    --root       Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
