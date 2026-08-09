---
name: data-driven-widgets
description: >-
  How a widget is built and fed in this monorepo — composed from the package's
  parts, handed a view-model rather than state, compared on what the user can
  see, and written in Dart's dot shorthand. Use before writing or changing any
  widget in `ui`, any `_Vm` / `fromStore` in a connector, or a list of anything;
  when deciding where a widget belongs or whether to make one private; and
  whenever a widget is about to be handed a domain object, a `Store`, or a
  `BuildContext` lookup instead of data. Do NOT write a widget from recalled
  Flutter habits without it.
---

# Widgets are handed data, and nothing else

```
AppState  ──_Factory.fromStore()──>  _Vm  ──builder──>  dumb widget
```

**The state does not cross the second arrow.** The connector reads the store and
produces finished values; the widget draws them. A widget that takes a `Task`, a
`Store`, an `AppState`, or reaches for one through `context` has moved the seam,
and every rule below stops holding at once.

The whole chain, in three fragments:

```dart
// ui/lib/<family>/task_tile.dart — the widget and its render model,
// together. `frx list-widget-dirs` says which families exist.
final class TaskTileVm extends Equatable {
  const TaskTileVm({required this.title, required this.due, this.onTap});

  final String title;
  final String due;              // already formatted — see "Text", below
  final VoidCallback? onTap;     // null when the row does not react

  @override
  List<Object?> get props => [title, due, onTap != null];
}

final class TaskTile extends StatelessWidget {
  const TaskTile({required this.vm, super.key});

  final TaskTileVm vm;

  @override
  Widget build(BuildContext context) => AppCard(
    child: InkWell(
      onTap: vm.onTap,
      child: Row(
        crossAxisAlignment: .start,
        children: [Text(vm.title), Text(vm.due)],
      ),
    ),
  );
}
```

```dart
// app/lib/connectors/tasks_page_connector.dart — the seam.
class _Factory extends VmFactory<AppState, TasksPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    tiles: [
      for (final task in tasks.visible)
        TaskTileVm(
          title: task.name,
          due: S.current.dueOn(task.dueAt),
          onTap: task.isOpen ? () => dispatch(OpenTaskAction(task.id)) : null,
        ),
    ],
  );
}

class _Vm extends Vm {
  _Vm({required this.tiles}) : super(equals: [tiles]);

  final List<TaskTileVm> tiles;
}
```

```dart
// ui/lib/pages/tasks_page.dart — it takes render models, and decides nothing.
final List<TaskTileVm> tiles;
…
itemBuilder: (_, index) => TaskTile(vm: tiles[index]),
```

The domain `Task` appears once, inside `fromStore`, and never leaves `app`.

## Where each piece lives

| Piece | Package | Why there |
| --- | --- | --- |
| `TaskTile` — the widget | `ui` | it draws; it knows no domain |
| `TaskTileVm` — its render model | `ui`, **beside the widget**, public | it is the widget's own input shape |
| `_Vm` / `_Factory` — the screen's model | `app`, in the connector file, private | it is that screen's, and nothing else's |
| `Task` — the domain | `models` | `ui` never sees it |

A render model is `ui`-local and public, so a connector in `app` can build one;
a screen's `_Vm` is private, so nothing can reach into it.

## A widget is a part, and parts compose

`ui/lib/` is a folder per kind of part, and that taxonomy is the rule made
physical. **A widget that fits none of them is a sign the package is missing a
primitive**, not a sign to write a bigger widget.

**Ask which folders exist — do not take a list from here.** `frx
list-widget-dirs` answers it, and the answer moves: it reports only folders that
already hold a widget, so a folder emptied by a deletion stops being offered the
moment it stops being a home. A list written into this file was wrong within a
day of being written.

Build the new thing out of what is there. Three of the five archetypes
`frx add-widget` scaffolds do nothing else:

| `-k` | wraps |
| --- | --- |
| `field` | `InputFormField` |
| `choice` | `ChoiceFormField` |
| `action` | `Button` |
| `container` | whatever it is given — it takes a `child` |
| `view` | draws a render model, composed from the parts above |

A screen is the last composition, not the first: a page is a `Scaffold`, a list,
and a tile. It holds no layout the tile could have owned.

**The test for "is this a part": could another screen ask for it by name?** If
yes, it is a file in a family folder, whatever it looks like today.

### Which folder

The folder names what the widget **is**, and for three archetypes the CLI
already knows which one and offers it first:

| `-k` | goes in |
| --- | --- |
| `field`, `choice` | `inputs/` |
| `action` | `buttons/` |
| `container` | `containers/` |
| `view` | **no fixed home — decide** |

`view` has none on purpose: a card, a tile, a row and a header are all views,
and there is no answer that fits all of them. The card in this package lives in
`containers/app_card.dart`, so "cards go in `cards/`" is not a rule here. Run
`frx list-widget-dirs` and place the widget with the family it belongs to.

**Ask before inventing.** `--dir` is open-ended — a name that does not exist
creates the folder, in `lower_snake_case` — so the failure is not being refused,
it is quietly starting a second folder beside an established one and splitting a
family in two. Run `frx list-widget-dirs` first; create a folder only when the
widget is genuinely a new kind of part.

The folders that are not widget homes are refused outright: `theme`, `models`,
`generated`, `l10n`, `pages`.

## Private widgets are parts of one widget, not hidden components

A private widget is right when it is **its owner's own piece**, named for the
role it plays inside it, in the same file. The package has exactly two, and both
are that: `_Segment` in `buttons/segmented_control.dart` is one segment of a
segmented control; `_Content` in `containers/auth_from_container.dart` is the
heading-and-form column of that container. Neither means anything elsewhere.

