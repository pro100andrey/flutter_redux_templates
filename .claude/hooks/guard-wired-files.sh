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

# --- the shell channel -------------------------------------------------------
#
# `Write` and `Edit` are not the only ways to write a file, and measurement said
# so: across four traced builds the agent put 55–69 `.dart` files on disk per run
# through `Bash` — `cat > f <<'DART'` heredocs and `python3 - <<'PY'` patch
# scripts. In one run two state files were refused on `Write` and rewritten
# through `Bash` two minutes later. A guard blind to this channel is not a weaker
# guard; it is one that reports success while the write happens.
#
# **This is a speed bump, not a wall, and the difference is not repairable.** A
# shell can write a file in unlimited ways — base64, a variable holding the path,
# `install`, an editor script, a Dart program. What is caught here is what agents
# actually reach for, measured rather than imagined. The honest gate on the
# result is `frx doctor`, which reads the tree and does not care how it got
# there.
#
# Paths are matched by their **tail**, not from the repo root. `cd business/lib`
# followed by `cat > redux/tasks/models/tasks_state.dart` is the observed shape —
# 127 of the commands in those runs were preceded by a `cd` — and a tail match
# resolves it without parsing the shell.

# The two shapes frx owns. Kept as tails so a relative path matches too.
readonly STATE_TAIL='redux/[A-Za-z0-9_]+/models/[A-Za-z0-9_]+_state\.dart'
readonly SELECTORS_TAIL='redux/selectors\.dart'

# A path that lands *after* one of these has been written to. The operator has to
# precede the path, which is what keeps Dart source inside a heredoc body from
# matching: `IMap get table => _state…` is a fat arrow followed by nothing frx
# owns, and no `>` in this repo's code is followed by a state file's path.
readonly WRITE_OPS='(>>?|(^|[^A-Za-z0-9_])tee([[:space:]]+-a)?)[[:space:]]*'
readonly NOT_PATH='[^[:space:]<>|;&"'"'"']*'

# `cp`, `mv` and `install` write to their *last* operand, so the path that
# matters sits behind at least one other word. Folding them into WRITE_OPS was
# exactly backwards, and measurably so: `cp /tmp/new.dart <state file>` was
# allowed while `mv <state file> /tmp/x` — which only reads it — was refused.
# The two rules are separate because they ask different questions, and one
# pattern that answered both answered neither.
readonly COPY_OPS='(^|[^A-Za-z0-9_])(cp|mv|install)([[:space:]]+-[^[:space:]]+)*[[:space:]]+'
readonly ANY_OPERANDS='[^|;&]*[[:space:]]'

# Editing in place rather than replacing: `sed -i`, and the interpreter scripts
# that do the same thing with a read-modify-write. `open(` alone is not enough —
# it reads as often as it writes — so the mode or an unambiguous writer is what
# counts.
readonly INPLACE_TOOLS='(^|[^A-Za-z0-9_])(sed|perl)([[:space:]]+-[A-Za-z]*i|[[:space:]]+--in-place)'
#
# The `\(` is not decoration. Without it the rule fires on any command that
# merely contains the *word*: an analysis script whose regex reads
# `'cat >|write_text'` while a `sed -n` elsewhere names a state file was refused,
# and it only read. A real call always has its parenthesis.
readonly INPLACE_WRITES='(write_text\(|write_bytes\(|writeFileSync\(|shutil\.(copy|move)\(|open\([^)]*,[^)]*['"'"'"][wax])'

says() { printf '%s' "$payload" | grep -Eq "$1"; }

refuse_shell() {
  cat >&2
  exit 2
}

guard_shell() {
  # Whole-file replacement — the `cat > f <<'DART'` shape. Refused for both, the
  # way `Write` is: it loses every getter and field the commands put there.
  if says "$WRITE_OPS$NOT_PATH$STATE_TAIL" ||
    says "$COPY_OPS$ANY_OPERANDS$NOT_PATH$STATE_TAIL"; then
    refuse_shell <<EOF
This writes a substate's state file from the shell, which is the same edit the
Write tool is refused for — and refusing one channel while allowing the other is
how a field arrives without the Select getter that comes with it.

  frx add-field <substate> <name>:<type>           # nullable, or pass --default
  frx add-field <substate> <name>:<type> --action  # also its setter action

Collections are IList / IMap / ISet. Run \`frx help add-field\` for the flags.
EOF
  fi

  if says "$WRITE_OPS$NOT_PATH$SELECTORS_TAIL" ||
    says "$COPY_OPS$ANY_OPERANDS$NOT_PATH$SELECTORS_TAIL"; then
    refuse_shell <<'EOF'
This replaces the selector facade wholesale from the shell. Written whole it
loses the getters other commands put there.

  frx add-selector <substate> <name> --type <T> [--expr '<body>']

A selector whose body needs statements is hand-written — and editing one in
place, here or with Edit, is allowed. Replacing the file is not.
EOF
  fi

  # In-place edits. Refused for a state file, allowed for the facade — the same
  # asymmetry the tool channel already has, and for the same reason: the facade
  # holds hand-written selectors, a state file holds only wiring.
  if says "$STATE_TAIL" &&
    { says "$INPLACE_TOOLS" || says "$INPLACE_WRITES"; }; then
    refuse_shell <<EOF
This edits a substate's state file in place from the shell. Every field in it
carries wiring — the Select getter on the facade, the import a collection type
needs — and only \`add-field\` writes that.

  frx add-field <substate> <name>:<type>

If you are changing something that is not a field, say so by editing through the
Edit tool, which refuses for the same reason and names it.
EOF
  fi
}

case "$tool" in
  Write | Edit | MultiEdit) ;;
  Bash) guard_shell; exit 0 ;;
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
