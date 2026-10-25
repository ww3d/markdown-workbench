#!/usr/bin/env bash
#
# PostToolUse hook for Read - records a real read of a file the read receipt names. Generic,
# byte-identical across consumers.
#
# The companion of require-rule-read.sh: that hook blocks the first action of a
# trigger type until the matching rule file was read; this one writes the state
# it looks for. A Read that succeeded (PostToolUse fires only after success) on
#
#   .agents/rules/<trigger>.md              -> marker  <session>-read-<who>-<trigger>
#   .agents/rules/local/<trigger>.md        -> marker  <session>-read-<who>-local-<trigger>
#   .claude/skills/<skill>/reference/<f>.md -> marker  <session>-read-<who>-skill-<skill>-<f>
#   AGENTS.md, CLAUDE.md at the project root -> marker  <session>-read-<who>-core.agents / -core.claude
#   docs/audit/state-<stamp>.md (ist-stand-<stamp>.md until 26.0.0; audit/ until 26.0.0,
#   the first MAJOR after the move)          -> marker <session>-read-<who>-core.audit.<stamp>
#   (an audit also from a read that starts at line 1 and covers its short form, see below)
# The dot keeps the core markers apart from every rule name, which allows only [A-Za-z0-9_-]. A core
# file needs CLAUDE_PROJECT_DIR: from the payload's cwd alone the project root is not known.
#
# counts when it covered the WHOLE file (an audit: see the range test below): no offset/limit, or a range that
# reached from line 1 to the last line (tool_response.file.startLine / numLines /
# totalLines). <who> is the sub-agent's agent_id, or "main" for the main
# thread: a sub-agent has a fresh context and has to read the file itself,
# while it shares session_id and transcript_path with its parent (measured with
# Claude Code 2.1.293: agent_id and agent_type appear in the payload only for
# a call made inside a sub-agent).
#
# A compaction ends every marker of the session: read-confirm.sh deletes
# ${TMPDIR}/claude-rule-gate/<session>-* on source "compact".
#
# Cost. Registered for Read only, and the payload of a Read carries the whole file. It is read
# with `$(</dev/stdin)` (a byte-by-byte `read` costs about 4.5 ms per KB), then judged with bash
# builtins alone, no jq: a Read whose payload names none of these paths exits at the first test.
#
# Fail-open: a payload this hook cannot read records nothing, and the gate's second
# source - the typed receipt line in the transcript - still works.
#
# Stdin:  the PostToolUse event JSON. Stdout: nothing.

set -euo pipefail

# Where stdin is a socket (Claude Code in a cloud session), /dev/stdin cannot be opened ("No such
# device or address"); `cat` reads it there, at the price of one process start.
if [ -S /dev/stdin ]; then input="$(cat)" || true; else input="$(</dev/stdin)" || true; fi

# The record runs for this session: require-receipt.sh checks green lines only where this stands.
# Written for every Read, from the head of the payload, where session_id stands.
sign_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
if [[ ${input:0:1000} =~ $sign_re ]]; then
  if { [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null; then
    { : > "${gate_dir}/${BASH_REMATCH[1]}-recorder.on"; } 2>/dev/null || true
  fi
fi

# Cheap exit: only a path that can be a rule file, a skill reference or a core file passes.
case "$input" in
  *.agents?rules?*|*.agents??rules??*|*.claude?skills?*|*.claude??skills??*|*AGENTS.md*|*CLAUDE.md*|*audit?*) ;;
  *) exit 0 ;;
esac

field() { # key -> global val, the first string value of "key" in the raw payload
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}
num() { # key -> global val, the first number value of "key"
  local re="\"$1\"[[:space:]]*:[[:space:]]*([0-9]+)"
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}

