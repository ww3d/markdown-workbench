#!/usr/bin/env bash
#
# PreToolUse hook — point-of-use rule gate. Generic, byte-identical across
# consumers.
#
# AGENTS.md, section "Session Start: Read Before Anything Else", building block
# 3: before the FIRST action of a trigger type in a session, the matching rule
# file under .agents/rules/ is read in full and receipted as
#
#   rule | .agents/rules/pr.md | <blob SHA> | read
#
# This hook is what turns that from an expectation into a gate. It maps the tool
# call about to run onto its trigger(s), looks for the receipt in the transcript,
# and blocks while one is missing.
#
# Two stages, because a bare refusal only helps an agent that knows what to do
# with it:
#   1. first block for a trigger — deny, naming the file to read and the receipt
#      line to emit.
#   2. every block after that for the SAME trigger in the SAME session — deny
#      again, with the rule file's full text inside the denial reason. The reason
#      is the one field guaranteed to reach the model, which is why the text goes
#      there rather than into additionalContext.
# The stage is remembered in a per-session marker file under TMPDIR, not in the
# transcript: a hook's own denial is not something it can reliably read back.
#
# Fail-open by design, like require-receipt.sh: a missing jq, an unreadable
# transcript, an unparsable payload or an absent rule file all exit 0 (allow).
# The gate enforces only where it can decide with confidence — a wedged session
# is a worse failure than a missed receipt.
#
# A rule file that does not exist in the repository never blocks anything, so a
# repo that has not received the .agents/rules/ mirror yet behaves exactly as
# before.
#
# Stdin:  the PreToolUse event JSON ({ session_id, transcript_path, cwd,
#         tool_name, tool_input, ... }).
# Stdout: only when blocking — hookSpecificOutput with permissionDecision "deny".

set -euo pipefail

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$input" | jq -r "$1" 2>/dev/null || true; }

tool="$(field '.tool_name // empty')"
[ -n "$tool" ] || exit 0

transcript="$(field '.transcript_path // empty')"
session="$(field '.session_id // empty')"
cwd="$(field '.cwd // empty')"
ROOT="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"
[ -d "${ROOT}/.agents/rules" ] || exit 0

# --- which trigger(s) does this call belong to? -----------------------------
# The mapping is deliberately conservative: a call that cannot be classified
# with confidence maps to nothing and passes. Over-blocking would train the
# agent to work around the gate, which costs more than the receipt is worth.
triggers=()
add_trigger() {
  local existing
  for existing in ${triggers[@]+"${triggers[@]}"}; do
    if [ "$existing" = "$1" ]; then return 0; fi
  done
  triggers+=("$1")
}

path="$(field '.tool_input.file_path // .tool_input.notebook_path // empty')"
command_line="$(field '.tool_input.command // empty')"

case "$tool" in
  mcp__github__create_pull_request|mcp__github__update_pull_request)
    add_trigger pr; add_trigger evidence ;;
  mcp__github__pull_request_review_write|mcp__github__add_comment_to_pending_review|\
mcp__github__add_reply_to_pull_request_comment)
    add_trigger review; add_trigger evidence ;;
  mcp__github__issue_write|mcp__github__sub_issue_write)
    add_trigger carrier ;;
  mcp__github__add_issue_comment)
    add_trigger evidence ;;
  Bash)
    case "$command_line" in
      *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*) add_trigger pr; add_trigger evidence ;;
    esac
    case "$command_line" in
      *"gh pr review"*) add_trigger review; add_trigger evidence ;;
    esac
    case "$command_line" in
      *"gh issue create"*|*"gh issue edit"*|*"gh issue close"*) add_trigger carrier ;;
    esac
    ;;
  Write|Edit|NotebookEdit)
    # Only files inside the project: a scratch file in TMPDIR is not repository
    # work and owes no rule reading.
    case "$path" in
      "${ROOT}"/*)
        relative="${path#"${ROOT}"/}"
        case "$relative" in
          audit/ist-stand-*) add_trigger audit ;;
        esac
        case "$relative" in
          *.md) add_trigger docs ;;
          *) add_trigger code ;;
        esac
        ;;
    esac
    ;;
esac

[ "${#triggers[@]}" -gt 0 ] || exit 0

# --- is the receipt in the transcript? --------------------------------------
# "true" / "false"; anything else (no transcript, jq error) counts as present,
# which is the fail-open direction.
receipt_present() {
  local needle="rule | $1 |"
  local answer
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  answer="$(jq -rs --arg needle "$needle" '
      [ .[]
        | select(.type == "assistant")
        | .message.content[]?
        | select(.type == "text")
        | .text ]
      | any(contains($needle))
  ' "$transcript" 2>/dev/null || true)"
  [ "$answer" = "false" ] && return 1
  return 0
}

deny() {
  local trigger="$1" rule="$2" reason marker=""
  # An empty session_id has no marker at all, and therefore never reaches stage
  # 2: a fixed fallback name would be shared by every such run, so the next
  # session would open on the stage-2 answer and the state would outlive any
  # number of sessions. Stage 1 repeated is the safe degradation - it still
  # blocks and still says what to do, it just never escalates.
  if [ -n "$session" ]; then
    marker="${TMPDIR:-/tmp}/claude-rule-gate/${session}-${trigger}"
    mkdir -p "$(dirname "$marker")" 2>/dev/null || true
  fi

  if [ -n "$marker" ] && [ -e "$marker" ]; then
    # Stage 2 — the instruction alone did not land, so the file itself goes
    # into the reason. It is the whole file on purpose: a summary here would be
    # the rule copy AGENTS.md forbids.
    reason="$(printf '%s\n\n----- BEGIN %s -----\n%s\n----- END %s -----\n\n%s\n' \
      "Blocked again: the point-of-use receipt for '${rule}' is still missing. Its full text follows; read it, then emit the receipt line and retry." \
      "$rule" "$(cat "${ROOT}/${rule}")" "$rule" \
      "Receipt line: rule | ${rule} | <blob SHA> | read")"
  else
    # `if` rather than `[ ... ] && ...`, to read the same way as the guard that
    # builds the marker above. (`set -e` is no argument for it either way: bash
    # exempts every command in an && list but the last, so a failing test there
    # would not end the hook.)
    if [ -n "$marker" ]; then : > "$marker" 2>/dev/null || true; fi
    reason="$(printf '%s\n%s\n' \
      "Point-of-use rule gate (AGENTS.md, section \"Session Start: Read Before Anything Else\", building block 3): this is the first '${trigger}' action of the session and '${rule}' has not been receipted." \
      "Read ${rule} in full, emit the receipt line 'rule | ${rule} | <blob SHA> | read', then retry this call.")"
  fi

  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
}

for trigger in "${triggers[@]}"; do
  rule=".agents/rules/${trigger}.md"
  [ -f "${ROOT}/${rule}" ] || continue
  if receipt_present "$rule"; then continue; fi
  deny "$trigger" "$rule"
  exit 0
done

exit 0
