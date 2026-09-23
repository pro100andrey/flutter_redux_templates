#!/bin/sh
# install.sh, run end to end against a synthetic release — the `installer-run`
# task, in CI's `ci-installers` gate set.
#
# The linter only reads the script. What it cannot see is everything install.sh
# does once it runs: the download, the checksum, the unpack, and the one edit
# it makes to a stranger's shell profile — which file, how many times, and with
# what path in it. Each of those shipped broken at least once and was found by a
# user, because nothing in CI had ever executed the script.
#
# The release is built here: a stub `frx` that prints a version, archived under
# every name install.sh can ask for, plus a `checksums.txt`. It is served over
# localhost when python3 is there (the path a real install takes, through HTTP)
# and as file:// otherwise; `FRX_DOWNLOAD_BASE` points the installer at it.
# Every run gets a fresh $HOME and a scrubbed environment, so nothing of the
# machine running the test — its profile, its ~/.frx — is read or written.
#
# Two things the host cannot be made to be are faked on PATH: `uname` (to take
# the macOS branch on Linux) and `ldd` (to be a musl system on a glibc one).
#
# Runs the installer under every POSIX shell present — sh, dash, bash, busybox
# ash — because /bin/sh is whichever of them the machine has, and a bashism is
# a failure only under the others.
#
# POSIX sh, like the script it tests.
set -u

ROOT="$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd)"
INSTALLER="$ROOT/tools/scripts/install.sh"
VERSION=1.2.3

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t frxtest)"
SERVER_PID=''
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

FAILED=0
ok()   { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }
# check <description> <command...>: passes when the command succeeds.
check() {
  what="$1"; shift
  if "$@"; then ok "$what"; else fail "$what"; fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# --- the synthetic release --------------------------------------------------

# make_release <dir> <what the stub prints for --version>
make_release() {
  mkdir -p "$1/stage"
  cat > "$1/stage/frx" <<EOF
#!/bin/sh
case "\${1:-}" in
  --version) echo '$2' ;;
  completions) echo "# stub completions for \${2:-}" ;;
  *) echo 'frx stub' ;;
esac
EOF
  chmod 755 "$1/stage/frx"
  for os in linux macos; do
    for arch in x64 arm64; do
      tar -czf "$1/frx-$VERSION-$os-$arch.tar.gz" -C "$1/stage" frx
    done
  done
  rm -rf "$1/stage"
  (cd "$1" && sha256 frx-*.tar.gz > checksums.txt)
}

SRV="$WORK/srv"
make_release "$SRV/good" "frx $VERSION"
# The same names and the same checksums.txt, but archives whose bytes are not
# the ones it lists: what a compromised mirror or a truncated proxy hands over.
make_release "$SRV/tampered" "frx $VERSION (tampered)"
cp "$SRV/good/checksums.txt" "$SRV/tampered/checksums.txt"

if command -v python3 >/dev/null 2>&1; then
  # Port 0, and the port the kernel picked written out: a fixed port collides
  # with whatever else the runner has listening.
  python3 -c '
