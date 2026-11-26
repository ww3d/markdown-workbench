#!/usr/bin/env bash
# Stands in for one guard in a copied hooks folder (cases/pre-tool-parity.sh): files the call, its environment
# and the markers of this moment under $PARITY_CORPUS, then runs the real guard on it.
name="${BASH_SOURCE[0]##*/}"
box="$(mktemp -d "$PARITY_CORPUS/XXXXXXXX")" || exit 1
cat > "$box/input"
gate="${TMPDIR:-${TMP:-${TEMP:-}}}"
if [ -n "$gate" ] && [ -d "$gate/claude-rule-gate" ]; then cp -R "$gate/claude-rule-gate" "$box/gate"; fi
{
  printf 'cd %q\n' "$PWD"
  # Only what the guards read: a session's environment also holds its tokens.
  for v in $(compgen -e); do
    case "$v" in
      PLAYBOOK_* | GUARD_* | CLAUDE_PROJECT_DIR | CLAUDE_CODE_REMOTE | CLAUDE_CODE_SESSION_ID | CLAUDE_CONFIG_DIR | \
        CLAUDE_JOB_DIR | TMPDIR | TMP | TEMP | PATH) printf 'export %s=%q\n' "$v" "${!v}" ;;
    esac
  done
} > "$box/env"
exec "$BASH" "$PARITY_REAL/$name" "$@" < "$box/input"
