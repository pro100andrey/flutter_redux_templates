#!/bin/sh
# frx installer — macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/pro100andrey/flutter_redux_templates/main/tools/scripts/install.sh | sh
#
# Detects the platform, downloads that release's archive from GitHub, verifies it
# against the release's `checksums.txt`, and puts `frx` in ~/.frx/bin.
#
# Options (after `| sh -s --`, or directly when the file is run):
#   --version <x.y.z>   a specific release instead of the latest
#   --dir <path>        install somewhere other than ~/.frx/bin
#   --no-modify-path    do not touch the shell profile (PATH, and completions)
#
# Environment equivalents: FRX_VERSION, FRX_INSTALL_DIR, FRX_NO_MODIFY_PATH=1.
#
# Linux means a glibc one: the binary is built against glibc, and a musl system
# (Alpine) is refused up front rather than handed a binary that cannot start.
#
# POSIX sh, not bash: this runs on whatever /bin/sh is — dash on Debian and
# Ubuntu, busybox ash in a slim image. No arrays, no `local`, no `[[`.
# tools/scripts/test/install_sh_test.sh runs it end to end under each of them.
set -eu

REPO='pro100andrey/flutter_redux_templates'
INSTALL_DIR="${FRX_INSTALL_DIR:-$HOME/.frx/bin}"
VERSION="${FRX_VERSION:-}"
MODIFY_PATH=1
[ -n "${FRX_NO_MODIFY_PATH:-}" ] && MODIFY_PATH=0

# ---------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
err() { printf 'frx: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "'$1' is required and was not found"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; [ -n "$VERSION" ] || err '--version needs a value'; shift 2 ;;
    --dir)     INSTALL_DIR="${2:-}"; [ -n "$INSTALL_DIR" ] || err '--dir needs a value'; shift 2 ;;
    --no-modify-path) MODIFY_PATH=0; shift ;;
    -h|--help)
      # Spelled out rather than extracted from the comment header above: piped
      # into `sh` there is no `$0` to read the header out of.
      cat <<EOF
frx installer — macOS and Linux.

  --version <x.y.z>   install a specific release (default: the latest)
  --dir <path>        install location (default: \$HOME/.frx/bin)
  --no-modify-path    do not touch the shell profile: neither PATH nor completions

Environment: FRX_VERSION, FRX_INSTALL_DIR, FRX_NO_MODIFY_PATH=1
EOF
      exit 0 ;;
    *) err "unknown option: $1" ;;
  esac
done

# Absolute before anything records it. The directory is written into a shell
# profile, and `export PATH="relbin:$PATH"` there resolves against whatever
# directory each new shell happens to start in — which is almost never the one
# the installer ran from.
case "$INSTALL_DIR" in
  /*) ;;
  *) INSTALL_DIR="$(pwd)/$INSTALL_DIR" ;;
esac

# --- platform ---------------------------------------------------------------

# The names here are the ones the release workflow builds under; a platform that
# does not map is a platform with no asset, and saying so beats a 404 from curl.
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  MINGW*|MSYS*|CYGWIN*)
    err 'this script is for macOS and Linux — on Windows run install.ps1:
  irm https://raw.githubusercontent.com/'"$REPO"'/main/tools/scripts/install.ps1 | iex' ;;
  *) err "unsupported OS: $(uname -s)" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x64 ;;
  *) err "unsupported architecture: $(uname -m)" ;;
esac

# The Linux binary links glibc — it is compiled in Dart's Debian image, and
# `dart compile exe` has no static or musl target. On a musl system (Alpine, and
# the slim CI images built on it) the loader it names does not exist, so it
# installs, prints ✓, and then every run fails with `frx: not found` — about a
# file that is plainly there. Refused here, before anything is downloaded.
#
# Two probes, because either can be absent: the musl loader under /lib is what
# the binary would actually be missing the counterpart of, and `ldd --version`
# names its libc (on stderr, with a nonzero exit, when it is musl's).
is_musl() {
  for loader in /lib/ld-musl-*; do
    [ -e "$loader" ] && return 0
  done
  command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl
}

if [ "$OS" = linux ] && is_musl; then
  err "this system uses musl libc (Alpine?), and frx's Linux build needs glibc — it would install and then fail to start.
  Use a glibc-based system or image (Debian, Ubuntu, Fedora, ...)."
fi

need curl
need tar

# `shasum` on macOS, `sha256sum` on most Linux — one of the two is always there,
# and skipping verification because neither is would defeat the point.
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CHECK='sha256sum -c'
elif command -v shasum >/dev/null 2>&1; then
  SHA_CHECK='shasum -a 256 -c'
else
  err 'neither sha256sum nor shasum found — cannot verify the download'
fi

# --- which release ----------------------------------------------------------

if [ -z "$VERSION" ]; then
  # The redirect that /releases/latest performs, rather than the JSON API:
  # unauthenticated api.github.com allows 60 requests an hour per IP, which a
  # shared office address or a CI runner can exhaust, and the failure would land
  # on whoever installed next. The redirect has no such budget.
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null)" \
    || err "could not reach github.com to resolve the latest release"
  VERSION="${latest_url##*/tag/v}"
  case "$VERSION" in
    "$latest_url"|'') err "could not parse a version out of '$latest_url' — pass --version <x.y.z>" ;;
  esac