field session_id; session="$val"
[ -n "$session" ] || exit 0
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
field agent_id; who="${val:-main}"
[[ $who =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

# tool_input.file_path comes first in the payload; JSON doubles every backslash.
field file_path
path="${val//\\\\//}"
path="${path//\\//}"

# Only a file inside the project counts: a rule file read from another checkout is not this
# project's rule. The root is CLAUDE_PROJECT_DIR, else the payload's cwd; a path climbing out
# through `..` is refused. One spelling for both sides: slashes, a drive letter D:/x as /D/x
# (the Git Bash form), no trailing slash; on Windows the comparison ignores case.
case "$path" in */../*|*/..) exit 0 ;; esac
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
if [ -n "$root" ]; then
  root="${root//\\//}"; root_n="$root"; path_n="$path"
  case "$root" in [A-Za-z]:/*) root_n="/${root:0:1}${root:2}" ;; esac
  case "$path" in [A-Za-z]:/*) path_n="/${path:0:1}${path:2}" ;; esac
  root_n="${root_n%/}"
  case "$root$path" in *[A-Za-z]:/*) shopt -s nocasematch ;; esac
  [[ $path_n == "$root_n"/* ]] || exit 0
  shopt -u nocasematch
fi

name=""
# A core file counts at the project root only. The containment test above already matched the
# root, case-blind on Windows, so the relative part is cut by length, not by a case-sensitive prefix.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  case "$root$path" in *[A-Za-z]:/*) shopt -s nocasematch ;; esac
  rel="${path_n:$(( ${#root_n} + 1 ))}"
  case "$rel" in
    AGENTS.md) name="core.agents" ;;
    CLAUDE.md) name="core.claude" ;;
    docs/audit/state-*.md) stamp="${rel:17:$(( ${#rel} - 20 ))}" ;;
    docs/audit/ist-stand-*.md) stamp="${rel:21:$(( ${#rel} - 24 ))}" ;;
    # audit/ is the old place, read until playbook 26.0.0, the first MAJOR after the move.
    audit/state-*.md) stamp="${rel:12:$(( ${#rel} - 15 ))}" ;;
    audit/ist-stand-*.md) stamp="${rel:16:$(( ${#rel} - 19 ))}" ;;
  esac
  shopt -u nocasematch
  [[ -z "${stamp:-}" || ! $stamp =~ ^[A-Za-z0-9_.-]+$ ]] || name="core.audit.${stamp}"
fi
[ -z "$name" ] && case "$path" in
  # A consumer's own rule: its marker is `local-<trigger>`, so it never stands in for a playbook rule of that name.
  */.agents/rules/local/*.md)
    name="${path##*/.agents/rules/local/}"
    [[ $name != */* && $name =~ ^[A-Za-z0-9_-]+\.md$ ]] || exit 0
    name="local-${name%.md}" ;;
  */.agents/rules/*.md)
    name="${path##*/.agents/rules/}"
    [[ $name != */* && $name =~ ^[A-Za-z0-9_-]+\.md$ ]] || exit 0
    name="${name%.md}" ;;
  */.claude/skills/*/reference/*.md)
    name="${path##*/.claude/skills/}"
    skill="${name%%/*}"; file="${name##*/}"
    [[ $skill =~ ^[A-Za-z0-9_-]+$ && $file =~ ^[A-Za-z0-9_.-]+$ && $name == "${skill}/reference/${file}" ]] || exit 0
    name="skill-${skill}-${file%.md}" ;;
  *) exit 0 ;;
esac

# Whole file? A partial range does not count - except for an audit, where a read from line 1 that
# covers its short form counts (.agents/rules/session.md, section "Session Receipt"): the metadata block and the
# first "## " section, up to the line before the second "## " heading of the file on disk.
case "$input" in
  *'"offset"'*|*'"limit"'*)
    num startLine; start="$val"; num numLines; lines="$val"; num totalLines; total="$val"
    [ "$start" = 1 ] && [ -n "$lines" ] && [ -n "$total" ] || exit 0
    need="$total"
    if [[ $name == core.audit.* && -r $path ]]; then
      n=0; heads=0
      fence=""
      while IFS= read -r l || [ -n "$l" ]; do
        n=$((n + 1))
        if [[ $l =~ ^\ {0,3}(\`{3,}|~{3,}) ]]; then
          if [ -z "$fence" ]; then fence="${BASH_REMATCH[1]}"; continue
          elif [[ ${BASH_REMATCH[1]} == "${fence:0:1}"* && ${#BASH_REMATCH[1]} -ge ${#fence} ]]; then fence=""; continue; fi
        fi
        [ -z "$fence" ] || continue
        if [[ $l == '## '* ]]; then heads=$((heads + 1)); [ "$heads" -lt 2 ] || { need=$((n - 1)); break; }; fi
      done < "$path"
    fi
    [ "$lines" -ge "$need" ] || exit 0 ;;
esac

: > "${gate_dir}/${session}-read-${who}-${name}" 2>/dev/null || true
exit 0
