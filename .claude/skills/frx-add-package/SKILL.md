---
name: frx-add-package
description: >-
  A whole workspace member is missing — `add-model` or `add-retrofit`
  refused because the package it writes into is not in this project.
  Answered by `frx add-package` (alias `apkg`).
paths:
  - "pubspec.yaml"
---

# `frx add-package`

Add an optional workspace member (models, http_client, storage).

```
frx add-package <kind>
```

## Which packages are optional

`models` and `http_client` are optional, and a project may have been created
without them. `app`, `business`, `ui` and `localization` are not — the app does
not compile without them, so there is nothing to add.

| kind | holds | written into by |
| --- | --- | --- |
| `models` | freezed models and JSON converters shared between packages | `add-model` |
| `http_client` | Dio + Retrofit clients and interceptors | `add-retrofit` |
| `storage` | key-value persistence behind `BaseKeyValueStorage` | nothing — `AppPersistor` uses it |

## What it writes

Five files and one edit, applied together or not at all: the package's
`pubspec.yaml` (with `resolution: workspace`, the line that makes it a member),
`analysis_options.yaml`, `build.yaml` where a builder runs, `.gitignore`,
`lib/.gitkeep` — and one entry spliced into the root pubspec's `workspace:`
list.

## After it runs

**`flutter pub get` from the workspace root, before anything else.** A new
member changes what pub resolves, and until it has run the package is a
directory the analyzer cannot see. That is why this command runs no codegen of
its own — build_runner needs the resolution it just invalidated.

## Before you run it

- Adding the package does not add a **dependency** on it. A package that
  wants to import `package:models/…` still needs the entry in its own
  `pubspec.yaml` — nothing writes that yet.
- Asking for a package that is already a member is not an error: it writes
  nothing and says so.

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
