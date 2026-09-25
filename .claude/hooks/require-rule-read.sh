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
# Cost. The hook is registered without a matcher, so it runs before EVERY tool
# call, and under Git Bash every process start costs tens of milliseconds
# (issue ww3d/playbook#276 measured ~0.5 s per call for six separate jq starts). Hence three
# steps, each paid only when the one before could not decide:
#   1. the raw payload, with bash builtins only — no process at all for a tool
#      call that cannot map to a trigger (Read, Grep, a Bash call without gh);
#   2. one jq start that pulls every field at once;
#   3. the transcript, only when a trigger is mapped and its rule file exists,
#      in one grep+jq pass for all of the call's triggers together.
#
# Windows. Claude Code hands file paths and CLAUDE_PROJECT_DIR over with
# backslashes and a drive letter (D:\repo\docs\x.md), runs shell commands
# through a PowerShell tool as well as through Bash, and names the claude.ai
# GitHub connector mcp__claude_ai_GitHub_MCP__* instead of mcp__github__*. All
# three are classified like their POSIX / CLI counterparts (issue ww3d/playbook#276).
#
# Stdin:  the PreToolUse event JSON ({ session_id, transcript_path, cwd,
#         tool_name, tool_input, ... }).
# Stdout: only when blocking — hookSpecificOutput with permissionDecision "deny".

set -euo pipefail

# `read` rather than "$(cat)": a builtin, so no process start on the path every
# single tool call takes. -d '' reads to EOF and then returns 1, hence || true.
IFS= read -r -d '' input || true

# --- step 1: can this call map to a trigger at all? --------------------------
# Matched on the raw JSON, which is safe in the one direction that matters: a
# key "tool_name" can only match where it is a real key (inside a JSON string
# every quote is escaped, so `"tool_name"` cannot occur there), and the gh
# phrases contain no character JSON escapes, so a decoded command that holds one
# holds it verbatim in the raw text too. A false positive here costs only the
# jq start of step 2; a false negative is impossible.
tool_re='"tool_name"[[:space:]]*:[[:space:]]*"(Bash|PowerShell|Write|Edit|NotebookEdit|mcp__[^"]*)"'
[[ $input =~ $tool_re ]] || exit 0
case "${BASH_REMATCH[1]}" in
  Bash|PowerShell)
    case "$input" in
      *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*|*"gh pr review"*|*"gh pr comment"*|\
*"gh issue create"*|*"gh issue edit"*|*"gh issue close"*|*"gh issue comment"*) ;;
      *) exit 0 ;;
    esac ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

# --- step 2: every field in one jq start --------------------------------------
# @sh quotes each value for the shell, so eval assigns them verbatim. One line,
# printed with -j (no newline at all): jq for Windows writes every newline as
# CRLF, and a CR outside the quotes would become part of a value. An
# unparsable payload makes jq print nothing, every field stays empty, and the
# empty tool name below allows the call.
tool="" transcript="" session="" cwd="" path="" command_line=""
eval "$(jq -j '@sh "tool=\(.tool_name // "") transcript=\(.transcript_path // "") session=\(.session_id // "") cwd=\(.cwd // "") path=\(.tool_input.file_path // .tool_input.notebook_path // "") command_line=\(.tool_input.command // "")"' \
  <<<"$input" 2>/dev/null || true)"
[ -n "$tool" ] || exit 0

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

