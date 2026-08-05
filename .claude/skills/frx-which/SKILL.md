---
name: frx-which
description: >-
  What artifact a class, route or field belongs to — and the canonical name
  to hand `rename`. Answered by `frx which` (alias `w`).
---

# `frx which`

Resolve an identifier (class/route/field) to its frx artifact.

```
frx which <identifier>
```

## Flags

```
-h, --help    Print this usage information.
    --json    Emit JSON ({kind, name, suffix, prefix}) instead of a line. kind is null when the identifier is not a wired artifact.
    --root    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
