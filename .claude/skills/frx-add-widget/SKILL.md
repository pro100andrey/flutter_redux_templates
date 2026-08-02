---
name: frx-add-widget
description: >-
  A reusable piece of UI in the `ui` package — an input, a button, a tile,
  a container. Wired by `frx add-widget` (alias `aw`).
---

# `frx add-widget`

Scaffold a widget (+ its previews) in the ui package.

```
frx add-widget <name> --dir <folder> [-k <kind>]
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
