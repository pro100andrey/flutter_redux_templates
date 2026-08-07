---
name: frx-add-connector
description: >-
  Connecting a dumb widget to the store — the `StoreConnector` that builds
  its view-model. Wired by `frx add-connector` (alias `ac`). Do NOT
  hand-write this artifact or edit the files it wires — run the command.
paths:
  - "app/lib/connectors/*.dart"
---

# `frx add-connector`

Scaffold a StoreConnector for a ui widget.

```
frx add-connector <name>
```

## What a connector is here

Three classes in one file under `app/lib/connectors/`, two of them private. The
public one carries `@RoutePage()` and does nothing but wire the other two:

```dart
@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LogInPage(email: vm.email, theme: vm.theme),
  );
}
```

The factory reads the store. `with Selectors` is what lets it say `login.email`
instead of reaching into the state, and it is where a dispatch is bound to a
callback:

```dart
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    email: FieldVm(
      value: login.email,
      validator: emailValidator,
      onChanged: (v) => dispatchSync(SetEmailAction(v)),
    ),
    onPressedLogIn: () => dispatchAndWait(LogInWithEmailAction()),
    onPressedRegister: () => dispatch(GoAction.push(const RegistrationRoute())),
  );
}
```

The view-model holds what the dumb widget needs, and `equals:` names **only the
fields that carry data**:

```dart
class _Vm extends Vm {
  _Vm({required this.email, required this.onPressedLogIn})
    : super(equals: [email]);

  final FieldVm<String?> email;
  final VoidCallback onPressedLogIn;
}
```

A callback is a fresh closure every build, so listing one in `equals:` makes the
view-model unequal to itself and the connector rebuilds on every dispatch. That
is why a value and the callback that changes it travel together as `FieldVm`
(or `ChoiceVm`, when the value comes from a finite set): its `props` deliberately
omit the closures, so the value can be compared and the behaviour cannot break
the comparison.

**Which dispatch:** `dispatchSync` for a synchronous setter, `dispatchAndWait`
when the next step depends on the result, `dispatch(GoAction.push(...))` for
navigation. Connectors never touch the router directly.

This file is also the seam between the domain and the screen: `ui` depends on
neither `models` nor `business`, so an enum, a `DateTime` or a domain object
becomes a primitive, a formatted string or a `ui`-local render model **here**,
before it is handed over.

## Before you run it

- Converting a domain value here means **naming its type here**, and `app`
  does not depend on `models` out of the box — no connector in the template
  converts one. Add `models` to `app/pubspec.yaml` and run `flutter pub
  get`; `frx add-package` creates a workspace member and does not draw a
  dependency edge between two that exist.
- The suffix is optional and idempotent: `Toolbar` and `ToolbarConnector`
  scaffold the same artifact. Do not strip it yourself, and do not add it —
  pass the name as you have it. `frx remove` reads the same rule, so
  whichever spelling created it removes it.

## Flags

```
-h, --help           Print this usage information.
    --dry-run        Show the planned changes without writing.
-f, --force          Overwrite existing files.
    --[no-]format    Run `dart format` on the changed files.
                     (defaults to on)
    --json           Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root           Repo root to search from.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
