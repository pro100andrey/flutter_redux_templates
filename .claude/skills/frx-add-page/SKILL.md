---
name: frx-add-page
description: >-
  A new screen and the route that reaches it. Wired by `frx add-page`
  (alias `ap`). Do NOT hand-write this artifact or edit the files it wires
  — run the command.
---

# `frx add-page`

Scaffold a page + connector and wire the route into AppRouter (AST).

```
frx add-page <name>
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