fi
VERSION="${VERSION#v}"

ASSET="frx-$VERSION-$OS-$ARCH.tar.gz"
# Overridable so the script can be pointed at an internal mirror of the release
# assets — and so its own test, tools/scripts/test/install_sh_test.sh, can serve
# a synthetic release over localhost, which is the only way to exercise the
# download, checksum and unpack path without publishing something.
BASE="${FRX_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/v$VERSION}"

# --- download & verify ------------------------------------------------------

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t frx)"
# Covers the error paths too, which is the point: a failed checksum should not
# leave half a download in /tmp for someone to find and trust later.
trap 'rm -rf "$TMP"' EXIT INT TERM

say "frx $VERSION · $OS-$ARCH"
say "  ↓ $ASSET"
curl -fsSL --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET" \
  || err "no asset '$ASSET' in release v$VERSION — see https://github.com/$REPO/releases/tag/v$VERSION"
curl -fsSL --retry 3 -o "$TMP/checksums.txt" "$BASE/checksums.txt" \
  || err "release v$VERSION has no checksums.txt — refusing to install an unverified binary"

# Verify only the line naming our asset: checksums.txt covers every platform's
# archive plus the VSIX, and `-c` on the whole file fails on the files we did not
# download. The grep also fails when the asset is absent from the manifest, which
# is exactly the case worth failing on.
grep " \{1,2\}\*\{0,1\}$ASSET\$" "$TMP/checksums.txt" > "$TMP/expected.sha256" \
  || err "$ASSET is not listed in checksums.txt"
( cd "$TMP" && $SHA_CHECK expected.sha256 >/dev/null 2>&1 ) \
  || err "checksum mismatch for $ASSET — the download is corrupt or tampered with"
say '  ✓ checksum'

# --- install ----------------------------------------------------------------

tar -xzf "$TMP/$ASSET" -C "$TMP"
[ -f "$TMP/frx" ] || err "the archive did not contain 'frx'"

mkdir -p "$INSTALL_DIR"
# `./bin` and `../x` made plain — the path is printed and written to a profile.
INSTALL_DIR="$(CDPATH='' cd -- "$INSTALL_DIR" && pwd)"
chmod 755 "$TMP/frx"
# `mv` over a running binary fails on some filesystems and, worse, an in-place
# overwrite corrupts a process that is mid-read. Replacing the directory entry
# atomically leaves any running frx on the old inode, finishing normally.
mv -f "$TMP/frx" "$INSTALL_DIR/frx.new"
mv -f "$INSTALL_DIR/frx.new" "$INSTALL_DIR/frx"

# macOS quarantines anything curl wrote, and Gatekeeper then refuses to run it
# with a dialog that says the binary is damaged. The attribute is ours to drop:
# we are the ones who fetched it, and we verified the hash.
if [ "$OS" = macos ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/frx" 2>/dev/null || true
fi

say "  → $INSTALL_DIR/frx"

# --- PATH -------------------------------------------------------------------

on_path() {
  case ":$PATH:" in *":$INSTALL_DIR:"*) return 0 ;; *) return 1 ;; esac
}

# The login shell's name, or empty.
#
# `${SHELL:-}` and not `$SHELL`, because `set -u` turns an unset one into a fatal
# error — and unset is normal in exactly the environments this script is fetched
# into: a Docker image, an Alpine CI container, anything that runs it as a
# non-login process. The binary was already installed by the time this runs, so
# the failure landed after the useful work, leaving PATH unconfigured and an exit
# code that looked like the install itself had failed.
shell_name() {
  name="${SHELL:-}"
  printf '%s' "${name##*/}"
}

