# Changelog

The Marketplace renders this as the extension's **Changelog** tab.

The extension and the `frx` CLI share a version and ship on one tag — the editor
reads the CLI's contract out of generated constants, so a version pair that can
drift will. Entries here therefore cover both halves, and CLI-only changes are
marked as such.

## Unreleased

### Added

- **A one-line install for the CLI.** `install.sh` (macOS, Linux) and
  `install.ps1` (Windows) download the release for the running platform, verify
  it against the release's `checksums.txt`, and put `frx` in `~/.frx/bin`
  (`%LOCALAPPDATA%\frx\bin`). No Dart SDK required — the binary is
  self-contained, template included.
- **Native binaries per platform**, attached to every GitHub release: macOS
  arm64 and x64, Linux x64 and arm64, Windows x64. Linux builds against
  glibc 2.35, so they run on distributions a year or two behind.
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
  the repository; this is the first version prepared for the Marketplace and Open
  VSX, with the icon, categories and workspace-trust declaration a listing needs.
  See the
  [commit history](https://github.com/pro100andrey/flutter_redux_templates/commits/main/tools/vscode)
  for what came before.
