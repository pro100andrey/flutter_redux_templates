# Changelog

The Marketplace renders this as the extension's **Changelog** tab.

The extension and the `frx` CLI share a version and are built on one tag — the
editor reads the CLI's contract out of generated constants, so a version pair
that can drift will. Entries here therefore cover both halves, and CLI-only
changes are marked as such.

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
