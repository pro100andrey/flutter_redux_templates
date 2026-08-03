#!/bin/bash
# Refuse a hand edit to a file whose shape a frx command owns.
#
# Why a hook and not a skill: the Agent Skills standard says an agent "only
# consult[s] skills for tasks that require knowledge or capabilities beyond what
# they can handle alone", and writing a Dart file looks like one it can. Two
# traced runs bear that out — one rewrote five state files whole, the next added
# the same fields line by line with Edit, both ten minutes after reading the
# skill that says to run the command. Anthropic's guidance for that gap is
# hooks: they fire on the tool call, not on the agent's judgement.
#
# The scope is asymmetric on purpose:
#
#   * a substate's state file — `Write` and `Edit` both refused. Every field in
#     it carries wiring (the `Select` getter, a collection type's import) that
#     only `add-field` writes, and a field is what an edit here almost always
#     adds.
#   * the selector facade — `Write` refused, `Edit` allowed. `add-selector`
#     takes an expression, so a selector whose body needs statements is written
#     by hand into this file, and that is what the skill tells you to do. A
#     guard that forbade it would contradict the documentation it enforces.
#
# Exit 2 blocks the call and hands stderr to the agent, which is where the
# command it should have run is named.
set -u

payload=$(cat)

# No jq: a Flutter checkout is not guaranteed to have it. Both fields needed are
# flat strings, so a tolerant grep costs no dependency.
field() {
  printf '%s' "$payload" |
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
    head -1 |
    sed 's/.*"\([^"]*\)"$/\1/'
}

tool=$(field tool_name)
path=$(field file_path)

case "$tool" in
  Write | Edit | MultiEdit) ;;
  *) exit 0 ;;
esac

case "$path" in
  */business/lib/redux/*/models/*_state.dart)
    slice=$(printf '%s' "$path" | sed 's|.*/redux/\([^/]*\)/models/.*|\1|')
    cat >&2 <<EOF
The shape of this file belongs to frx. A field added here by hand arrives without
the wiring that comes with it — the Select getter on the facade, and the import a
collection type needs.

  frx add-field $slice <name>:<type>           # nullable, or pass --default
  frx add-field $slice <name>:<type> --action  # also its setter action

Run \`frx help add-field\` for the flags. Collections are IList / IMap / ISet.
EOF
    exit 2
    ;;
  */business/lib/redux/selectors.dart)
    [ "$tool" = "Write" ] || exit 0
    cat >&2 <<'EOF'
The selector facade is wired by frx. Writing it whole loses the getters other
commands put there.

  frx add-selector <substate> <name> --type <T> [--expr '<body>']

A selector whose body needs statements rather than one expression is written by
hand — reach for Edit for that, which this guard allows.
EOF
    exit 2
    ;;
esac

exit 0
