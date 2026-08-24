# Changelog

The Marketplace renders this as the extension's **Changelog** tab.

The extension and the `frx` CLI share a version and are built on one tag — the
editor reads the CLI's contract out of generated constants, so a version pair
that can drift will. Entries here therefore cover both halves, and CLI-only
changes are marked as such.

## 0.3.4

### Fixed

- **`graph` no longer calls a selector dead because its reader holds the facade
  in a variable.** The chain rule counted `chats.unreadTotal` when the receiver
  heads the chain — how a class mixing in `Selectors` reaches one — and refused
  any segment in front of it except the literal `select` of the spine that no
  longer exists. A file that does `final s = _Reader(state); s.chats.unreadTotal`
  was therefore read, scanned and not counted, so a selector only it reads came
  back on the list frx uses to say "you can delete this". On a real project that
  was the application's tray icon, and the one false positive left in the list.
  A receiver is now judged by *type*: a class with `Selectors` in its `with`
  clause is the facade, and so is a variable, field or parameter holding one, or
  the type where the facade is built in place. Not "any receiver" — a substate's
  field and its selector are spelled the same, so that would have read
  `state.session.token` as a selector and hidden every genuinely dead one behind
  the substate it reads. Measured on the same project: five edges gained, none
  lost. *(CLI)*

- **`remove --kind selector` takes the imports the getter was the last reason
  for.** The splice pruned only the imports a table knew about, so a getter's
  own went on standing: the action file behind
  `_state.wait.isWaitingForType<LoadContactsAction>()`, and a package that
  supplied one return type. Two `unused_import`s in a file under the placement
  guard, repaired by the hand edit the command exists to avoid — and a facade
  imports one write-layer file per waiting getter, so this is the ordinary case.
  Which imports are still needed is now read rather than looked up: a URI
  resolves to a file, a file declares names and hands on what it exports, and a
  name in the surviving source keeps the import. Three things it takes to be
  right rather than merely safe — uses are read off the tree, so a word in prose
  is not one; a type is not an identifier on that tree; and a name can have two
  suppliers, so an import goes only when every name it still answers for is
  answered by an import that stays, which is `unused_import`'s own rule.
  Anything unreadable keeps the import. The same pass runs when a whole
  substate's selectors are unwired. Replayed against a real cleanup of nine
  selectors, the import list frx leaves is now the one that was fixed by hand.
  *(CLI)*

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

- **`graph` no longer calls a dispatched action an orphan.** The orphan list is
  the one place frx says "you can delete this", and it was reading dispatches
  out of the routed page walk, which draws an edge only where a dispatch is
  written as a named argument of `_Vm(...)`. Four ordinary shapes fell outside
  it: `onInit:` on the `StoreConnector`, a callback built in `builder:`, any
  connector no route registers (the `MaterialApp.builder` tree), and
  `StoreProvider.dispatch(context, X)` — whose action is the *second* argument,
  so the `BuildContext` was read as the thing dispatched. Two more came from
  the action reader: it took cascades from `reduce()` only, so a dispatch in
  `before()` / `after()` / a mixin's required override was invisible, and it
  *assigned* rather than appended per `reduce()` it met, so in a file with two
  action classes the second erased the first's. Dispatches are now swept from
  every file of the app's own packages — the rule the selector half of the same
  reader already applied, and states in a comment. Measured on a real project:
  eleven reported orphan actions, none of them dead. *(CLI)*

### Added

- **`graph` says when a whole connector is dead, instead of listing its
  actions.** A connector now has a node and a `builds` edge, so "no file
  constructs it" is a verdict frx can reach: on a real project six of eleven
  reported orphan actions were dispatched only from a `SettingsConnector` that
  nothing builds. Composition is matched on the class name rather than on a
  `*_connector.dart` import, because the file that constructs the app's root
  widget is not itself a connector — resolving through the import pattern
  called `AppConnector` unbuilt. In-degree, not reachability from a root: frx
  does not know which widget the root is, and being wrong about that would
  report a live screen as dead. *(CLI)*
- **`doctor` reports two selectors with one body.** What is left after
  `add-selector` correctly declines a taken name and the reader is added by
  hand under another: both are right, and together they are one fact under two
  names that the next change has to find twice. A warning, and
  character-for-character — two getters that compute the same thing differently
  are a judgement call frx has no business making. *(CLI)*
- **`remove --kind selector`.** `add-selector` had no inverse, and
  `selectors.dart` is under the placement guard, so the way out was a hand edit
  to a file frx complains about being hand-edited. Takes the address `graph` and
  `doctor` print (`SelectTheme.isWaiting`) or the bare name with `--state`, and
  refuses while another getter on the facade reads it. *(CLI + extension)*
- **`list-mixins` lists the mixins the project declares**, with the hooks each
  overrides and whether it passes the chain on — `WaitingAction` is the mixin in
  this architecture that must go last, and the command whose job is to say what
  combines with what could not see it. `--root` had been accepted and ignored;
  this is what it is for. *(CLI)*
- **The mixin-order rule is no longer only about `WaitingAction`.** An action
  that overrides `after()` without `super` in front of `NonReentrant` leaks the
  reentrancy key just as surely, with no barrier involved. Which hooks a mixin
  overrides is now derived from the async_redux source alongside the rest.
  *(CLI)*

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

- **The docs say what actually enforces an excluded mixin pair**, after
  measuring rather than reading: `dart analyze` reports
  `private_collision_in_mixin_application`, and the compiler does not — the pair
  builds, so a test file the gate rejects still runs and async_redux's `assert`
  throws on the first dispatch of a debug build. An intermediate version of this
  note claimed the collision did not apply at all; it does. Pinned by
  `business/test/mixin_exclusion_test.dart`, since `tools` cannot import
  async_redux to check it. *(CLI, docs only)*

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
