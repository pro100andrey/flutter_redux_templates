#!/bin/bash
# Refuse a wholesale `Write` over a file frx owns the shape of.
#
# Why a hook and not a skill: the Agent Skills standard says an agent "only
# consult[s] skills for tasks that require knowledge or capabilities beyond what
# they can handle alone", and writing a Dart file looks like one it can. A traced
# run had the agent read five state files and rewrite them whole, ten minutes
# after reading the skill that says not to. Anthropic's own guidance for that
# gap is hooks — they fire on the tool call, not on the agent's judgement.
#
# Scope is deliberately narrow:
#   * `Write` only. `Edit` is a targeted change and stays free — fixing a doc
#     comment or a body in one of these files is ordinary work.
#   * The two files whose *shape* a command owns: a substate's freezed state,
#     and the selector facade. Everything else in the tree is yours to write.
#
# Exit 2 blocks the call and hands stderr back to the agent, which is where the
# command it should have run is named.
set -u

payload=$(cat)

# No jq: a Flutter checkout is not guaranteed to have it. The two fields needed
# are flat strings, so a tolerant grep is enough and costs no dependency.
tool=$(printf '%s' "$payload" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
path=$(printf '%s' "$payload" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')

[ "$tool" = "Write" ] || exit 0

case "$path" in
  */business/lib/redux/*/models/*_state.dart)
    slice=$(printf '%s' "$path" | sed 's|.*/redux/\([^/]*\)/models/.*|\1|')
    cat >&2 <<EOF
This file's shape belongs to frx. Writing it whole drops the wiring that comes
with a field — the Select getter on the facade, and the import a collection type
needs.

  frx add-field $slice <name>:<type>          # nullable, or add --default
  frx add-field $slice <name>:<type> --action # also its setter action

Run \`frx help add-field\` for the flags. Use Edit for a targeted change to a
line that already exists.
EOF
    exit 2
    ;;
  */business/lib/redux/selectors.dart)
    cat >&2 <<'EOF'
The selector facade is wired by frx. Writing it whole loses the getters other
commands put there.

  frx add-selector <substate> <name> --type <T> [--expr '<body>']

A selector whose body needs statements rather than one expression is written by
hand — use Edit for that, inside this file, which is where the placement rule
(`selector-outside-facade`) expects it.
EOF
    exit 2
    ;;
esac

exit 0
