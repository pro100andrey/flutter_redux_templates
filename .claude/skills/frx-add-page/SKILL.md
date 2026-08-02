---
name: frx-add-page
description: >-
  A new screen and the route that reaches it. Wired by `frx add-page`
  (alias `ap`).
---

# `frx add-page`

Scaffold a page + connector and wire the route into AppRouter (AST).

```
frx add-page <name>
```

## Before you run it

- It wires the page, its `@RoutePage()` connector, the `AutoRoute` entry
  and auth-area membership (`--public`). Navigation **to** it is a separate
  decision — that is `add-nav`.
- `--param name:type` becomes both a `/:name` path segment and a
  constructor field.

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
    --public          Page is reachable while logged out — add its route to the auth guard's _authArea set.
-p, --param           Typed route param "name:type" (repeatable), e.g. -p id:int. Becomes a /:name path segment + a constructor field.
    --path            Route path. Defaults to /<dash-name> plus a /:p per --param.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
