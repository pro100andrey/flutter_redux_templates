---
name: asyncredux-in-this-template
description: >-
  How async_redux is actually used in this monorepo, where it diverges from the
  library's own documentation, and the pieces no `frx` command owns —
  dispatching, waiting, user-facing errors, persistence and injected
  dependencies. Use before writing the body of a reducer, a connector or a state
  class, and whenever recalled async_redux knowledge is about to be applied
  here.
---

# async_redux, as this template uses it

## Five places the library's docs point the wrong way

| Stock async_redux | Here |
| --- | --- |
| an immutable class with its own `copy()` | `@freezed`, and `state.copyWith.<slice>(…)` for a nested write |
| `extends ReduxAction<AppState>` | `extends Action` — it mixes in `Selectors` and types `deps` and `env` |
| selector functions memoised with `cache1` / `cache2` | a facade of `extension type`s over `AppState`, zero-cost, nothing to memoise |
| `VmFactory` / `Vm` written however | `_Factory` / `_Vm`, private, in the connector file, `with Selectors` |
| `List` / `Map` in state | `IList` / `IMap` / `ISet` |

Everything below is the part no command scaffolds.

## Dispatching

- `dispatchSync` — a synchronous reducer. Setters from a connector use this.
- `dispatchAndWait` — returns the `ActionStatus`; await it when the next step
  depends on whether the action succeeded.
- `dispatch` — fire and forget, including `GoAction` for navigation.

Navigation is itself an action (`GoAction.push` / `replace` / `navigate` / `pop`
/ `popUntilRoot`), so it is observable and testable like any other, and
connectors never poke the router.

## Waiting

`Wait` is a field on `AppState`, owned by async_redux. An action opts in with the
`WaitingAction` mixin, which raises the barrier in `before()` and clears it in
`after()`. The reader is a selector keyed on the action type:

```dart
bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();
```

`frx add-action -k waiting` writes both. Never reduce `wait` yourself.

## Errors the user should see

Throw `UserException` from a reducer and async_redux shows it. `store.dart`
installs a `GlobalErrorObserver` that logs, wraps anything else into a
`UserException`, and gives the app a first chance to translate through a
`UserErrorWrapperHandler` returning a `LocalizedMessage` (title + message) — so a
message can be localised without `business` depending on the app's locale.

## Persistence

`AppPersistor` (`business/lib/persistor.dart`) is a `Persistor<AppState>` over
`KeyValueStorage` from `storage`. Boot goes through `createStore`: open storage,
read the persisted state, fall back to `AppState.initial()`. The app layer never
touches the storage backend. A persistor rebuilds state without dispatching,
which is why `frx graph` gives it a node of its own.

## Injected dependencies and environment

`AppDependencies` is built once by the store and reaches a reducer as `deps` on
the `Action` base; `Environment` (base URL, prod/dev) reaches it as `env`. Both
are already typed there — reading `store.dependencies` and casting is the long
way round.

## What this template does not use

Undo/redo, stream and timer actions, the provider integration, flutter_hooks,
events, `abortDispatch`, the optimistic-update mixin, and async_redux's testing
helpers — the template ships no test harness at all. If a task genuinely needs
one of these it is new ground here, not an established pattern: say so rather
than adopting it silently.
