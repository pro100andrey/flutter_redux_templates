---
name: frx-add-substate
description: >-
  A new slice of application state — a list or table of things, a search,
  or a single value the app holds onto. Wired by `frx add-substate` (alias
  `as`).
---

# `frx add-substate`

Scaffold an AsyncRedux substate and wire it into AppState (AST).

```
frx add-substate <name>
```

## What a state slice is here

The store holds one immutable `AppState`. It is never edited — a reducer returns
a new one. `AppState` is a `@freezed` class composing the slices, and every slice
has an entry in `initial()`:

```dart
@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required LoginState login,
    required ThemeState theme,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    login: LoginState(),
    theme: ThemeState(),
    wait: Wait.empty,
  );
}
```

`wait` is async_redux's own barrier registry, not a slice of this app. Leave it
alone — actions raise and clear it through the `WaitingAction` mixin.

A slice is a `@freezed` class of its own, at
`business/lib/redux/<slice>/models/<slice>_state.dart`. Every field is nullable
or carries `@Default(…)`, because the state is constructed with no arguments,
and collections are `IList` / `IMap` / `ISet` — value equality is what stops a
connector rebuilding on an identical list.

**`--kind` picks the shape**, and changing it later is a rewrite:

- `value` — one `String? value`, plus `SetValueAction`
- `search` — a `String? query` and an `IList<int> view` of results, plus
  `SetQueryAction`
- `table` — an `IMap<int, Object> table` and an `IList<int> view` over it, plus
  `Add…Action` / `Retrieve…Action`

```dart
@freezed
abstract class TodosState with _$TodosState {
  const factory TodosState({
    @Default(IMapConst<int, Object>({})) IMap<int, Object> table,
    @Default(IListConst<int>([])) IList<int> view,
  }) = _TodosState;
}
```

The slice is never read directly. The command writes its getters into the
selector facade, so a screen says `todos.view` and so does a reducer —
`_state.todos.view` appears only inside the facade itself.

## Before you run it

- The kind decides the shape: `table` for a keyed collection with an
  ordering, `search` for a query with results, `value` for one value. Ask
  which before scaffolding — changing it later is a rewrite.
- It wires the `AppState` field *and* its `initial()` entry, the selectors
  facade and the change log. What dispatches its starter actions is yours.

## Flags

```
-h, --help                     Print this usage information.
    --dry-run                  Show the planned changes without writing.
-f, --force                    Overwrite existing files.
    --[no-]format              Run `dart format` on the changed files.
                               (defaults to on)
    --json                     Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root                     Repo root to search from.
-b, --build-runner             Run build_runner in the artifact's package after writing.
-k, --kind                     Which substate flavour to scaffold.

          [value] (default)    A single nullable `value` field + SetValueAction.
          [search]             A `query` string + `IList<int> view` + SetQueryAction.
          [table]              A byId `IMap` table + view + Add…/Retrieve… actions.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
