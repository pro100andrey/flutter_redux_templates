---
name: frx-add-action
description: >-
  Something that changes state — a reducer, a mutation, an async operation
  a screen dispatches. Wired by `frx add-action` (alias `aa`). Do NOT
  hand-write this artifact or edit the files it wires — run the command.
---

# `frx add-action`

Scaffold a ReduxAction into a substate.

```
frx add-action <name> --state <substate>
```

## What an action is here

An action is a class with a `reduce()` method. You dispatch it; the store calls
`reduce()` and replaces the state with what it returns. Returning `null` means
"no state change" — the action still ran, and observers still see it.

Actions extend **`Action`**, not `ReduxAction<AppState>`. The base lives in
`business/lib/redux/common/action.dart` and is what gives a reducer its three
tools:

```dart
abstract class Action extends ReduxAction<AppState> with Selectors {
  AppDependencies get deps => store.dependencies! as AppDependencies;
  Environment get env => store.environment! as Environment;
}
```

- `Selectors` — the selector facade, so state is read as `login.email`
- `deps` — injected services
- `env` — base URL, prod/dev

**Synchronous.** Parameters arrive through the constructor as `final` fields;
the write is freezed's nested `copyWith`:

```dart
class SetEmailAction extends Action {
  SetEmailAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.login(email: value);
}
```

**Asynchronous.** `Future<AppState?> reduce() async`, and every path must
`await`. Reads go through the facade — `login.email`, never `state.login.email`:

```dart
class LogInWithEmailAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _request(email: login.email!, password: login.password!);

    return state.copyWith(login: const LoginState());
  }
}
```

`with WaitingAction` raises a wait barrier for the duration — `before()` puts it
up, `after()` takes it down — and a screen asks about it through a selector,
`isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>()`.

**How it is dispatched**, from a connector's `_Factory`: `dispatchSync` for a
synchronous setter, `dispatchAndWait` when the next step depends on the result,
plain `dispatch` for fire-and-forget.

## Before you run it

- The suffix is optional and idempotent: `ArchiveTask` and
  `ArchiveTaskAction` scaffold the same artifact. Do not strip it yourself,
  and do not add it — pass the name as you have it. `frx remove` reads the
  same rule, so whichever spelling created it removes it.
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
          [waiting]                        extends Action with WaitingAction — async, and in `Wait` while it runs so a selector can read it. Add BlockingAction by hand for one the modal barrier should cover.

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
