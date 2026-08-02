---
name: frx-add-widget
description: >-
  A reusable piece of UI in the `ui` package — an input, a button, a tile,
  a container. Wired by `frx add-widget` (alias `aw`). Do NOT hand-write
  this artifact or edit the files it wires — run the command.
paths:
  - "ui/lib/**/*.dart"
---

# `frx add-widget`

Scaffold a widget (+ its previews) in the ui package.

```
frx add-widget <name> --dir <folder> [-k <kind>]
```

## What a widget is here — `ui` is data-driven

A widget draws what it is handed and decides nothing. It does not fetch, derive,
look up or branch on the domain. Its inputs are data and callbacks: primitives,
a `ui`-local render model, `FieldVm` / `ChoiceVm`.

This is a boundary, not a preference. `ui` depends on neither `models` nor
`business`, so a domain type cannot even be named in this package — the
conversion happens in the connector, the one place that sees both sides.

```dart
class InputFormField extends StatelessWidget {
  const InputFormField({required this.vm, this.labelText, super.key});

  final FieldVm<String?> vm;
  final String? labelText;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: vm.value,
    validator: vm.validator,
    onChanged: vm.onChanged,
    decoration: InputDecoration(labelText: labelText),
  );
}
```

`FieldVm` is what makes that possible: the value, its `onChanged`, an optional
validator and a server-side error arrive as one object, and its `props` omit the
closures so the view-model above can still compare equal between builds.

**Text: chrome is looked up, content arrives resolved.** A widget's own fixed
label may come from `S.current`, because `ui` does depend on `localization`.
Anything that depends on the domain or the data — an option's label, a formatted
date, a pluralised count — arrives as a finished `String`, resolved in the
connector where the locale and the domain both live. `ChoiceItemVm.label` puts it
in one line: *label is data, not design*.

Every widget is scaffolded with previews into a mirrored tree under
`ui/lib/previews/`, which is what gives it a name and a rendering anything else
can reach:

```dart
@AppPreview(name: 'primary', group: 'Button')
Widget buttonPrimaryPreview() =>
    Button.primary(label: 'Primary', onPressed: () {});
```

## Before you run it

- `--dir` is required and open-ended: a name that does not exist creates
  the folder. Ask `frx list-widget-dirs` which already hold widgets instead
  of inventing a home.
- Previews are scaffolded alongside into a mirrored tree, so a widget moved
  or deleted by hand leaves its preview behind.
- `-k` picks what it takes in: `field` takes a `FieldVm`, `choice` a
  `ChoiceVm`, `action` is a labelled button, `view` draws a render model,
  `container` wraps children.
- A component with its own lifecycle earns a file in a family folder —
  never a private `StatefulWidget` inside a page. Hidden there it has no
  preview and no name anything else can reach, so the next screen that
  needs it copies it instead. There is not one in the package.

## Flags

```
-h, --help                    Print this usage information.
    --dry-run                 Show the planned changes without writing.
-f, --force                   Overwrite existing files.
    --[no-]format             Run `dart format` on the changed files.
                              (defaults to on)
    --json                    Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root                    Repo root to search from.
-k, --kind                    What the widget takes in, and which primitive it wraps.

          [field]             Takes a FieldVm; wraps InputFormField.
          [choice]            Takes a ChoiceVm; wraps ChoiceFormField.
          [action]            A labelled action; wraps Button.
          [view] (default)    Draws a render model; the tap handler stays a parameter.
          [container]         Wraps other widgets; takes a child.

    --dir                     Folder under ui/lib/ to write into, e.g. inputs. Required — a new name creates the folder. Completion lists the ones in use.
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
