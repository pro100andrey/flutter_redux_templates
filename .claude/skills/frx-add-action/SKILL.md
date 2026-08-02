---
name: frx-add-action
description: >-
  Something that changes state — a reducer, a mutation, an async operation
  a screen dispatches. Wired by `frx add-action` (alias `aa`).
---

# `frx add-action`

Scaffold a ReduxAction into a substate.

```
frx add-action <name> --state <substate>
```

## Before you run it

- Mixins conflict, and the conflict is a **compile error**: async_redux
  makes groups mutually exclusive by colliding on a private member. Ask
  `frx list-mixins` which exclude which and let the scaffolder write the
  `with` clause — it refuses a bad pair up front.
- `-k waiting` also adds the substate's `isWaiting` getter, on the same
  ground as a field's getter: a waiting action a page cannot ask about is
  half-wired.

## Flags

```
-h, --help                                 Print this usage information.
    --dry-run                              Show the planned changes without writing.
-f, --force                                Overwrite existing files.
    --[no-]format                          Run `dart format` on the changed files.
                                           (defaults to on)
    --json                                 Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root                                 Repo root to search from.
-s, --state                                The substate to add the action to (its folder under business/lib/redux, any casing).
-k, --kind                                 Action body shape.

          [sync] (default)                 AppState? reduce() — synchronous state update.
          [async]                          Future<AppState?> reduce() async — async work.
          [waiting]                        extends Action with WaitingAction — async + wait barrier.

-m, --mixin                                async_redux behaviour mixin (repeatable). Dependencies are added automatically (noDialog → checkInternet, unlimitedRetries → retry).

          [checkInternet]                  Check connectivity first; error dialog when offline
          [noDialog]                       With checkInternet: fail without the dialog
          [abortWhenNoInternet]            Abort silently when offline
          [nonReentrant]                   Ignore a dispatch while already running
          [retry]                          Retry failures with exponential backoff
          [unlimitedRetries]               With retry: never stop retrying
          [debounce]                       Run only after a pause in dispatches
          [throttle]                       Drop dispatches while a recent run is fresh
          [fresh]                          Skip the run while the last result is still fresh
          [unlimitedRetryCheckInternet]    Retry forever, treating offline as a failure to retry

    --[no-]selector                        For --kind waiting, also add the substate's `isWaiting` getter to its Select<Pascal> in selectors.dart.
                                           (defaults to on)
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
