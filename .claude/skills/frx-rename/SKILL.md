---
name: frx-rename
description: >-
  Renaming a state slice or a screen — files, classes and every wiring
  reference. Wired by `frx rename` (alias `mv`).
---

# `frx rename`

Rename a substate or page — files, classes, and all wiring references.

```
frx rename <old> <new> [--kind substate|page] --apply
```

## Before you run it

- Previews by default; `--apply` is what touches disk. Identifiers move off
  the parse tree, so a name inside a persistence key survives untouched.

## Flags

```
-h, --help            Print this usage information.
-k, --kind            Force the target kind (default: auto-detect from what is wired).
                      [substate, page]
-a, --apply           Apply the rename (move files + rewrite references). Without it the plan is only previewed.
-b, --build-runner    Run build_runner in the affected package after renaming.
    --diff            Also print a unified diff of the reference rewrites.
    --[no-]format     Run `dart format` on the edited files.
                      (defaults to on)
    --json            Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root            Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
