#!/usr/bin/env bash
# Lists the VSCode profiles on this machine and which frx build each one holds.
#
# VSCode installs extensions per profile, and `code --list-extensions` without
# `--profile` reports the *Default* profile — so "it's installed" and "it's
# installed where I'm working" are different questions. This answers the second.
#
#   vscode-profiles.sh            table: profile, storage dir, installed frx
#   vscode-profiles.sh --names    just the names, one per line (for scripting)
set -euo pipefail

case "$(uname -s)" in
  Darwin) USER_DIR="$HOME/Library/Application Support/Code/User" ;;
  Linux)  USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
  *) echo "vscode-profiles: unsupported platform $(uname -s)" >&2; exit 1 ;;
esac

STORAGE="$USER_DIR/globalStorage/storage.json"

# The Default profile is implicit — it has no entry in storage.json.
names() {
  echo "Default"
  [ -f "$STORAGE" ] || return 0
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for p in d.get("userDataProfiles") or []:
    name = p.get("name")
    if name:
        print(name)
' "$STORAGE"
}

if [ "${1:-}" = "--names" ]; then
  names
  exit 0
fi

if ! command -v code >/dev/null 2>&1; then
  echo "vscode-profiles: the \`code\` command is not on PATH." >&2
  echo "  In VSCode: Command Palette → 'Shell Command: Install code command in PATH'." >&2
  exit 1
fi

printf '%-16s  %s\n' "PROFILE" "frx"
printf '%-16s  %s\n' "----------------" "----------------"
while IFS= read -r name; do
  if [ "$name" = "Default" ]; then
    installed=$(code --list-extensions --show-versions 2>/dev/null | grep -i 'frx' || true)
  else
    installed=$(code --profile "$name" --list-extensions --show-versions 2>/dev/null | grep -i 'frx' || true)
  fi
  printf '%-16s  %s\n' "$name" "${installed:-—}"
done < <(names)