It is wrong when it is something another screen would want. `ui/lib/pages/`
contains **no** private widget class, and that is not an accident: hidden in a
page, a component has no name anything else can reach, so the next screen that
needs it copies it — and then there are two, drifting.

Reach for a private class to keep one widget's `build` readable. Do not reach
for it to avoid deciding where a component belongs — that decision is
`frx add-widget <name> --dir <folder>`, and `frx list-widget-dirs` says which
folders already hold widgets.

## A value plus an `onChanged` is a `FieldVm`, not a new pair

`ui/lib/models/value_changed.dart` holds the shared input models, and a widget
that takes a value and reports changes takes one of them rather than declaring
`value` and `onChanged` side by side:

| The widget | takes |
| --- | --- |
| edits one value | `FieldVm<T>` — `value`, `onChanged`, `validator?`, `error?`, `enabled` |
| picks from a set **that is data** | `ChoiceVm<T>` — the same, plus `items` |
| picks from a set **fixed by design** | `FieldVm<T>` for the value, and its own list of options |

That last row is the line worth getting right, and `ChoiceVm`'s own doc draws
it: *use it when the set is data (loaded, localized, user-specific); when the
set is fixed by design, the widget declares it instead*. `SegmentedControl` is
the worked example — `FieldVm<T> vm` for the value and the callback,
`List<Segment<T>> segments` for the two or three options the design fixes.

Taking the pair loose costs three things at once: the `error` and `enabled`
states every input here already has, the equality that is already right
(`onChanged` and `validator` are behaviour, not display — they are out of
`props` on purpose), and the shape `frx add-widget -k field` scaffolds, which is
what every other input in the package looks like.

`ChoiceItemVm` carries a `label`, already resolved. `ui` does not localise an
option — see "Text", below.

## Equality is the part that goes wrong

A view-model that compares wrong does not crash. It redraws the screen on every
dispatch in the app, or leaves a region showing a moment that has passed — and
both read as "Flutter being slow" rather than as a bug in a list.

**Compare what the user can see. Leave out what they cannot.**

- **A value** — text, a flag, an id, a list of render models — goes in.
- **An optional callback goes in as `onTap != null`**, because whether a row
  reacts is visible. Never the callback itself: `fromStore` builds a fresh
  closure every time, so a model holding one is unequal to itself on every
  rebuild.
- **A callback that is always present is left out entirely.** `FieldVm` in
  `ui/lib/models/value_changed.dart` says why in a comment: `onChanged` and
  `validator` are *behaviour, not data*, so its props are `[value, error,
  enabled]`.

The screen's `_Vm` follows the same rule through `super(equals: [...])`: the
list of render models is compared, the callbacks are not. An empty `equals`
where there was something to compare rebuilds on every dispatch; a missing
member leaves the screen stale.

`frx doctor` reports a **value** field left out of equality
(`view-model-equality`). It never reports a callback — the audit catches the
omission, not the excess.

## Three strategies for a callback in a list

| Strategy | Shape | Use when |
| --- | --- | --- |
| **In the model, optional** | `onTap` on the Vm, `onTap != null` in props | tappability varies per row |
| **Out of the model** | `onTap` a widget parameter, rows keyed by `Vm.id` | every row means the same thing — one closure instead of N, and `const` models. What `frx add-widget -k view` scaffolds |
| **Not a callback** | the row carries an id, the composer dispatches | a row is a link, not a button |

The middle one is the default and the cheapest. Reach for the first when the
rows genuinely differ.

## Dot shorthand, wherever the type is known

Dart infers the type of a `.` expression from its context, and this package is
written that way throughout:

```dart
border: .all(color: context.colors.borderStrong),   // BorderSide.all
scrollDirection: .horizontal,                       // Axis.horizontal
mainAxisSize: .min,                                 // MainAxisSize.min
crossAxisAlignment: .start,                         // CrossAxisAlignment.start
alignment: .center,                                 // Alignment.center
fit: .cover,                                        // BoxFit.cover
value: .dark,                                       // ThemeMode.dark
```

Argument positions and typed fields have a context type, so the prefix is noise.
**Repeating it is the thing to fix, not a style preference** — `theme_switcher.dart`
writes `value: .dark` for one of this app's own enums, not only for Flutter's.

**Where it does not work**, and long form is correct: a declaration with no
context type to infer from.

```dart
static const _textPadding = EdgeInsets.symmetric(horizontal: 8);  // no type here
```

That is why `theme/radii.dart` and `theme/spacing.dart` are full of
`BorderRadius.all(...)` and `EdgeInsets.all(...)` — they are the declarations.

**And a token beats a literal, shorthand or not.** `radii.dart` exists so that
`BorderRadius.circular` is not written at every call site, so the best form is
`borderRadius: Radii.card`, not `.circular(8)`. Same for `Insets.md` over
`.all(16)`. Reach for the shorthand when there is no token for the value; reach
for the token first.

## Text: chrome is looked up, content arrives resolved

A widget's own fixed label may come from `S.current` — a page titles its own
`AppBar` that way. Anything depending on the domain or the data — an item's
title, a formatted date, a pluralised count — arrives as a finished `String`,
resolved in the connector where the locale and the domain both live.
`ChoiceItemVm.label` states it in one line: **label is data, not design**.

## Before you write one

- A widget with no `vm` is fine; a widget with a domain type in its constructor
  is the seam in the wrong place.
- `frx add-widget -k view <name> --dir <folder>` scaffolds the pair — render
  model and widget — with the equality already right. Reach for it rather than
  hand-writing the shape from this file.
- Composed from the package's parts, not from `Container` and `Padding` — and if
  there is no part for it, the part is what is missing.
- Building the model inside the widget, or in a `builder:`, is the failure this
  exists to prevent. It compiles, it draws, and it rebuilds on everything.
