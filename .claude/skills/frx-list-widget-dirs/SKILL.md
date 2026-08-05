---
name: frx-list-widget-dirs
description: >-
  Where widgets already live, before inventing a folder for a new one.
  Answered by `frx list-widget-dirs` (alias `lwd`).
---

# `frx list-widget-dirs`

List the ui/lib folders that hold widgets (add-widget --dir).

```
frx list-widget-dirs [arguments]
```

## Flags

```
-h, --help    Print this usage information.
    --json    Emit JSON ({dirs:[…], home:{kind:dir}}) instead of a list.
    --root    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
