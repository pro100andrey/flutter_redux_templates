---
name: frx-remove
description: >-
  Deleting a state slice or a screen, with everything that points at it.
  Wired by `frx remove` (alias `rm`).
---

# `frx remove`

Remove a substate or page: delete its files and unwire it (AST).

```
frx remove <name> [--kind substate|page] --apply
```

## Before you run it

- Previews by default; `--apply` is what touches disk.
- It knows a substate and a page. Everything else — a widget, a service, a
  model, an enum — is `rm` plus the audit.

## Flags

```
-h, --help            Print this usage information.
    --diff            Print a unified diff of the change.
    --[no-]format     Run `dart format` on the changed files.
                      (defaults to on)
    --json            Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root            Repo root to search from.
-b, --build-runner    Run build_runner in the artifact's package after writing.
-k, --kind            Force the target kind (default: auto-detect from what is wired).
                      [substate, page]
-a, --apply           Apply the removal (delete files + unwire). Without it the plan is only previewed.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
