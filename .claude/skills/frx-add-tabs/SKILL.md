---
name: frx-add-tabs
description: >-
  A tabbed shell — several screens living under one tab bar, as a nested
  route. Wired by `frx add-tabs` (alias `at`). Do NOT hand-write this
  artifact or edit the files it wires — run the command.
---

# `frx add-tabs`

Scaffold an AutoTabsScaffold shell + tab pages and wire the nested route.

```
frx add-tabs <name> --tab <t1> --tab <t2> …
```

## Flags

```
-h, --help            Print this usage information.
    --dry-run         Show the planned changes without writing.
-f, --force           Overwrite existing files.
    --[no-]format     Run `dart format` on the changed files.
                      (defaults to on)
    --json            Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root            Repo root to search from.
-b, --build-runner    Run build_runner in the artifact's package after writing.
-t, --tab             A tab page name (repeatable, ≥2), e.g. -t home -t profile.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
