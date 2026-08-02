---
name: frx-doctor
description: >-
  Checking the project is still consistent — after hand edits, after a
  deletion, or before calling something done. Answered by `frx doctor`
  (alias `dr`).
---

# `frx doctor`

Audit the project for wiring drift, ungenerated code and misplaced declarations.

```
frx doctor [arguments]
```

## Before you run it

- It finds wiring drift, ungenerated code and misplaced declarations — what
  the Dart analyzer cannot know. Run both.
- `--fix` repairs what is safe to repair: runs codegen, removes an orphan
  substate folder that holds nothing. Placement findings never auto-fix — a
  deliberately placed file is the false positive being accepted.

## Flags

```
-h, --help    Print this usage information.
    --fix     Repair auto-fixable findings: run build_runner for missing parts and remove orphan substate folders.
    --json    Emit findings as JSON ({findings:[{severity,message,file,fix,rule}]}) instead of the report. Read-only (ignores --fix).
    --root    Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
