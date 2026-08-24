# Changelog

The Marketplace renders this as the extension's **Changelog** tab.

The extension and the `frx` CLI share a version and are built on one tag — the
editor reads the CLI's contract out of generated constants, so a version pair
that can drift will. Entries here therefore cover both halves, and CLI-only
changes are marked as such.

## 0.3.3

### Fixed

- **A generated waiting action could raise the wait barrier and never lower
  it.** `add-action -k waiting -m nonReentrant` wrote `with WaitingAction,
  NonReentrant`, and Dart runs one `after()` per class — the last mixin's.
  `NonReentrant.after()` releases its own lock without calling `super.after()`,
  so the barrier stayed up: the action finished and
  `isWaitingForType<T>()` remained true for the rest of the session, leaving
  every widget that reads it disabled. The file compiled, analyzed clean and
  passed its tests. `add-action` now emits `WaitingAction` last, and the
  template's own `WaitingAction` chains `super` in both hooks — reversing the
  order alone would only have moved the loss to the reentrancy lock, which the
  regression test pins. *(CLI + template)*

### Added

- **`doctor` reports a `WaitingAction` whose cleanup never runs.** Three shapes:
  a `with` clause placing it before `nonReentrant` / `throttle` / `fresh`, an
  action overriding `before()` / `after()` without `super` (a class member beats
  the whole `with` clause), and a project `WaitingAction` declaration that does
  not chain — that file belongs to the project, so generating the clause
  correctly is not enough on its own. Errors, and not silenceable: they name
  async_redux's own mixins doing what its own source says they do. *(CLI)*
- **`list-mixins` says which mixins end the `after()` chain**, as a third note
  beside `implies` and `excludes`, and as `swallowsAfter` in `--json`. The set
  is derived from the async_redux source by the test suite rather than
  transcribed. *(CLI)*

### Changed

- **The docs no longer claim an excluded mixin pair is a compile error.**
  `_incompatible<T1, T2>` is an `assert`: `with NonReentrant, Throttle` compiles
  and analyzes clean, throws on the first dispatch in a debug build, and is
  stripped from a release one. The marker members share one library, so
  `private_collision_in_mixin_application` never applied. This makes
  `add-action` refusing the pair up front the earliest check that exists, not a
  convenience. *(CLI, docs only)*

## 0.3.2

### Fixed

- **A transition subclass was not read as a route at all.** auto_route spells a
  transition by subclassing — a sheet over the screen behind it is
  `CustomRoute(opaque: false)`, and `MaterialRoute` / `CupertinoRoute` /
  `AdaptiveRoute` pick a platform transition — and `AppRouter` was matched on
  the base class name alone. A screen registered as any of the four was
  invisible to every reader at once: `list-routes` left it out, `doctor`
  reported its connector as unregistered, `remove` could not find it, and
  `flow --md` deleted its generated document as a page that had gone.
  `RedirectRoute` and `NamedRouteDef` carry no page, so they are still not
  screens. *(CLI)*

### Changed

- **The analyzer no longer walks the build output or the platform folders.**
  `build/`, `android/`, `ios/`, `web/`, `windows/`, `macos/` and `linux/` are
  excluded in every package the template ships, and `add-package` writes the
  same set into a package it creates. *(CLI)*

## 0.3.1

### Added

- **`frx upgrade`** replaces the installed binary with the newest release —
  same redirect, same `checksums.txt` check as `install.sh`, done from the
  binary itself. `--check` reports without installing and exits 1 when an
  upgrade exists, so it can gate a command. It is the only part of frx that
  opens a socket: no background check, nothing appended to unrelated output.
  *(CLI)*

### Fixed

- **The upgrade compared versions for inequality, not order,** so a source
  build made after a version bump but before its tag was published was told to
  upgrade backwards. A pinned `--version` still installs in either direction —
  naming a version is how you go back to one. *(CLI)*
- **A mirror that labels `.tar.gz` with `Content-Encoding: gzip`** made every
  upgrade fail as "tampered with", because Dart inflates what `curl` stores
  verbatim. *(CLI)*
- **Failure paths that left a mess:** a missing `tar` crashed with a stack
  trace instead of a sentence, a failed staging copy left a truncated binary
  beside the real one, and on Windows a failed swap could leave the install
  directory with no `frx.exe` and nothing saying where it went. *(CLI)*

## 0.3.0

### Fixed

- **`frx flow` lost whole regions.** A dispatch was found only where it was
  written inside the subtree of a `_Vm(...)` argument, so a callback built by a
  member of the same factory — the shape a list row takes the moment it needs
  one — was invisible, and a region with no interaction gets no lane and leaves
  the diagram. Measured on one page: six of eleven regions missing. The walk now
  follows calls and tear-offs into the file's own functions, and refuses to
  follow a name that anything nearer binds. *(CLI)*
- **What the map does not draw is now said.** Dispatches no use case accounts
  for are counted and reported — in `--json`, in the diagram, in the exported
  markdown and in the terminal — instead of being dropped. `frx flow` and the
  markdown export also stop claiming a page "has no dispatching callbacks" when
  the truth is that none could be followed. *(CLI)*
- **`frx doctor`'s equality rule was switched off by an unrelated element.** Any
  entry in `super(equals: [...])` that was not a bare field name — an integer, a
  string, another object's `hashCode` — made the whole list unreadable, and an
  unreadable list reports nothing. Only a spread genuinely hides membership now;
  everything else is read, and a field compared only through something derived
  from it (`ids.length`) is reported as that rather than as absent. *(CLI)*

### Added

- **A one-line install for the CLI.** `install.sh` (macOS, Linux) and
  `install.ps1` (Windows) download the release for the running platform, verify
  it against the release's `checksums.txt`, and put `frx` in `~/.frx/bin`
  (`%LOCALAPPDATA%\frx\bin`). No Dart SDK required — the binary is
  self-contained, template included.
- **Native binaries per platform**, attached to every GitHub release: macOS
  arm64 and x64, Linux x64 and arm64, Windows x64. The Linux ones are built
  inside Dart's own `dart:stable` image — Debian bookworm, glibc 2.36 — rather
  than on the runner, whose glibc is always the newest thing GitHub hosts and
  would refuse to start on anything a year behind. Debian 12, Ubuntu 24.04 and
  Fedora 38 upwards; below that, build from source with `dart install`.
- **The extension finds an installed binary in `~/.frx/bin`.** It already
  searched `PATH` and `dart install`'s directory as *files* rather than spawning
  a bare name; the installer's directory joins them, because the `PATH` line it
  adds to your shell profile is exactly what a Dock- or Start-menu-launched
  editor never reads. `dart install`'s directory is still searched first: on a
  machine with both, the locally built binary belongs to somebody working on frx
  itself.

### Changed

- **"Could not find the frx CLI" now leads with the download.** It used to say
  `dart install .` in `tools/`, which is a dead end for anyone who arrived from
  the Marketplace and has no checkout.

## 0.2.0

- Everything up to this point. The extension was distributed as a `.vsix` from
  the repository; this is the first version prepared for the Marketplace, with
  the icon, categories and workspace-trust declaration a listing needs. See the
  [commit history](https://github.com/pro100andrey/flutter_redux_templates/commits/main/tools/vscode)
  for what came before.
