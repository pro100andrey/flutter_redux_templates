---
name: frx-batch
description: >-
  Several artifacts at once — a whole feature's worth of state, screens and
  actions, wired together. Wired by `frx batch` (alias `bat`). Do NOT
  hand-write this artifact or edit the files it wires — run the command.
---

# `frx batch`

Wire a declared list of artifacts in one transaction (file or stdin).

```
frx batch <file.json>|- [--dry-run]
```

## Before you run it

- One rollback boundary where eight invocations are eight boundaries: a
  failure at the fifth intent leaves nothing of the first four.
- Intents apply **in the order written** and fail loudly — `add-action`
  refuses a substate that is not there — so a prerequisite comes first.
  Nothing is reordered for you, on purpose.
- Creation commands only. `rename` and `remove` are refused, and an intent
  carrying `--dry-run`, `--json`, `--build-runner` or `--format` is refused
  too: those decide whether the batch writes.

## Flags

```
-h, --help            Print this usage information.
    --dry-run         Report the combined plan without keeping it. The batch is applied and unwound — see the note in the README.
-b, --build-runner    Run build_runner once after the batch, in each package it wrote.
    --[no-]format     Run `dart format` once on everything the batch wrote.
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
