---
name: frx-add-field
description: >-
  A piece of data a state slice does not hold yet — the slice already
  exists and needs one more field on it. Also the shape of a slice you just
  created: each field is one of these, not a file you open and type. Wired
  by `frx add-field` (alias `af`). Do NOT hand-write this artifact or edit
  the files it wires — run the command.
paths:
  - "business/lib/redux/*/models/*_state.dart"
---

# `frx add-field`

Add a field to an existing substate state (+ optional setter action).

```
frx add-field <substate> <name:type>
```

## What a field is here

A field belongs to a slice's `@freezed` class. Adding one is three coordinated
edits, and the command makes all three.

**1. The factory**, spliced in via AST. A field is either nullable or carries
`@Default(…)`, because the state is constructed with no arguments:

```dart
const factory TodosState({
  @Default(IMapConst<int, Object>({})) IMap<int, Object> table,
  @Default(IListConst<int>([])) IList<int> view,
  DateTime? dueAt,
}) = _TodosState;
```

A collection field is `IList` / `IMap` / `ISet`, and the import comes with it.
`List` / `Map` compare by identity, so a connector would rebuild on an identical
list.

**2. The getter on the facade**, so anything can read the field without knowing
where it sits:

```dart
/// Returns dueAt
DateTime? get dueAt => _state.todos.dueAt;
```

`--no-selector` skips it. Rarely what you want: a field a connector cannot read
is half-wired, and it is this getter that makes the read visible to `frx graph`.

**3. A setter action**, with `--action` — positional constructor, `final` field,
and freezed's nested `copyWith`:

```dart
class SetDueAtAction extends Action {
  SetDueAtAction(this.dueAt);

  final DateTime? dueAt;

  @override
  AppState reduce() => state.copyWith.todos(dueAt: dueAt);
}
```

That `state.copyWith.<slice>(<field>: …)` form is how every write to a slice is
spelled — not `state.copyWith(todos: state.todos.copyWith(…))`.

## Before you run it

- The field is spliced into the `@freezed` factory via AST. A non-nullable
  type **requires** `--default`, because a state is constructed with no
  arguments.
- It also writes the `Select…` getter, unless `--no-selector`. A field a
  connector cannot read is half-wired — which is why hand-writing the field
  means hand-writing the facade too, and usually forgetting it.
- `IList` / `IMap` / `ISet` types auto-import `fast_immutable_collections`.
  `--action` scaffolds the `Set<Field>Action` setter and never clobbers an
  existing one.

## Flags

```
-h, --help             Print this usage information.
    --dry-run          Show the planned changes without writing.
    --diff             Print a unified diff of the change.
    --[no-]format      Run `dart format` on the changed files.
                       (defaults to on)
    --json             Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root             Repo root to search from.
-b, --build-runner     Run build_runner in the artifact's package after writing.
-d, --default          A `@Default(<expr>)` for the field. Required for a non-nullable type (a state field must be nullable or defaulted).
-a, --action           Also scaffold a Set<Field>Action setter in the substate.
-f, --force            When the field already exists, rewrite its declaration to this type (and its selector getter to match).
    --[no-]selector    Also add a getter for the field to the substate's Select<Pascal> in selectors.dart.
                       (defaults to on)
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
