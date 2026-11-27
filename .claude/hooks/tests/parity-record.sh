#!/usr/bin/env bash
# Stands in for one hook in a copied hooks folder (parity.sh): files the call, its environment and the markers
# of this moment under $PARITY_CORPUS, compares it right away where PARITY_COMPARE names the comparing program,
# then runs the real hook on it.
name="${BASH_SOURCE[0]##*/}"
# A terminal on stdin is a hand call: there is no input to record, and reading it would wait for the keyboard.
if [ -t 0 ]; then exec "$BASH" "$PARITY_REAL/$name" "$@"; fi
# The recorder's own programs come from the run's PATH: a case narrows PATH to what its hook calls. A call that
# cannot be filed is counted, never lost in silence.
own="${PARITY_PATH:-$PATH}"
if ! box="$(PATH="$own" mktemp -d "$PARITY_CORPUS/XXXXXXXX")"; then
  : >> "$PARITY_CORPUS/lost"
  exec "$BASH" "$PARITY_REAL/$name" "$@"
fi
PATH="$own" cat > "$box/input"
gate="${TMPDIR:-${TMP:-${TEMP:-}}}"
if [ -n "$gate" ] && [ -d "$gate/claude-rule-gate" ]; then PATH="$own" cp -R "$gate/claude-rule-gate" "$box/gate"; fi
{
  printf 'cd %q\n' "$PWD"
  # Only what the hooks read: a session's environment also holds its tokens.
  for v in $(compgen -e); do
    case "$v" in
      PLAYBOOK_* | GUARD_* | CLAUDE_PROJECT_DIR | CLAUDE_CODE_REMOTE | CLAUDE_CODE_SESSION_ID | CLAUDE_CONFIG_DIR | \
        CLAUDE_JOB_DIR | CLAUDE_CODE_AUTO_COMPACT_WINDOW | CLAUDE_AUTOCOMPACT_PCT_OVERRIDE | \
        CLAUDE_CODE_DISABLE_1M_CONTEXT | SS_FORGE | STATE_CACHE_DIR | TICKS_* | GH_DOUBLE_WORLD | ANTHROPIC_MODEL | PB_HOOK_CALLER | TMPDIR | TMP | TEMP | PATH) printf 'export %s=%q\n' "$v" "${!v}" ;;
    esac
  done
} > "$box/env"
if [ -n "${PARITY_COMPARE:-}" ]; then
  boxes=("$PARITY_CORPUS"/*/); part="${PARITY_PART:-1/1}"
  if ((${#boxes[@]} % ${part#*/} == ${part%/*} - 1)); then PATH="$PARITY_PATH" "$BASH" "$PARITY_COMPARE" "$box" < /dev/null
  else : > "$box/skipped"; fi
fi
exec "$BASH" "$PARITY_REAL/$name" "$@" < "$box/input"