# The one file this user's shell reads at startup, and the only file the
# installer writes to — the PATH line and the completions line both go here.
#
# bash is the case with a wrong answer in each direction. It reads .bashrc only
# in an interactive shell that is *not* a login shell, and in a login shell
# reads the first of .bash_profile, .bash_login and .profile that exists — that
# one alone. So:
#   - macOS: Terminal.app and iTerm open login shells, which never read .bashrc.
#     A line there is a line nobody runs.
#   - Linux: terminals open non-login shells, which read .bashrc; the
#     distributions' login files source it. Without a .bashrc, the login file
#     bash already reads — and never a new .bash_profile, which would take
#     precedence over the user's .profile and silently drop every PATH entry in
#     it.
# Either way a login file is created only when there is none at all: the
# platform's own default, .bash_profile on macOS, .profile elsewhere.
profile_for_shell() {
  case "$(shell_name)" in
    zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
    bash)
      if [ "$OS" = linux ] && [ -f "$HOME/.bashrc" ]; then
        printf '%s' "$HOME/.bashrc"
        return
      fi
      for login in .bash_profile .bash_login .profile; do
        [ -f "$HOME/$login" ] && { printf '%s' "$HOME/$login"; return; }
      done
      if [ "$OS" = macos ]; then
        printf '%s' "$HOME/.bash_profile"
      else
        printf '%s' "$HOME/.profile"
      fi ;;
    *)    printf '%s' "$HOME/.profile" ;;
  esac
}

export_line() {
  if [ "$(shell_name)" = fish ]; then
    printf 'fish_add_path %s' "$INSTALL_DIR"
  else
    # shellcheck disable=SC2016  # `$PATH` is meant to stay literal: this line is
    # written into a shell profile, where it is expanded, not here.
    printf 'export PATH="%s:$PATH"' "$INSTALL_DIR"
  fi
}

if on_path; then
  say ''
  say "✓ frx $VERSION installed — run 'frx --help'"
elif [ "$MODIFY_PATH" = 0 ]; then
  say ''
  say "✓ frx $VERSION installed, but $INSTALL_DIR is not on your PATH. Add it:"
  say "    $(export_line)"
else
  profile="$(profile_for_shell)"
  # Idempotent by marker, not by grepping for the export itself: the line is
  # cosmetically different per shell, and re-running the installer is the normal
  # way to upgrade.
  if [ -f "$profile" ] && grep -q '# added by frx installer' "$profile" 2>/dev/null; then
    say ''
    say "✓ frx $VERSION installed — open a new terminal, or: $(export_line)"
  else
    mkdir -p "$(dirname "$profile")"
    {
      printf '\n# added by frx installer\n'
      export_line
      printf '\n'
    } >> "$profile"
    say "  → PATH updated in $profile"
    say ''
    say "✓ frx $VERSION installed — open a new terminal, or: $(export_line)"
  fi
fi

# --- Completions ------------------------------------------------------------
#
# `frx completions <shell>` prints the script; this wires it in, because a
# completion script nobody sources completes nothing. Under the same flag as
# the PATH edit — both are "touch my shell profile" — and idempotent by its own
# marker, so re-running the installer to upgrade adds nothing twice, and an
# install that predates this block gains it on the next run.

# The line a profile runs to load the script, for the shells frx has one for.
# `eval` rather than `source <(…)`: process substitution is bash and zsh only,
# and `eval` reads the same in both. Guarded on `command -v` so a profile
# outlives an uninstall without printing an error at every new shell.
completion_line() {
  # shellcheck disable=SC2016  # `$(frx …)` is meant to stay literal: it runs in
  # the profile, not here.
  case "$(shell_name)" in
    zsh)  printf 'command -v frx >/dev/null 2>&1 && eval "$(frx completions zsh)"' ;;
    bash) printf 'command -v frx >/dev/null 2>&1 && eval "$(frx completions bash)"' ;;
    *)    printf '' ;;
  esac
}

if [ "$MODIFY_PATH" = 1 ]; then
  case "$(shell_name)" in
    fish)
      # fish loads completions from a directory, by name — no profile line.
      fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
      mkdir -p "$fish_dir"
      if "$INSTALL_DIR/frx" completions fish > "$fish_dir/frx.fish" 2>/dev/null; then
        say "  → completions in $fish_dir/frx.fish"
      fi
      ;;
    zsh|bash)
      profile="$(profile_for_shell)"
      if [ -f "$profile" ] && grep -q '# frx completions' "$profile" 2>/dev/null; then
        :
      else
        mkdir -p "$(dirname "$profile")"
        {
          printf '\n# frx completions\n'
          completion_line
          printf '\n'
        } >> "$profile"
        say "  → completions in $profile"
      fi
      ;;
  esac
fi

say ''
say 'The VSCode extension (search "FRX" in the Marketplace) finds this binary'
say 'even when the editor was launched from the Dock and has a different PATH.'
