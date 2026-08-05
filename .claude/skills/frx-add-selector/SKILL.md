---
name: frx-add-selector
description: >-
  A value computed from state rather than stored in it — a count, a
  filtered list, a derived flag; anything a screen reads that the state
  does not hold directly. Wired by `frx add-selector` (alias `asel`). Do
  NOT hand-write this artifact or edit the files it wires — run the
  command.
paths:
  - "business/lib/redux/selectors.dart"
---

# `frx add-selector`

Add a computed getter to a substate's Select<Pascal> selector.

```
frx add-selector <substate> <name>
```

## What a selector is here

Not a function, and nothing to memoise. async_redux's own documentation teaches
selector functions cached with `cache1` / `cache2`; this template has none of
that. A selector is a getter on an `extension type` over `AppState`, so reading
one is a field access, and all of them live in a single file,
`business/lib/redux/selectors.dart`:

```dart
extension type SelectLogin(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<LogInWithEmailAction>();

  /// Returns email value
  String? get email => _state.login.email;
}
```

The facade is the `Selectors` mixin, and mixing it in is the only way in:

- a reducer, because `Action` mixes it in — `login.email`
- a connector's `_Factory`, for the same reason

There is no root type and no `state.select` hop. There were both, plus a
`Select` extension type carrying the same getter list as the mixin, and nothing
in the template ever called them — so adding a slice cost two parallel lists,
one of which was unreachable.

A value that spans slices belongs to `SelectComposites`, on the facade itself —
not inside one of the slices:

```dart
extension SelectComposites on Selectors {
  bool get canEnterApp => session.isAvailable && !login.isWaiting;
}
```

That works because `Selectors` has every slice in scope. A `SelectX` does not
reach its siblings, and in the whole template not one of them tried to.

`doctor` reports a selector declared anywhere but the facade
(`selector-outside-facade`), so the file is the convention, not a habit.

## Before you run it

- `--expr` is the getter body and defaults to reading the state field of
  the same name; `--type` tightens the return type from `Object?`. No
  codegen — selectors are hand code.
- A selector nothing reads is reported by the graph as a fact, not a
  defect: in a template it can be API for whoever builds on it.

## Flags

```
-h, --help           Print this usage information.
    --dry-run        Show the planned changes without writing.
    --diff           Print a unified diff of the change.
    --[no-]format    Run `dart format` on the changed files.
                     (defaults to on)
    --json           Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root           Repo root to search from.
-t, --type           The getter return type. Tighten it from the default.
                     (defaults to "Object?")
-e, --expr           The getter body expression. Defaults to reading the state field of the same name (`_state.<substate>.<name>`).
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
