---
name: frx-list-routes
description: >-
  What routes the router registers. Answered by `frx list-routes` (alias
  `lr`).
---

# `frx list-routes`

List the routes registered in AppRouter (parsed via AST).

```
frx list-routes [arguments]
```

## Flags

```
-h, --help    Print this usage information.
    --json    Emit JSON ({routes:[{route,path,connector}]}) instead of a table.
    --root    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
