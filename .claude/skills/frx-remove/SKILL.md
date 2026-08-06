---
name: frx-remove
description: >-
  Deleting any artifact — a state slice, a screen, an action, a model, a
  widget, a connector, a service — with everything that points at it. Wired
  by `frx remove` (alias `rm`). Do NOT hand-write this artifact or edit the
  files it wires — run the command.
---

# `frx remove`

Remove an artifact: delete its files and unwire it (AST).

```
frx remove <name> [--kind <kind>] --apply
```

## Before you run it

- Previews by default; `--apply` is what touches disk.
- The kind is auto-detected; pass `--kind` only when the name matches more
  than one, and `--state` when an action name is used under more than one
  substate.
- Reach for it instead of `rm`, which deletes the file you name and leaves
  the rest of the set: a service's dispatcher, a model's `.freezed.dart`
  and `.g.dart` — and those two stop the package compiling once their
  source is gone.
- It deletes the artifact and unwires what registered it. It does not chase
  the code that used it: what still dispatches a deleted action or imports
  a deleted model is yours to fix, so run the audit after.

## Flags

```
-h, --help            Print this usage information.
    --diff            Print a unified diff of the change.
    --[no-]format     Run `dart format` on the changed files.
                      (defaults to on)
    --json            Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root            Repo root to search from.
-b, --build-runner    Run build_runner in the artifact's package after writing.
-k, --kind            Force the target kind (default: auto-detect).
                      [substate, page, action, model, widget, connector, service]
-s, --state           For --kind action: the substate that owns it, when the name is used under more than one.
-a, --apply           Apply the removal (delete files + unwire). Without it the plan is only previewed.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
