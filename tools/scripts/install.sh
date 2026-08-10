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
#   --no-modify-path    do not touch the shell profile
#
# Environment equivalents: FRX_VERSION, FRX_INSTALL_DIR, FRX_NO_MODIFY_PATH=1.
#
# POSIX sh, not bash: this runs on whatever /bin/sh is, including Alpine's ash
# inside a CI container. No arrays, no `local`, no `[[`.
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
  --no-modify-path    do not add the install directory to the shell profile

Environment: FRX_VERSION, FRX_INSTALL_DIR, FRX_NO_MODIFY_PATH=1
EOF
      exit 0 ;;
    *) err "unknown option: $1" ;;
  esac
done

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
# assets — and so its own test can serve a synthetic release over localhost,
# which is the only way to exercise the download, checksum and unpack path
# without publishing something.
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

profile_for_shell() {
  case "$(shell_name)" in
    zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) [ -f "$HOME/.bashrc" ] && printf '%s' "$HOME/.bashrc" || printf '%s' "$HOME/.bash_profile" ;;
    fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
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

say ''
say 'The VSCode extension (search "FRX" in the Marketplace) finds this binary'
say 'even when the editor was launched from the Dock and has a different PATH.'
