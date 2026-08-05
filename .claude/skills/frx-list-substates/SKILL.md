---
name: frx-list-substates
description: >-
  What state slices exist and are composed into `AppState`. Answered by
  `frx list-substates` (alias `ls`).
---

# `frx list-substates`

List the substates composed into AppState (parsed via AST).

```
frx list-substates [arguments]
```

## Flags

```
-h, --help    Print this usage information.
    --json    Emit JSON ({substates:[{field,type,file}]}) instead of a table.
    --root    Repo root to search from. Defaults to walking up from the current directory until app_state.dart is found.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