# One spelling for both sides of the project-root comparison: backslashes
# become slashes, a drive letter D:/x becomes /D/x (the Git Bash / MSYS form,
# so either spelling meets the other), and a trailing slash goes.
normalize_path() {
  local p="${1//\\//}"
  case "$p" in
    [A-Za-z]:/*) p="/${p:0:1}${p:2}" ;;
  esac
  normalized="${p%/}"
}

case "$tool" in
  # Any GitHub MCP server, whatever the harness calls it: mcp__github__* in
  # Claude Code with a local server, mcp__claude_ai_GitHub_MCP__* for the
  # claude.ai connector. The server segment is everything before the last "__".
  mcp__*[Gg]it[Hh]ub*__*)
    case "${tool##*__}" in
      create_pull_request|update_pull_request)
        add_trigger pr; add_trigger evidence ;;
      pull_request_review_write|add_comment_to_pending_review|add_reply_to_pull_request_comment)
        add_trigger review; add_trigger evidence ;;
      issue_write|sub_issue_write)
        add_trigger carrier ;;
      add_issue_comment)
        add_trigger evidence ;;
    esac
    ;;
  Bash|PowerShell)
    case "$command_line" in
      *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*) add_trigger pr; add_trigger evidence ;;
    esac
    case "$command_line" in
      *"gh pr review"*) add_trigger review; add_trigger evidence ;;
    esac
    case "$command_line" in
      *"gh issue create"*|*"gh issue edit"*|*"gh issue close"*) add_trigger carrier ;;
    esac
    # A comment is the CLI's counterpart of the MCP add_issue_comment above.
    case "$command_line" in
      *"gh pr comment"*|*"gh issue comment"*) add_trigger evidence ;;
    esac
    ;;
  Write|Edit|NotebookEdit)
    # Only files inside the project: a scratch file in TMPDIR is not repository
    # work and owes no rule reading.
    normalize_path "$ROOT"; root_n="$normalized"
    normalize_path "$path"; path_n="$normalized"
    # A drive letter on either side means Windows, whose paths compare without
    # regard to case (D:\Repo and d:\repo are the same file); anywhere else the
    # comparison stays exact.
    case "$ROOT$path" in
      *[A-Za-z]:[\\/]*) shopt -s nocasematch ;;
    esac
    if [[ $path_n == "$root_n"/* ]]; then
      relative="${path_n:${#root_n}+1}"
      case "$relative" in
        audit/ist-stand-*) add_trigger audit ;;
      esac
      case "$relative" in
        *.md) add_trigger docs ;;
        *) add_trigger code ;;
      esac
    fi
    shopt -u nocasematch
    ;;
esac

# Only triggers whose rule file this repository carries, and whose receipt this
# session has not already been found to hold, can block. A found receipt is
# remembered per session and trigger in a marker file next to the stage-2
# marker (see deny below), so each trigger costs one transcript read per
# session rather than one per tool call - a session editing fifty files reads
# its transcript once for "code", not fifty times. An empty session_id has no
# marker, as in deny, and simply reads every time. A compaction ends a marker's
# life: read-confirm.sh deletes the session's markers on source "compact".
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
pending=()
for trigger in ${triggers[@]+"${triggers[@]}"}; do
  [ -f "${ROOT}/.agents/rules/${trigger}.md" ] || continue
  if [ -n "$session" ] && [ -e "${gate_dir}/${session}-${trigger}.receipted" ]; then continue; fi
  pending+=("$trigger")
done
[ "${#pending[@]}" -gt 0 ] || exit 0

# --- step 3: which receipts are in the transcript? ---------------------------
# Sets `receipted` to the newline-framed list of rule paths whose receipt was
# found. Returns 1 when that could not be established (no transcript, grep or
# jq failing), which the caller treats as "every receipt present" - the
# fail-open direction.
#
# Two sources count, additively:
#   - a plain assistant text block (the documented case);
#   - a command the session RAN to print the line: a tool_use whose
#     .input.command carries the receipt line AND whose own tool_result (same
#     tool_use_id, not is_error) shows it too. Text between tool calls can come
#     out of the model as thinking and then never lands in the transcript as
#     text, so an echoed receipt is the dependable way;
#     but a command that merely carries the line as data does not count
#     (issue ww3d/playbook#273) - a `gh pr comment --body "... rule | ..."` about to run
#     would otherwise unlock itself, a refused one would unlock everything
#     after it, and `cat > f <<EOF` would count a file write. Neither of those
#     prints the line back, which is what the result check asks for.
#
# Only what stands after the newest compaction counts. AGENTS.md, section
# "Session Start: Read Before Anything Else", has every point-of-use receipt
# lapse at a compaction; the transcript file runs on through it, so the cut is
# read from the file itself. Claude Code marks a compaction twice, measured on
# Windows transcripts (Claude Code 2.1.281, 25 compactions): a line
# {"type":"system","subtype":"compact_boundary"} that it always writes, and an
# attachment with hookName "SessionStart:compact" that exists only where a
# SessionStart hook ran. Either one cuts. The per-session marker files are
# cleared by read-confirm.sh at the same moment (source "compact").
#
# grep -F narrows the transcript to the lines that carry any of the needles at
# all (a needle holds no character JSON escapes, so the raw line carries it
# verbatim; the tool_use and its tool_result both carry it); jq then judges only
# those few lines, one at a time (-R + fromjson?), so one truncated line - a
# write in progress - is skipped rather than failing the whole read (same fix
# as require-receipt.sh's REQ-015). The jq step is what keeps any other line -
# the hook's own denial quotes the receipt line - from counting.
receipted=""
read_receipts() {
  local needles=() rules=() trigger out status
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  for trigger in "${pending[@]}"; do
    rules+=(".agents/rules/${trigger}.md")
    needles+=(-e "rule | .agents/rules/${trigger}.md |")
  done
  needles+=(-e "compact_boundary" -e "SessionStart:compact")
  # The trailer line carries both exit codes out of the substitution: grep 1 is
  # "no line matched", a positive finding that no receipt exists; grep 2 is a
  # read error.
  out="$(grep -F "${needles[@]}" -- "$transcript" 2>/dev/null \
    | jq -nRr '
        [ inputs | fromjson? // empty ] as $all
      | ([ $all | to_entries[]
           | select((.value.type == "system" and .value.subtype == "compact_boundary")
                    or (.value.type == "attachment"
                        and .value.attachment.hookName? == "SessionStart:compact"))
           | .key ] | last // -1) as $cut
      | [ $all | to_entries[] | select(.key > $cut) | .value ] as $in
      | [ $in[] | select(.type == "assistant") | .message.content[]? ] as $said
      | [ $in[] | select(.type == "user") | .message.content[]?
          | select(.type == "tool_result" and .is_error != true
                   and (.tool_use_id | type == "string"))
          | { key: .tool_use_id,
              value: (.content | if type == "string" then .
                                 elif type == "array" then map(.text? // "" | strings) | join("\n")
                                 else "" end) } ]
        | from_entries as $printed
      | $ARGS.positional[] as $rule
      | ("rule | " + $rule + " |") as $n
      | select($said | any(
            (.type == "text" and (.text | type == "string") and (.text | contains($n)))
         or (.type == "tool_use" and (.id | type == "string")
             and (.input.command? | type == "string") and (.input.command | contains($n))
             and ($printed[.id] // "" | contains($n)))))
      | $rule
    ' --args "${rules[@]}" 2>/dev/null
    printf '\n#status %s %s' "${PIPESTATUS[0]}" "${PIPESTATUS[1]}")" || return 1
  out="${out//$'\r'/}" # jq for Windows ends its lines with CRLF
  status="${out##*#status }"
  case "$status" in
    "0 0"|"1 0") ;;
    *) return 1 ;;
  esac
  receipted=$'\n'"${out%#status *}"$'\n'
}

read_receipts || exit 0

deny() {
  local trigger="$1" rule="$2" reason marker=""
  # An empty session_id has no marker at all, and therefore never reaches stage
  # 2: a fixed fallback name would be shared by every such run, so the next
  # session would open on the stage-2 answer and the state would outlive any
  # number of sessions. Stage 1 repeated is the safe degradation - it still
  # blocks and still says what to do, it just never escalates.
  if [ -n "$session" ]; then
    marker="${gate_dir}/${session}-${trigger}"
    mkdir -p "$gate_dir" 2>/dev/null || true
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
    reason="$(printf '%s\n%s\n%s\n' \
      "Point-of-use rule gate (AGENTS.md, section \"Session Start: Read Before Anything Else\", building block 3): this is the first '${trigger}' action of the session and '${rule}' has not been receipted." \
      "Read ${rule} in full, emit the receipt line 'rule | ${rule} | <blob SHA> | read', then retry this call." \
      "Emit it where the gate can see it: print it with a command of its own (e.g. echo), or make it the closing text of a turn. Text written between tool calls may never reach the transcript, and a line that a command merely carries as data does not count.")"
  fi

  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
}

for trigger in "${pending[@]}"; do
  rule=".agents/rules/${trigger}.md"
  case "$receipted" in
    *$'\n'"$rule"$'\n'*)
      if [ -n "$session" ]; then
        mkdir -p "$gate_dir" 2>/dev/null || true
        : > "${gate_dir}/${session}-${trigger}.receipted" 2>/dev/null || true
      fi
      continue ;;
  esac
  deny "$trigger" "$rule"
  exit 0
done

exit 0
