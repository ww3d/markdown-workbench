#!/usr/bin/env bash
#
# PreCompact hook - saves which rule files the main thread read before this compaction. Generic,
# byte-identical across consumers.
#
# Only this moment still sees the read record: on the SessionStart that follows the compaction,
# read-confirm.sh deletes the session's read markers, and hooks of one event run in no fixed
# order, so restore-compact-state.sh cannot count on finding them. This hook copies them:
#
#   ${TMPDIR:-/tmp}/claude-rule-gate/<session>-compact-rules
#     lines=<n>          the transcript's line count now, where the part before this compaction ends
#     <path>             one line per file read in full, relative to the project root; a skill
#                        reference no file matches keeps its marker name, so no read drops silently
#
# The name does not start with "<session>-read-", so read-confirm.sh leaves it; the restore uses it
# once and removes it, the weekly sweep of that folder any left over. It is a copy for
# restore-compact-state.sh, no carrier. A sub-agent's
# reads are left out: its context is not the one being compacted.
#
# Fail-open: bash builtins plus wc and sed; no jq. Whatever goes wrong, the hook writes what it can
# and exits 0 - a compaction never waits on it.
#
# Stdin:  the PreCompact event JSON. Stdout: nothing.
set -uo pipefail

if [ -S /dev/stdin ]; then input="$(cat)" || true; else input="$(</dev/stdin)" || true; fi

field() { # key -> global val, the first string value of "key" in the raw payload
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}

# Known token shapes, masked in every file the compaction hooks write (restore-compact-state.sh
# uses the same expression); a path or a transcript line can carry one.
mask() {
  sed -E \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{20,}/\1[masked]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/github_pat_[masked]/g' \
    -e 's/(sk-(ant-)?)[A-Za-z0-9_-]{20,}/\1[masked]/g' \
    -e 's/(xox[abprs]-)[A-Za-z0-9-]{10,}/\1[masked]/g' \
    -e 's/AKIA[0-9A-Z]{16}/AKIA[masked]/g' \
    -e 's/(glpat-)[A-Za-z0-9_-]{20,}/\1[masked]/g' \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[A-Za-z0-9._~+\/=-]{20,}/\1[masked]/g'
}

field session_id; session="$val"
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
field transcript_path; transcript="${val//\\\\//}"
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
root="${root%/}"

gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
{ [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null || exit 0

lines=0
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
  # wc, not a read loop: bash reads a line byte by byte, and a transcript runs to megabytes.
  lines="$(wc -l < "$transcript" 2>/dev/null | tr -d ' ')" || lines=0
  [[ $lines =~ ^[0-9]+$ ]] || lines=0
fi

# A marker name back to its file; a skill reference is ambiguous at the hyphen between skill and
# file name, so the split that names an existing file wins.
resolve() { # marker name -> global rel ("" when none)
  local name="$1" rest skill f i s
  rel=""
  case "$name" in
    core.agents) rel="AGENTS.md" ;;
    core.claude) rel="CLAUDE.md" ;;
    core.audit.*)
      s="${name#core.audit.}"
      for f in "docs/audit/state-$s.md" "docs/audit/ist-stand-$s.md" "audit/state-$s.md" "audit/ist-stand-$s.md"; do
        if [ -e "$root/$f" ]; then rel="$f"; return; fi
      done
      rel="docs/audit/state-$s.md" ;;
    local-*) rel=".agents/rules/local/${name#local-}.md" ;;
    skill-*)
      rest="${name#skill-}"
      for ((i = 1; i < ${#rest}; i++)); do
        [ "${rest:i:1}" = - ] || continue
        skill="${rest:0:i}"; f="${rest:i+1}"
        if [ -e "$root/.claude/skills/$skill/reference/$f.md" ]; then rel=".claude/skills/$skill/reference/$f.md"; return; fi
      done
      # No split names a file (a root other than the project's): the marker itself still says which.
      rel="skill reference $rest (marker name, no file found under $root/.claude/skills)" ;;
    *) rel=".agents/rules/$name.md" ;;
  esac
}

out="lines=$lines"
prefix="${gate_dir}/${session}-read-main-"
for m in "$prefix"*; do
  [ -e "$m" ] || continue
  resolve "${m#"$prefix"}"
  [ -z "$rel" ] || out="$out"$'\n'"$rel"
done

printf '%s\n' "$out" | mask > "${gate_dir}/${session}-compact-rules" 2>/dev/null || true
exit 0