import functools, http.server, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
handler.log_message = lambda *a: None
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
with open(sys.argv[2] + ".tmp", "w") as f: f.write(str(server.server_address[1]))
import os; os.rename(sys.argv[2] + ".tmp", sys.argv[2])
server.serve_forever()
' "$SRV" "$WORK/port" &
  SERVER_PID=$!
  i=0
  while [ ! -s "$WORK/port" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$WORK/port" ] || { echo 'the release server did not start' >&2; exit 1; }
  BASE_URL="http://127.0.0.1:$(cat "$WORK/port")"
else
  BASE_URL="file://$SRV"
fi
echo "release served at $BASE_URL"

# --- fakes ------------------------------------------------------------------

REAL_UNAME="$(command -v uname)"
FAKE_DARWIN="$WORK/fake-darwin"
mkdir -p "$FAKE_DARWIN"
cat > "$FAKE_DARWIN/uname" <<EOF
#!/bin/sh
[ "\${1:-}" = -s ] && { echo Darwin; exit 0; }
exec '$REAL_UNAME' "\$@"
EOF
chmod 755 "$FAKE_DARWIN/uname"

# musl's ldd answers `--version` on stderr with exit 1; the installer must go
# by what it says, not by the exit code.
FAKE_MUSL="$WORK/fake-musl"
mkdir -p "$FAKE_MUSL"
printf '#!/bin/sh\necho "musl libc (x86_64)" >&2\nexit 1\n' > "$FAKE_MUSL/ldd"
chmod 755 "$FAKE_MUSL/ldd"

# --- running it -------------------------------------------------------------

# run_install <shell> <home> <login shell> <release> <PATH prefix> [args...]
# Runs from $home, output in $home.log. A scrubbed environment: only what a
# fresh terminal would plausibly carry, so a FRX_* or ZDOTDIR of the machine
# running the test cannot steer the installer.
run_install() {
  sh_cmd="$1"; home="$2"; login="$3"; release="$4"; prefix="$5"; shift 5
  mkdir -p "$home"
  # shellcheck disable=SC2086  # `busybox ash` is two words on purpose.
  (cd "$home" && env -i HOME="$home" SHELL="$login" PATH="$prefix$PATH" \
    FRX_DOWNLOAD_BASE="$BASE_URL/$release" \
    $sh_cmd "$INSTALLER" --version "$VERSION" "$@") > "$home.log" 2>&1
}

count() { grep -c "$1" "$2" 2>/dev/null || true; }
runs_stub() { [ "$("$1" --version 2>/dev/null)" = "frx $VERSION" ]; }
missing() { [ ! -e "$1" ]; }
contains() { grep -qF "$2" "$1" 2>/dev/null; }

SHELLS='sh'
for s in dash bash; do command -v "$s" >/dev/null 2>&1 && SHELLS="$SHELLS $s"; done
command -v busybox >/dev/null 2>&1 && SHELLS="$SHELLS busybox_ash"

n=0
for s in $SHELLS; do
  sh_cmd="$(printf '%s' "$s" | tr _ ' ')"
  n=$((n + 1))
  echo "--- under $sh_cmd"

  # A good release, installed twice: the second run is the upgrade path, and
  # must not add a second PATH line or a second completions line.
  h="$WORK/h$n-good"
  run_install "$sh_cmd" "$h" /bin/zsh good ''
  check "[$s] installs: exit 0" [ $? -eq 0 ]
  check "[$s] the installed binary runs" runs_stub "$h/.frx/bin/frx"
  check "[$s] PATH line written once" [ "$(count '# added by frx installer' "$h/.zshrc")" = 1 ]
  run_install "$sh_cmd" "$h" /bin/zsh good ''
  check "[$s] re-run: exit 0" [ $? -eq 0 ]
  check "[$s] re-run: PATH line still once" [ "$(count '# added by frx installer' "$h/.zshrc")" = 1 ]
  check "[$s] re-run: completions line still once" [ "$(count '# frx completions' "$h/.zshrc")" = 1 ]

  # A tampered archive: refused, and nothing of it left behind.
  h="$WORK/h$n-tampered"
  run_install "$sh_cmd" "$h" /bin/zsh tampered ''
  check "[$s] tampered: nonzero exit" [ $? -ne 0 ]
  check "[$s] tampered: says why" contains "$h.log" 'checksum mismatch'
  check "[$s] tampered: installs nothing" missing "$h/.frx/bin/frx"
  check "[$s] tampered: touches no profile" missing "$h/.zshrc"
done

echo '--- which profile, per shell and OS'

# bash on Linux reads ~/.bashrc in every interactive shell that is not a login
# one, and the distributions' own login files source it.
h="$WORK/bash-linux-bashrc"; mkdir -p "$h"; : > "$h/.bashrc"
run_install sh "$h" /bin/bash good ''
check 'bash/Linux with a .bashrc: written there' [ "$(count '# added by frx installer' "$h/.bashrc")" = 1 ]
check 'bash/Linux with a .bashrc: no .bash_profile created' missing "$h/.bash_profile"

# No .bashrc: the login file bash already reads. Creating a .bash_profile would
# shadow the .profile, and every PATH entry in it would vanish.
h="$WORK/bash-linux-profile"; mkdir -p "$h"
# shellcheck disable=SC2016  # a line of someone's profile, literal on purpose.
echo 'export PATH="$HOME/mine:$PATH"' > "$h/.profile"
run_install sh "$h" /bin/bash good ''
check 'bash/Linux with only .profile: written there' [ "$(count '# added by frx installer' "$h/.profile")" = 1 ]
check 'bash/Linux with only .profile: no .bash_profile created' missing "$h/.bash_profile"

h="$WORK/bash-linux-empty"
run_install sh "$h" /bin/bash good ''
check 'bash/Linux with no profile at all: .profile created' [ "$(count '# added by frx installer' "$h/.profile")" = 1 ]
check 'bash/Linux with no profile at all: no .bash_profile created' missing "$h/.bash_profile"

# macOS: Terminal.app opens login shells, which never read .bashrc.
h="$WORK/bash-mac-bashrc"; mkdir -p "$h"; : > "$h/.bashrc"
run_install sh "$h" /bin/bash good "$FAKE_DARWIN:"
check 'bash/macOS: exit 0' [ $? -eq 0 ]
check 'bash/macOS with a .bashrc: written to .bash_profile' [ "$(count '# added by frx installer' "$h/.bash_profile")" = 1 ]
check 'bash/macOS with a .bashrc: .bashrc left alone' [ "$(count '# added by frx installer' "$h/.bashrc")" = 0 ]

h="$WORK/bash-mac-profile"; mkdir -p "$h"; : > "$h/.profile"
run_install sh "$h" /bin/bash good "$FAKE_DARWIN:"
check 'bash/macOS with only .profile: written there' [ "$(count '# added by frx installer' "$h/.profile")" = 1 ]
check 'bash/macOS with only .profile: no .bash_profile created' missing "$h/.bash_profile"

echo '--- options and refusals'

h="$WORK/reldir"
run_install sh "$h" /bin/zsh good '' --dir relbin
check '--dir relbin: installed under the cwd' runs_stub "$h/relbin/frx"
check '--dir relbin: the profile gets an absolute path' contains "$h/.zshrc" "export PATH=\"$h/relbin:"

h="$WORK/nomodify"
run_install sh "$h" /bin/zsh good '' --no-modify-path
check '--no-modify-path: installed' runs_stub "$h/.frx/bin/frx"
check '--no-modify-path: no profile written' missing "$h/.zshrc"

# The Linux build links glibc; on musl it would install, say ✓, and then fail
# to start with a `not found` that names no missing file.
h="$WORK/musl"
run_install sh "$h" /bin/sh good "$FAKE_MUSL:"
check 'musl: nonzero exit' [ $? -ne 0 ]
check 'musl: says why' contains "$h.log" 'musl libc'
check 'musl: installs nothing' missing "$h/.frx/bin/frx"

echo
if [ "$FAILED" -ne 0 ]; then
  echo "$FAILED check(s) failed. Installer output is in each case's .log:" >&2
  for log in "$WORK"/*.log; do echo "== $log" >&2; cat "$log" >&2; done
  exit 1
fi
echo "install.sh: every check passed (shells: $SHELLS)"
