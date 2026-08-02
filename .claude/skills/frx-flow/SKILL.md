---
name: frx-flow
description: >-
  What actually happens when the user taps something, how the screens
  connect, or refreshing the generated flow docs. Answered by `frx flow`
  (alias `fl`).
---

# `frx flow`

Diagram use cases and navigation (mermaid) from the AST.

```
frx flow <page> | frx flow --routes | --md
```

## Before you run it

- `--md` writes `docs/flows/`; `--check` verifies it is current and exits 1
  when not. Never hand-edit that folder.

## Flags

```
-h, --help      Print this usage information.
    --routes    Diagram the whole app: every screen and the navigation between them, instead of one page.
    --md        Export every diagram to docs/flows/ as markdown.
    --check     With --md: verify the export is up to date instead of writing it. Exits 1 when it is not (for CI).
    --json      Emit the raw flow model as JSON (the VSCode viewer consumes it).
    --root      Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
