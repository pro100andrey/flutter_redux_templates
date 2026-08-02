---
name: frx-list-mixins
description: >-
  Which action mixins imply what, and which exclude which — before passing
  a second `--mixin`. Answered by `frx list-mixins` (alias `lm`).
---

# `frx list-mixins`

The action mixins, what they imply and what they exclude.

```
frx list-mixins [arguments]
```

## Flags

```
-h, --help    Print this usage information.
    --json    Emit JSON ({mixins:[{name,clause,summary,implies,conflictsWith}]}) instead of a table.
    --root    Repo root (accepted for consistency).
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
