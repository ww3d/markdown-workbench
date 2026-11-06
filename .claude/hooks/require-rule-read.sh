#!/usr/bin/env bash
#
# PreToolUse hook — point-of-use rule gate. Generic, byte-identical across
# consumers.
#
# AGENTS.md, section "Session Start: Read Before Anything Else", step 3: before
# the FIRST action of a trigger type in a session, the matching rule file under
# .agents/rules/ is read in full.
#
# This hook is what turns that from an expectation into a gate. It maps the tool
# call about to run onto its trigger(s) and blocks while the file was not read.
# Two sources count, either one is enough:
#   1. the read itself - record-rule-read.sh (PostToolUse on Read) leaves a marker
#      file per session, reader and trigger under ${TMPDIR}/claude-rule-gate/;
#      a sub-agent that read the file itself passes, one that did not is
#      refused (its marker carries its agent_id);
#   2. the typed receipt line in the transcript (AGENTS.md, section "Session Start"),
#        + pr.md        24.1.0   <blob SHA>   read (rule)
#      the file named relative to .agents/rules/ (a local rule as local/<name>.md),
#      any other file by its repository path; the earlier form
#        rule | .agents/rules/pr.md | <blob SHA> | read
#      is read until playbook 26.0.0 (ww3d/playbook#366). Kept as a second source for
#      harnesses that run no PostToolUse hook.
# The denial names the path and the blob SHA of the file and nothing else - the
# text of the rule never travels through the hook.
#
# Second gate, same hook: a pull-request review post (`gh pr review`; a `gh api` call that creates, submits or
# edits a review - POST to pulls/<n>/reviews or .../reviews/<id>/events, PUT to .../reviews/<id>; a `gh api graphql`
# call with addPullRequestReview, submitPullRequestReview or updatePullRequestReview; the connector's
# pull_request_review_write) is refused unless /pr-poll-review ran for the PR's CURRENT head in this transcript, and
# the posting agent read the skill's gates.md and checks.md in full - see review_gate below. Each `gh api` call is
# read from its words (lib/segments.awk), its method as gh sends it (`-X` wins, else a field or `--input` makes a
# POST). A read (GET) and a deletion owe nothing; a dismissal (PUT .../reviews/<id>/dismissals,
# dismissPullRequestReview) is the merger's step and owes pr.md alone. A heredoc body that only data takes holds no
# post (lib/heredoc.sh); one an interpreter reads does (a listed command that can start a shell, a git alias or
# `gh alias --shell`, is not followed), and a GraphQL mutation counts anywhere in the command once it holds a
# `gh api graphql` call. A post that names no repo is checked for the repo of a folder changed to before it (`cd`),
# else of the origin remote; one whose folder cannot be read is refused. The gate does not see a query read from a
# file or a command substitution (`-F query=@file`, `--input q.json`), a `review-head` line the agent printed itself
# instead of the skill's gate step, a command built in a variable, or a script file that posts: it is a guard
# against the honest slip, not against a determined bypass.
#
# Third gate, ahead of both: after a compaction the main thread is locked until it has read the
# restore file and, where due, the cross-check result - see compact_lock. A rule file is no part of it:
# one with a trigger or `gate:` is read again before the next action of its kind (steps 1-3 below),
# chat.md and a local rule without `gate:` by the list in the restore file, which names only what was read before.
#
# Fail-open by design, like require-receipt.sh: a missing jq, an unreadable
# transcript, an unparsable payload or an absent rule file all exit 0 (allow);
# a missing or failing awk (or lib/segments.awk) lets the review gate pass, the
# other gates of the call still run.
# The gate enforces only where it can decide with confidence — a wedged session
# is a worse failure than a missed receipt.
#
# A rule file that does not exist in the repository never blocks anything, so a
# repo that has not received the .agents/rules/ mirror yet behaves exactly as
# before.
#
# Cost. The hook is registered with a matcher naming exactly the tools tool_re
# below accepts (a test holds the two equal), so Read, Grep, Glob, a non-GitHub MCP
# tool and the like never start it. Every call it does see still costs a bash start,
# and under Git Bash every process start costs tens of milliseconds, so separate jq
# starts add up per call (issue ww3d/playbook#276). The payload is read with `cat` through
# lib/stdin.sh (a byte-by-byte `read` costs about 4.5 ms per KB; `$(</dev/stdin)` fails under Git Bash). Ahead of them step 0, the lock after
# a compaction: without a lock file one regex and one file test; with one, per call tail and awk
# over the transcript's last 400 lines (a full awk pass only where they hold no turn start with a uuid).
# Then three steps, each paid only when the one before could not decide:
#   1. the raw payload, with bash builtins only — no further process for a call
#      that cannot map to a trigger (a Bash or PowerShell call without gh);
#   2. one jq start that pulls every field at once;
#   3. the transcript, only when a trigger is mapped and its rule file exists,
#      in one grep+jq pass for all of the call's triggers together.
# A Bash or PowerShell call whose text holds `gh` with `pr`, `issue` or `api` pays, before step 3, for one awk run of
# lib/segments.awk that splits the command (its time grows with the command's length, not faster), the reading of
# its `gh` records and, with `<<`, the heredoc parse - builtins only.
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

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
read_hook_payload
input="$hook_input"

# --- step 1: can this call map to a trigger at all? --------------------------
# Matched on the raw JSON, which is safe in the one direction that matters: a
# key "tool_name" can only match where it is a real key (inside a JSON string
# every quote is escaped, so `"tool_name"` cannot occur there), and the gh
# phrases contain no character JSON escapes, so a decoded command that holds one
# holds it verbatim in the raw text too. A false positive here costs only the
# jq start of step 2; a false negative is impossible.
#
# A skill that starts work with its own rules raises the trigger of the one table below (ww3d/playbook#526): a design
# round or a state audit raises `audit`, a handover (`chat-handoff`) raises `session`. Both ways the skill starts count:
# the Skill tool call (`Skill` in tool_re below) and the typed `/ccweb-prompt`, which no PreToolUse hook sees. For the
# typed one this hook is also registered on UserPromptExpansion: it leaves the marker `<session>-<trigger>-owed` and
# hands Claude the hint to read the rule file first; it never blocks the expansion. While a marker stands, every call
# this hook sees owes its trigger too (the read of the rule file or its receipt line lifts it, that marker only).
# Skill names count with or without a namespace (`anthropic-skills:ccweb-prompt`). The UserPromptExpansion matcher of
# both settings.json files names the same skills; a test holds them equal.
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
sid0_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
skill_table=(ccweb-prompt:audit state-audit:audit chat-handoff:session) # skill:trigger, the one place of the mapping
skill_alt="" skill_trigs=" "
for skill_e in "${skill_table[@]}"; do
  skill_alt+="${skill_alt:+|}${skill_e%%:*}"
  case "$skill_trigs" in *" ${skill_e#*:} "*) ;; *) skill_trigs+="${skill_e#*:} " ;; esac
done
skill_trigger() { # skill name -> global skill_trig; status 1 for a skill the table does not know
  local e
  for e in "${skill_table[@]}"; do
    if [ "${e%%:*}" = "$1" ]; then skill_trig="${e#*:}"; return 0; fi
  done
  return 1
}
upe_re='"hook_event_name"[[:space:]]*:[[:space:]]*"UserPromptExpansion"'
if [[ $input =~ $upe_re ]]; then
  cn_re='"command_name"[[:space:]]*:[[:space:]]*"/?([A-Za-z0-9_.-]+:)?('"$skill_alt"')"'
  if [[ $input =~ $cn_re ]]; then
    upe_name="${BASH_REMATCH[2]}"
    skill_trigger "$upe_name" || exit 0
    if [[ ${input:0:2000} =~ $sid0_re ]]; then
      # The hint is promised only where the marker stands and the rule file exists: elsewhere nothing is gated.
      mkdir -p "$gate_dir" 2>/dev/null || true
      printf '%s' "$upe_name" > "${gate_dir}/${BASH_REMATCH[1]}-${skill_trig}-owed" 2>/dev/null &&
      [ -f "${CLAUDE_PROJECT_DIR:-$PWD}/.agents/rules/${skill_trig}.md" ] &&
      printf '{"hookSpecificOutput":{"hookEventName":"UserPromptExpansion","additionalContext":"Rule gate (ww3d/playbook#526): /%s starts work that owes .agents/rules/%s.md; before the first action read it in full with the Read tool - until then every gated call is refused."}}\n' "$upe_name" "$skill_trig"
    fi
  fi
  exit 0
fi
tool_re='"tool_name"[[:space:]]*:[[:space:]]*"(Bash|PowerShell|Write|Edit|NotebookEdit|Agent|Task|Workflow|Skill|mcp__[^"]*[Gg]it[Hh]ub[^"]*)"'
[[ $input =~ $tool_re ]] || exit 0
call_tool="${BASH_REMATCH[1]}"
# The markers "<trigger> owed" of THIS session (one file test per trigger, no process start): without one, a Skill
# call of another name and a Bash call without gh stay as cheap as before, whatever markers other sessions left.
owed_any=0
if [[ ${input:0:2000} =~ $sid0_re ]]; then
  sid0="${BASH_REMATCH[1]}"
  for owed_t in $skill_trigs; do
    if [ -e "${gate_dir}/${sid0}-${owed_t}-owed" ]; then owed_any=1; fi
  done
fi

# --- step 0: the lock after a compaction (ww3d/playbook#439) -----------------
# restore-compact-state.sh writes <session>-compact-lock with one `need=<marker> <path>` line per
# file the main thread reads in full after the compaction (record-rule-read.sh leaves the marker).
# Until each is read, every call this hook sees is denied - an Agent or Task call naming cross-check.md excepted, which
# starts the cross-check helper. Sub-agents are free. Valve, fail-open: a need whose file is gone
# (the cross-check result excepted, which the helper writes), any error, and the third denial in
# one turn - the rest of the turn passes. A turn starts at the last user line that is no tool result,
# meta line or compaction summary. Without a lock file this costs one regex and one file test.
# The loss check the restore could not run while the summary was not written yet (ww3d/playbook#487): once the
# summary stands after `to`, the inputs of the maintainer whose key words it lacks - the same rule as in
# restore-compact-state.sh - go to the end of the restore file, the lock's line turns to loss=done, and where an
# input was lost the restore file counts as unread again. Any failure leaves the line pending.
late_loss_check() { # dir, session, lock
  local dir="$1" sid="$2" lock="$3" to="" t="" restore="" l out n ins="${1}/${2}-compact-loss-inputs.json"
  command -v jq >/dev/null 2>&1 && [ -r "$ins" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      to=*) to="${l#to=}" ;;
      transcript=*) t="${l#transcript=}" ;;
      "need=compact.restore "*) restore="${l#need=compact.restore }" ;;
    esac
  done < "$lock"
  [[ $to =~ ^[0-9]+$ ]] && [ -r "$t" ] && [ -f "$restore" ] || return 0
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables
  out="$(tail -n +"$((to + 1))" "$t" 2>/dev/null | jq -nRr --slurpfile ins "$ins" '
    def ctext: if (.message.content | type) == "string" then .message.content
      elif (.message.content | type) == "array" then [.message.content[] | select(.type? == "text") | .text] | join("\n")
      else "" end;
    def keys_of: ascii_downcase | [scan("[\\p{L}\\p{N}_]{5,}")] | unique;
    ([inputs | (fromjson? // null) | select(. != null and .isCompactSummary == true) | ctext] | first) as $s
    | if $s == null then empty
      else ($s | ascii_downcase) as $sum
      | [$ins[0][] | . as $t | (keys_of) as $k | select(($k | length) > 0)
         | select(([$k[] | select(. as $w | $sum | contains($w))] | length) * 2 < ($k | length))
         | $t | gsub("\\s+"; " ") | if length > 120 then .[0:117] + "..." else . end]
      | if length == 0 then "0\nEvery input of the maintainer since the previous compaction has its key words in the summary."
        else "\(length)\nMissing from the summary (\(length), newest first):\n\n"
          + (reverse | map("- \"" + . + "\"") | join("\n")) end end' 2>/dev/null)" || return 0
  n="${out%%$'\n'*}"; n="${n%$'\r'}"
  [[ $n =~ ^[0-9]+$ ]] || return 0
  printf '\n## Loss check after the summary arrived\n\n%s\n' "${out#*$'\n'}" | tr -d '\r' >> "$restore" 2>/dev/null || return 0
  { grep -v '^loss=pending$' "$lock"; printf 'loss=done\n'; } > "${lock}.tmp" 2>/dev/null && mv -f "${lock}.tmp" "$lock" 2>/dev/null
  [ "$n" = 0 ] || rm -f "${dir}/${sid}-read-main-compact.restore" "${dir}/${sid}-read-main-compact.restore.upto" 2>/dev/null
  return 0
}
started_now="" # the helper's started marker this call wrote (compact_lock), taken back on a later denial
compact_lock() {
  local dir="${TMPDIR:-/tmp}/claude-rule-gate" sid="$1" l name file missing="" helper="" from="" to="" lines="" t="" turn
  local count=0 key=""
  local lock="${dir}/${sid}-compact-lock" denies="${dir}/${sid}-compact-lock-denies"
  local started="${dir}/${sid}-cross-check-started" send_re="${PLAYBOOK_LOCK_SEND_RE:-}" phase=1 age="?"
  [ -f "$lock" ] || return 0
  local agent_re='"agent_id"[[:space:]]*:[[:space:]]*"[^"]'
  [[ ! $input =~ $agent_re ]] || return 0
  ! grep -q '^loss=pending$' "$lock" 2>/dev/null || late_loss_check "$dir" "$sid" "$lock"
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      from=*) from="${l#from=}" ;;
      to=*) to="${l#to=}" ;;
      lines=*) lines="${l#lines=}" ;;
      transcript=*) t="${l#transcript=}" ;;
      need=*)
        l="${l#need=}"; name="${l%% *}"; file="${l#* }"
        [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || continue
        [ ! -e "${dir}/${sid}-read-main-${name}" ] || continue
        if [ "$name" = compact.crosscheck ]; then helper="$file"
        elif [ -f "$file" ]; then missing="${missing}"$'\n'"- $file"; fi ;;
    esac
  done < "$lock" || return 0
  if [ -z "$missing" ] && [ -z "$helper" ]; then
    # Released: a cross-check that was needed is done up to `to`.
    if grep -q '^need=compact\.crosscheck ' "$lock" 2>/dev/null && [[ $to =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$to" > "${dir}/${sid}-cross-check-mark" 2>/dev/null || true
    fi
    rm -f "$lock" "$denies" "$started" 2>/dev/null || true
    return 0
  fi
  # The cross-check helper is the one sub-agent the lock lets start (ww3d/playbook#487): an Agent/Task
  # call whose input names cross-check.md passes and marks the helper as started; any other Agent/Task
  # call is held in phase 1 like every other call.
  case "$call_tool" in
    Agent|Task)
      # The marker stands only for this call; a later gate of this hook that denies it takes the marker back
      # (emit_decision), so a denied helper start never opens phase 2.
      case "$input" in
        *cross-check.md*)
          if [ ! -e "$started" ] && : > "$started" 2>/dev/null; then started_now="$started"; fi
          return 0 ;;
      esac ;;
  esac
  # Phase 2 (ww3d/playbook#487) kicks in once every need but compact.crosscheck is read AND the
  # helper has started (the started marker). It holds only a Bash/PowerShell call whose command line
  # matches the regex in PLAYBOOK_LOCK_SEND_RE; an empty or unset variable passes every call, a
  # non-shell tool passes. Phase 1 (something else unread, or the helper not started) locks as
  # before, and the valve below is shared by both phases.
  if [ -z "$missing" ] && [ -n "$helper" ] && [ -e "$started" ]; then
    phase=2
    case "$call_tool" in
      Bash|PowerShell) ;;
      *) return 0 ;;
    esac
    [ -n "$send_re" ] || return 0
    # The call's command line, read from the first "tool_input.command" of the raw payload (step 2
    # has not run yet). JSON string escapes are unescaped; a false positive here only widens the
    # lock, never relaxes it (fail-closed side of the match).
    local cmd_re='"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"' cmd=""
    if [[ $input =~ $cmd_re ]]; then
      cmd="${BASH_REMATCH[1]}"
      cmd="${cmd//\\\"/\"}"; cmd="${cmd//\\\\/\\}"
      cmd="${cmd//\\n/$'\n'}"; cmd="${cmd//\\t/$'\t'}"
      cmd="${cmd//\\\//\/}"
    fi
    [[ $cmd =~ $send_re ]] || return 0
    # The helper's running time, from the marker's mtime, in whole minutes.
    local m now
    if m="$(date -r "$started" +%s 2>/dev/null)" && [[ $m =~ ^[0-9]+$ ]] \
       && now="$(date +%s 2>/dev/null)" && [[ $now =~ ^[0-9]+$ ]]; then
      age=$(( (now - m) / 60 ))
    fi
  fi
  # The turn's key is that user line's uuid: the same from the last 400 lines and from the whole file,
  # so awk reads the tail first and the whole file only where the tail holds no such line. A line
  # without a uuid is keyed by its line number, which only the whole file gives.
  # shellcheck disable=SC2016 # `$0` belongs to awk, not to the shell
  local prog='/"type":"user"/ && !/"tool_use_id"/ && !/"isMeta":true/ && !/"isCompactSummary":true/ {
    k = "line" NR; if (match($0, /"uuid":"[^"]*"/)) k = substr($0, RSTART + 8, RLENGTH - 9) } END { print k }'
  turn=0
  if [ -n "$t" ] && [ -r "$t" ]; then
    turn="$(tail -n 400 "$t" 2>/dev/null | awk "$prog" 2>/dev/null)" || turn=""
    case "$turn" in ""|line*) turn="$(awk "$prog" "$t" 2>/dev/null)" || turn="" ;; esac
    [[ $turn =~ ^[A-Za-z0-9_-]+$ ]] || turn=0
  fi
  # Read, count, write is not atomic: parallel calls of one answer may each read the same count and
  # write the same next one, so the valve can take more than three denials (bounded, fail-closed side).
  if [ -r "$denies" ]; then read -r key count < "$denies" 2>/dev/null || true; fi
  [ "$key" = "$turn" ] && [[ $count =~ ^[0-9]+$ ]] || count=0
  [ "$count" -lt 3 ] || return 0
  count=$((count + 1))
  printf '%s %s\n' "$turn" "$count" > "$denies" 2>/dev/null || return 0
  local msg
  if [ "$phase" = 2 ]; then
    msg="Phase 2 of the compaction lock (ww3d/playbook#487): the cross-check helper is running (started ${age} minutes ago). This Bash/PowerShell call matches PLAYBOOK_LOCK_SEND_RE (/${send_re}/) and is held until the helper's result is read: ${helper}. Other tool calls pass. Valve: denial $count of 3 in this turn; after the third the rest of this turn passes."
  else
    msg="After the compaction this session is locked until it has read in full with the Read tool (in parts with offset and limit where a file is too large for one read):${missing}"
    # The range as the restore hint named it; a lock without `lines` (an older restore) counts from after `from`.
    [ -n "$lines" ] || { [[ $from =~ ^[0-9]+$ ]] && lines="$((from + 1))-$to"; } || lines="$from-$to"
    [ -z "$helper" ] || msg="$msg"$'\n'"- the cross-check result $helper - first start the helper on transcript $t, lines $lines, after the chat-handoff skill's reference/cross-check.md (only an Agent call whose prompt names cross-check.md passes)"
    msg="$msg"$'\n'"Sub-agents are not locked. Valve: denial $count of 3 in this turn; after the third the rest of this turn passes."
  fi
  msg="${msg//\\/\\\\}"; msg="${msg//\"/\\\"}"; msg="${msg//$'\n'/\\n}"; msg="${msg//$'\r'/}"; msg="${msg//$'\t'/ }"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
  exit 0
}
sid_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
if [[ ${input:0:2000} =~ $sid_re ]]; then compact_lock "${BASH_REMATCH[1]}" || true; fi

case "$call_tool" in
  Skill)
    skill_re='"skill"[[:space:]]*:[[:space:]]*"/?([A-Za-z0-9_.-]+:)?('"$skill_alt"')"'
    [[ $input =~ $skill_re || $owed_any = 1 ]] || exit 0 ;;
  Bash|PowerShell)
    if [ "$owed_any" != 1 ]; then
    shopt -s nocasematch
    case "$input" in
      *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*|*"gh pr review"*|*"gh pr comment"*|\
*"gh issue create"*|*"gh issue edit"*|*"gh issue close"*|*"gh issue comment"*) ;;
      *gh*api*"/reviews"*) ;;
      # a GraphQL review mutation, the query before or after the call
      *gh*api*PullRequestReview*|*PullRequestReview*gh*api*) ;;
      # gh with a path or .exe and more than one space between the words
      *gh*pr*review*) ;;
      *) exit 0 ;;
    esac
    shopt -u nocasematch
    fi ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

# --- step 2: every field in one jq start --------------------------------------
# @sh quotes each value for the shell, so eval assigns them verbatim. One line,
# printed with -j (no newline at all): jq for Windows writes every newline as
# CRLF, and a CR outside the quotes would become part of a value. An
# unparsable payload makes jq print nothing, every field stays empty, and the
# empty tool name below allows the call. Git Bash drops a CR inside eval'd quotes,
# so the command's CRs are settled in jq: CRLF becomes LF, any other CR a blank.
tool="" transcript="" session="" cwd="" path="" command_line="" agent="" skill_name="" mcp_owner="" mcp_repo="" mcp_pull="" mcp_method=""
eval "$(jq -j '@sh "tool=\(.tool_name // "") transcript=\(.transcript_path // "") session=\(.session_id // "") cwd=\(.cwd // "") path=\(.tool_input.file_path // .tool_input.notebook_path // "") command_line=\(.tool_input.command // "" | split("\r\n") | join("\n") | split("\r") | join(" ")) agent=\(.agent_id // "") skill_name=\(.tool_input.skill // "") mcp_owner=\(.tool_input.owner // "") mcp_repo=\(.tool_input.repo // "") mcp_pull=\(.tool_input.pullNumber // "" | tostring) mcp_method=\(.tool_input.method // "")"' \
  <<<"$input" 2>/dev/null || true)"
[ -n "$tool" ] || exit 0
# Whose reads count: the main thread, or one sub-agent (see record-rule-read.sh).
who="${agent:-main}"
# A sub-agent has its own transcript next to the main one, and what it printed
# lands there only. Measured with Claude Code 2.1.293: <main transcript without
# .jsonl>/subagents/agent-<agent_id>.jsonl.
if [ -n "$agent" ] && [ -f "${transcript%.jsonl}/subagents/agent-${agent}.jsonl" ]; then
  transcript="${transcript%.jsonl}/subagents/agent-${agent}.jsonl"
fi

ROOT="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"
[ -d "${ROOT}/.agents/rules" ] || exit 0

# --- which trigger(s) does this call belong to? -----------------------------
# The mapping is deliberately conservative: a call that cannot be classified
# with confidence maps to nothing and passes. Over-blocking would train the
# agent to work around the gate, which costs more than the receipt is worth.
triggers=()
review_post=0
post_i=0 review_src="" asg_repos=()

# The command, split once (ww3d/playbook#537): lib/segments.awk reads the command line in one pass and prints each
# command in command position as a record - its words unquoted, the GH_REPO= values and the folder in scope before
# it (the format stands at the top of segments.awk). A word inside a quoted text, a comment or a heredoc body that
# only data takes is no command. One awk start per call that holds `gh` with `pr`, `issue` or `api`; where awk is
# missing or fails, the review gate passes the call (fail-open); every other gate of the hook still runs.
seg_recs=() f=()
split_command() { # text -> global seg_recs; 1 where awk is missing or fails
  local out ps=""
  [ "$tool" != PowerShell ] || ps=1
  out="$(SEG_PS="$ps" LC_ALL=C awk -f "${BASH_SOURCE[0]%/*}/lib/segments.awk" <<<"$1" 2>/dev/null)" || return 1
  [ -z "$out" ] || mapfile -t seg_recs <<<"$out"
}
rec_fields() { # record -> global f: f[1] name, f[2] flags, f[3] length, f[4] review after, f[5] GH_REPO in scope,
  # f[6] every one in scope, f[7] folder state, f[8] index of the command word, f[9] nesting level; word k is f[9 + k]
  local IFS=$'\037'
  set -f
  # shellcheck disable=SC2206 # splitting at \037 is the point here; globbing is off
  f=($1)
  set +f
}
# A `gh` record's verb: `pr <sub>`, `issue <sub>` or `api`, options and their values allowed between the words
# (`gh -R o/r pr review 5`, `gh pr -R o/r review 5`). Sets verb ("review" for `pr review`) and verb_at (its field).
gh_subs=" create edit ready review comment close "
gh_verb() { # global f
  local j=$((9 + f[8] + 1)) n=${#f[@]} w prev=0 group=""
  verb="" verb_at=0
  while [ "$j" -lt "$n" ]; do
    w="${f[j],,}"
    if [[ $w == -* ]]; then prev=1
    elif [ -z "$group" ] && [ "$w" = api ]; then verb=api verb_at=$j; return 0
    elif [ -z "$group" ] && [[ $w == pr || $w == issue ]]; then group=$w prev=0
    elif [ -n "$group" ] && [[ $gh_subs == *" $w "* ]]; then
      verb="$group $w" verb_at=$j; [ "$verb" != "pr review" ] || verb=review
      return 0
    elif [ "$prev" = 1 ]; then prev=0
    else return 0; fi
    j=$((j + 1))
  done
}
# The path of a review endpoint: the PR, then a review id and its action where there are. A number given as a
# variable (`$PR`, `${PR}`) or a substitution is one the gate cannot read: the post takes the path of an unknown PR.
api_num='([0-9]+|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\$\(\.\.\.\))'
api_review_re="(^|/)pulls/${api_num}/reviews(/${api_num}(/([a-z_]+))?)?/?\$"
api_repo_re='(^|/)repos/([^/]+/[^/]+)/pulls/'
api_subst_review_re='\$\(\.\.\.\)[^ ]*/reviews(/[^/]+(/[a-z_]+)?)?/?$'
# GraphQL mutations by whole word; a query read from a file or a command substitution stays invisible.
gql_post_re='(^|[^A-Za-z0-9_])(addPullRequestReview|submitPullRequestReview|updatePullRequestReview)([^A-Za-z0-9_]|$)'
gql_dismiss_re='(^|[^A-Za-z0-9_])dismissPullRequestReview([^A-Za-z0-9_]|$)'
# One entry per review post, `gh pr review` first, then `gh api`: the repo it names (or empty), its PR (or empty),
# the GH_REPO= values that reach it (\035-joined) and the folder it runs in (the record's field 7).
gh_triggers="" post_repo=() post_pull=() post_asg=() post_cd=() api_implicit=0 api_overlong=0 api_deep=0 api_param=0 dismissal=0
# A call longer than this is read as a review post whose PR is unknown, where "review" follows it.
api_window=8192
# One `gh api` call with its method as gh sends it. A call that holds a substitution is read fail-closed (decision
# log of #544, "Nachtraege aus den Review-Runden"): the commands of its substitutions (printed before it, at a higher
# level) and the commands after it up to the next `gh api` add their words, and its endpoint is the first word that
# names a review or graphql. Sets api_method, api_endpoint, api_field,
# api_named (a field named event or body) and api_long.
read_api_call() { # record index, field of the word `api` (global f is that record)
  local r="$1" tok skip="" doubt=0 q
  local -a ws=("${f[@]:$2+1}") sv pre=()
  api_method="" api_endpoint="" api_field=0 api_named=0 api_long=0
  [ "${f[3]}" -lt "$api_window" ] || api_long=1
  if [[ ${f[2]} == *s* ]]; then
    doubt=1; sv=("${f[@]}")
    for ((q = r - 1; q >= 0; q--)); do
      rec_fields "${seg_recs[q]}"
      # Only the call's own substitutions: deeper, but read in the same pass (code read again counts 1000 more).
      if [ "${f[9]}" -le "${sv[9]}" ] || [ $((f[9] / 1000)) != $((sv[9] / 1000)) ]; then break; fi
      pre=("${f[@]:10}" ${pre[@]+"${pre[@]}"})
    done
    for ((q = r + 1; q < ${#seg_recs[@]}; q++)); do
      rec_fields "${seg_recs[q]}"
      if [ "${f[1]}" = gh ]; then gh_verb; [ "$verb" != api ] || break; fi
      ws+=("${f[@]:10}")
    done
    f=("${sv[@]}")
    ws=(${pre[@]+"${pre[@]}"} ${ws[@]+"${ws[@]}"})
  fi
  for tok in ${ws[@]+"${ws[@]}"}; do
    tok="${tok//[\"\']/}"
    if [ -n "$skip" ]; then
      case "$skip:$tok" in method:*) api_method="$tok" ;; field:event=*|field:body=*) api_named=1 ;; esac
      skip=""; continue
    fi
    # Short flags bundled behind gh's boolean -i (`-iX POST`, `-if k=v`) count as the last one alone.
    if [[ $tok == -i[A-Za-z]* && $tok =~ ^-i+([A-Za-z].*)$ ]]; then tok="-${BASH_REMATCH[1]}"; fi
    case "$tok" in
      -X|--method) skip=method ;;
      -X=*|--method=*) api_method="${tok#*=}" ;;
      -X?*) api_method="${tok#-X}" ;;
      -f|-F|--field|--raw-field) api_field=1; skip=field ;;
      --input) api_field=1; skip=value ;;
      -fevent=*|-Fevent=*|-fbody=*|-Fbody=*|--field=event=*|--field=body=*|--raw-field=body=*) api_field=1; api_named=1 ;;
      -f?*|-F?*|--field=*|--raw-field=*|--input=*) api_field=1 ;;
      -H|--header|-q|--jq|-t|--template|-p|--preview|--hostname|--cache) skip=value ;;
      # A redirection is no endpoint; a bare operator takes the next word as its target.
      [0-9]\>*|\>*|\<*|[0-9]\<*|\&\>*|\*\>*) [[ $tok == *[\<\>] || $tok == *\>\| ]] && skip=value ;;
      -*) ;;
      *)
        if [ "$doubt" = 1 ]; then
          [[ -z $api_endpoint && ( ${tok%%\?*} =~ $api_review_re || ${tok%%\?*} =~ (^|/)graphql/?$ \
             || ${tok%%\?*} =~ $api_subst_review_re ) ]] && api_endpoint="$tok"
        else
          [ -n "$api_endpoint" ] || api_endpoint="$tok"
        fi ;;
    esac
  done
  api_method="${api_method^^}"
}
repo_of() { # value -> global repo_v: OWNER/REPO without quotes or host
  repo_v="${1//[\"\']/}"
  if [[ $repo_v == */*/* ]]; then repo_v="${repo_v#*/}"; fi
}
# The words of a `gh pr review` record: the repo (-R, --repo, a URL, else the GH_REPO= that reaches `gh`: the one
# in scope, then the command's own prefix; `env -u GH_REPO` clears it) and the PR (the first number or a URL).
# A quoted body is one word whatever it holds ("2 nits fixed" is no PR number).
review_words() { # global f -> target_repo, target_pull
  local k n=${#f[@]} ci=$((9 + f[8])) tk env_repo="${f[5]}" skip=0 u
  target_repo="" target_pull=""
  for ((k = 10; k < n; k++)); do
    tk="${f[k]//[\"\']/}"
    if [ "$skip" = repo ]; then target_repo="$tk"; skip=0; continue; fi
    if [ "$skip" = unset ]; then skip=0; [ "$tk" != GH_REPO ] || env_repo=""; continue; fi
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    if [ "$k" -lt "$ci" ]; then
      case "$tk" in
        GH_REPO=*) env_repo="${tk#GH_REPO=}" ;;
        -u|--unset) skip="unset" ;;
        -uGH_REPO|--unset=GH_REPO) env_repo="" ;;
      esac
      continue
    fi
    if [ "$k" = "$ci" ]; then target_repo="$env_repo"; continue; fi
    case "$tk" in
      -R|--repo) skip=repo ;;
      --repo=*) target_repo="${tk#--repo=}" ;;
      -R=*) target_repo="${tk#-R=}" ;;
      -R?*) target_repo="${tk#-R}" ;;
      -b|--body|-F|--body-file) skip=1 ;;
      https://*/pull/[0-9]*)
        u="${tk#https://}"; u="${u#*/}"
        target_repo="${u%%/pull/*}"; target_pull="${u##*/pull/}"; target_pull="${target_pull%%[!0-9]*}" ;;
      [0-9]*) [[ $tk =~ ^[0-9]+$ && -z $target_pull ]] && target_pull="$tk" ;;
    esac
  done
  return 0
}
# Every review post of the command: each `gh pr review`, and each `gh api` write that creates, submits or edits a
# review; a dismissal is the merger's step and owes `pr` alone; a read and a deletion owe nothing.
find_posts() { # global seg_recs, command_line
  local r gql=0
  local -a api_repo=() api_pull=() api_asg=() api_cd=()
  for r in "${!seg_recs[@]}"; do
    case "${seg_recs[r]}" in
      C$'\037'gh$'\037'*) ;;
      # Code nested too deep to be read, or a ${...} that is not read with the text after it, may hold a post: read
      # as one whose PR is unknown (fail-closed).
      C$'\037'$'\037'[dp]$'\037'*)
        api_pull+=(""); api_repo+=(""); api_asg+=(""); api_cd+=("")
        case "${seg_recs[r]}" in C$'\037'$'\037'd*) api_deep=1 ;; *) api_param=1 ;; esac
        # The other gh commands it may hold are matched in its raw text.
        case "${seg_recs[r]}" in *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*) gh_triggers+=" pr evidence" ;; esac
        case "${seg_recs[r]}" in *"gh issue create"*|*"gh issue edit"*|*"gh issue close"*) gh_triggers+=" carrier" ;; esac
        case "${seg_recs[r]}" in *"gh pr comment"*|*"gh issue comment"*) gh_triggers+=" evidence" ;; esac
        continue ;;
      *) continue ;;
    esac
    rec_fields "${seg_recs[r]}"
    gh_verb
    case "$verb" in
      "pr create"|"pr edit"|"pr ready") gh_triggers+=" pr evidence" ;;
      "issue create"|"issue edit"|"issue close") gh_triggers+=" carrier" ;;
      # A comment is the CLI's counterpart of the MCP add_issue_comment.
      "pr comment"|"issue comment") gh_triggers+=" evidence" ;;
    esac
    if [ "$verb" = review ]; then
      review_words
      post_repo+=("$target_repo"); post_pull+=("$target_pull"); post_asg+=("${f[6]}"); post_cd+=("${f[7]}")
      continue
    fi
    [ "$verb" = api ] || continue
    # Flags, methods and endpoints compare without case, as gh reads them.
    shopt -s nocasematch
    read_api_call "$r" "$verb_at"
    classify_api_call
    shopt -u nocasematch
  done
  # A GraphQL post carries node ids only, no PR number: it takes the path of a post whose PR is unknown.
  if [ "$gql" = 1 ]; then
    if [[ $command_line =~ $gql_post_re ]]; then api_pull+=(""); api_repo+=(""); api_asg+=(""); api_cd+=(""); fi
    if [[ $command_line =~ $gql_dismiss_re ]]; then dismissal=1; fi
  fi
  post_repo+=(${api_repo[@]+"${api_repo[@]}"}); post_pull+=(${api_pull[@]+"${api_pull[@]}"})
  post_asg+=(${api_asg[@]+"${api_asg[@]}"}); post_cd+=(${api_cd[@]+"${api_cd[@]}"})
}
classify_api_call() { # global f, api_* of read_api_call -> api_repo, api_pull, api_asg, api_cd, gql, dismissal
  local path pull own k
  if [ "$api_long" = 1 ] && [ "${f[4]}" = r ]; then
    api_pull+=(""); api_repo+=(""); api_asg+=(""); api_cd+=(""); api_overlong=1; return 0
  fi
  path="${api_endpoint%%\?*}"
  if [[ $path =~ (^|/)graphql/?$ ]]; then gql=1; return 0; fi
  # A substitution that stands for the start of the path (`"$(...)/reviews"`) names a review of an unknown PR.
  if ! [[ $path =~ $api_review_re ]] && [[ $path =~ $api_subst_review_re ]]; then path="pulls/\$(...)/reviews${path##*/reviews}"; fi
  [[ $path =~ $api_review_re ]] || return 0
  case "${api_method:-x}:${BASH_REMATCH[6]}" in
    GET:*|HEAD:*|DELETE:*) return 0 ;;
    x:*) [ "$api_field" = 1 ] || return 0 ;;
  esac
  if [ "${BASH_REMATCH[6]}" = dismissals ]; then dismissal=1; return 0; fi
  [ -n "$api_method" ] || [ -n "${BASH_REMATCH[4]}" ] || [ "$api_named" = 1 ] || api_implicit=1
  pull="${BASH_REMATCH[2]}"; [[ $pull =~ ^[0-9]+$ ]] || pull=""
  api_pull+=("$pull")
  if [[ $path =~ $api_repo_re ]] && [[ ${BASH_REMATCH[2]} != *'{'* ]]; then
    api_repo+=("${BASH_REMATCH[2]}"); api_asg+=(""); api_cd+=("")
  else
    # gh fills `{owner}/{repo}` from GH_REPO - the ones in scope and the call's own prefix, the last one wins -
    # or from the folder it runs in.
    own=""
    for ((k = 10; k < 9 + f[8]; k++)); do
      [[ ${f[k]} == GH_REPO=* ]] || continue
      repo_of "${f[k]#GH_REPO=}"; own="$repo_v"; f[6]+="${f[6]:+$'\035'}$repo_v"
    done
    api_repo+=("${own:-${f[5]}}"); api_asg+=("${f[6]}"); api_cd+=("${f[7]}")
  fi
}
add_trigger() {
  local existing
  for existing in ${triggers[@]+"${triggers[@]}"}; do
    if [ "$existing" = "$1" ]; then return 0; fi
  done
  triggers+=("$1")
}

# The path form of both sides of the project-root comparison stands in lib/pathform.sh (shared with
# record-rule-read.sh); without it, no path is judged and the call passes.
pathform=0
# shellcheck source=SCRIPTDIR/lib/pathform.sh
if . "${BASH_SOURCE[0]%/*}/lib/pathform.sh" 2>/dev/null; then pathform=1; fi

case "$tool" in
  # Any GitHub MCP server, whatever the harness calls it: mcp__github__* in
  # Claude Code with a local server, mcp__claude_ai_GitHub_MCP__* for the
  # claude.ai connector. The server segment is everything before the last "__".
  mcp__*[Gg]it[Hh]ub*__*)
    case "${tool##*__}" in
      create_pull_request|update_pull_request)
        add_trigger pr; add_trigger evidence ;;
      pull_request_review_write|add_comment_to_pending_review|add_reply_to_pull_request_comment)
        add_trigger review; add_trigger evidence
        # Only the write that creates or submits a review is the post; a pending
        # review's comments and its deletion are not.
        if [ "${tool##*__}" = pull_request_review_write ] && [ "$mcp_method" != delete_pending ]; then
          review_post=1
        fi ;;
      issue_write|sub_issue_write)
        add_trigger carrier ;;
      add_issue_comment)
        add_trigger evidence ;;
    esac
    ;;
  Bash|PowerShell)
    # Every gh command counts where a command stands - not inside a quoted commit message, a comment or a heredoc
    # body that only data takes (lib/heredoc.sh; where it cannot be loaded, every body counts). The raw-text hint
    # keeps the segmenter off every call that cannot hold the words; where awk is missing or fails, the pr, issue and
    # comment commands are matched in the raw text and the review gate passes the call.
    review_src="$command_line"
    shopt -s nocasematch
    if [[ $command_line == *gh*pr* || $command_line == *gh*issue* || $command_line == *gh*api* ]]; then
      shopt -u nocasematch
      if [ "$tool" = Bash ] && [[ $command_line == *'<<'* ]]; then
        hd_out=""
        # shellcheck source=SCRIPTDIR/lib/heredoc.sh
        if . "${BASH_SOURCE[0]%/*}/lib/heredoc.sh" 2>/dev/null; then strip_heredocs "$command_line"; review_src="$hd_out"; fi
      fi
      if split_command "$review_src"; then
        find_posts
        if [ "${#post_pull[@]}" -gt 0 ]; then add_trigger review; add_trigger evidence; review_post=1; fi
        if [ "$dismissal" = 1 ]; then add_trigger pr; fi
        for t in $gh_triggers; do add_trigger "$t"; done
      else
        case "$command_line" in
          *"gh pr create"*|*"gh pr edit"*|*"gh pr ready"*) add_trigger pr; add_trigger evidence ;;
        esac
        case "$command_line" in
          *"gh issue create"*|*"gh issue edit"*|*"gh issue close"*) add_trigger carrier ;;
        esac
        # A comment is the CLI's counterpart of the MCP add_issue_comment above.
        case "$command_line" in
          *"gh pr comment"*|*"gh issue comment"*) add_trigger evidence ;;
        esac
      fi
    fi
    shopt -u nocasematch
    ;;
  # A skill of the table (top of this file) raises its trigger (ww3d/playbook#526); any other skill raises nothing.
  Skill)
    skill_name="${skill_name#/}"
    if skill_trigger "${skill_name##*:}"; then add_trigger "$skill_trig"; fi
    ;;
  # Starting a sub-agent or a workflow is the action `agents.md` is read before.
  Agent|Task|Workflow)
    add_trigger agents
    ;;
  Write|Edit|NotebookEdit)
    # Only files inside the project: a scratch file in TMPDIR is not repository
    # work and owes no rule reading. On Windows the comparison ignores case (lib/pathform.sh).
    if [ "$pathform" = 1 ] && path_under "$ROOT" "$path"; then
      relative="$pf_rel"
      [ "$pf_ci" = 0 ] || shopt -s nocasematch
      case "$relative" in
        # ist-stand-* is the old name, read until playbook 26.0.0 (ww3d/playbook#356); audit/ is
        # the old place, read until playbook 26.0.0, the first MAJOR after the move.
        docs/audit/state-*|docs/audit/ist-stand-*|audit/state-*|audit/ist-stand-*) add_trigger audit ;;
      esac
      case "$relative" in
        *.md) add_trigger docs ;;
        *) add_trigger code ;;
      esac
    fi
    shopt -u nocasematch
    ;;
esac

# Only triggers whose rule file this repository carries, and which this reader
# has not already been found to have read, can block. The state is one marker
# per session, reader and trigger: written by record-rule-read.sh on a real
# read, or here when a receipt is found in the transcript - so each trigger
# costs at most one transcript read per session rather than one per tool call
# (a session editing fifty files reads its transcript once for "code", not
# fifty times). An empty session_id has no marker and simply reads every time.
# A compaction ends a marker's life: read-confirm.sh deletes the session's
# markers on source "compact".
# The markers of a typed skill start (UserPromptExpansion, top of this file): each trigger is owed
# until its file is read.
owed_files=() owed_cmds=() owed_trigs=()
if [ -n "$session" ]; then
  for owed_t in $skill_trigs; do
    [ -e "${gate_dir}/${session}-${owed_t}-owed" ] || continue
    owed_files+=("${gate_dir}/${session}-${owed_t}-owed"); owed_trigs+=("$owed_t"); owed_cmd=""
    read -r owed_cmd < "${gate_dir}/${session}-${owed_t}-owed" 2>/dev/null || true
    owed_cmds+=("$owed_cmd")
    add_trigger "$owed_t"
  done
fi
# A consumer's own rule under .agents/rules/local/ is gated where its frontmatter says: `gate: <action>`, one or
# more of the actions mapped above (comma-separated, e.g. `gate: docs, code`), and it blocks that action like the
# playbook rule of the same name does. A local rule without `gate` stands in the index and is read from there;
# the hook cannot know its action. Its marker is `local-<trigger>` (record-rule-read.sh), so a local file never
# stands in for a playbook rule. Read with bash builtins, and only where the directory exists.
rule_triggers=() rule_paths_all=() rule_marks=()
for trigger in ${triggers[@]+"${triggers[@]}"}; do
  rule_triggers+=("$trigger"); rule_paths_all+=(".agents/rules/${trigger}.md"); rule_marks+=("$trigger")
done
# Read like the rule-index generator reads it (Read-RuleFrontmatter and Get-RuleIndex in the playbook): a BOM and the
# blanks around a line do not count, a `#` line is skipped, the key compares without case and the last one wins, one
# matching pair of outer quotes goes, and each comma-separated action is trimmed and lower-cased. A trailing
# ` # comment` stays part of the value, as there: the action is then unknown (the generator throws on it).
trim() { # text -> global trimmed: without the blanks around it
  trimmed="${1#"${1%%[![:space:]]*}"}"; trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
}
local_gate() { # file -> global lgate: the actions of `gate:` in the frontmatter, lower case, comma-joined
  local line n=0 key value="" found=0 a parts=()
  lgate=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ "$n" != 1 ] || line="${line#$'\xef\xbb\xbf'}"
    trim "$line"; line="$trimmed"
    if [ "$n" = 1 ]; then [ "$line" = "---" ] || return 0; continue; fi
    [ "$line" != "---" ] || break
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%:*}"; { [ "$key" != "$line" ] && [ -n "$key" ]; } || continue
    trim "$key"
    [ "${trimmed,,}" = gate ] || continue
    trim "${line#*:}"; value="$trimmed"; found=1
  done < "$1"
  [ "$found" = 1 ] || return 0
  case "$value" in \"*\"|\'*\') value="${value:1:${#value}-2}" ;; esac
  IFS=, read -ra parts <<<"$value"
  for a in ${parts[@]+"${parts[@]}"}; do
    trim "$a"; [ -n "$trimmed" ] || continue
    lgate+="${lgate:+,}${trimmed,,}"
  done
}
# A gate action the hook does not map can never block. The note goes to stderr with exit 0, which Claude Code writes
# only to its debug log: the typo fails where the generator reads the file (`update-rule-index.ps1 -Check`).
gate_actions=",agents,audit,carrier,code,docs,evidence,pr,review,session,"
note_unknown_gate() { # file
  local a parts=()
  IFS=, read -ra parts <<<"$lgate"
  for a in ${parts[@]+"${parts[@]}"}; do
    case "$gate_actions" in *",${a},"*) continue ;; esac
    [ -n "$a" ] || continue
    printf "require-rule-read.sh: %s: gate action '%s' is unknown and never blocks (known: %s)\n" \
      "${1#"${ROOT}"/}" "$a" "${gate_actions:1:${#gate_actions}-2}" >&2
  done
}
if [ "${#triggers[@]}" -gt 0 ] && [ -d "${ROOT}/.agents/rules/local" ]; then
  # Only *.md files are rules; any other file there is ignored on purpose and named, on stderr like the note above
  # (a tool's settings file, such as check-terminology.ps1's terminology.yml, belongs under .agents/config/).
  for lf in "${ROOT}"/.agents/rules/local/*; do
    { [ -f "$lf" ] && [[ $lf != *.md ]]; } || continue
    printf "require-rule-read.sh: %s is no rule file (*.md) and is ignored; a tool's settings file belongs under .agents/config/\n" \
      "${lf#"${ROOT}"/}" >&2
  done
  for lf in "${ROOT}"/.agents/rules/local/*.md; do
    [ -f "$lf" ] || continue
    lname="${lf##*/}"; lname="${lname%.md}"
    [[ $lname =~ ^[A-Za-z0-9_-]+$ ]] || continue
    local_gate "$lf"
    [ -n "$lgate" ] || continue
    note_unknown_gate "$lf"
    for trigger in "${triggers[@]}"; do
      case ",${lgate}," in
        *",${trigger},"*)
          # The denial names the action this call is, not the local file's own trigger name.
          rule_triggers+=("$trigger"); rule_paths_all+=(".agents/rules/local/${lname}.md"); rule_marks+=("local-${lname}")
          break ;;
      esac
    done
  done
fi
pending=() pending_paths=() pending_marks=()
for i in "${!rule_triggers[@]}"; do
  [ -f "${ROOT}/${rule_paths_all[$i]}" ] || continue
  if [ -n "$session" ] && [ -e "${gate_dir}/${session}-read-${who}-${rule_marks[$i]}" ]; then continue; fi
  pending+=("${rule_triggers[$i]}"); pending_paths+=("${rule_paths_all[$i]}"); pending_marks+=("${rule_marks[$i]}")
done

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
# Only what stands after the newest compaction counts. .agents/rules/session.md,
# section "Pasted Texts and Compaction", has every point-of-use receipt
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
# write in progress - is skipped rather than failing the whole read (as in
# require-receipt.sh). The jq step is what keeps any other line -
# the hook's own denial quotes the receipt line - from counting.
receipted=""
read_receipts() { # file paths whose receipt is asked for
  local needles=() out status path
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  for path in "$@"; do needles+=(-e "rule | ${path} |" -e "+ ${path#.agents/rules/} "); done
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
      | def esc: gsub("(?<c>[.*+?^$()\\[\\]{}|\\\\/])"; "\\\(.c)");
        def bare($line): gsub("\\r"; "") | test("(^|\\n)" + $line + "( |\\n|$)");
        $ARGS.positional[] as $rule
      | ("rule | " + $rule + " |") as $n
      | ("\\+ " + ($rule | ltrimstr(".agents/rules/") | esc) + " +[^ \\n]+ +[0-9a-f]{7,40} +read") as $line
      | select($said | any(
            (.type == "text" and (.text | type == "string")
             and ((.text | contains($n)) or (.text | bare($line))))
         or (.type == "tool_use" and (.id | type == "string")
             and (.input.command? | type == "string")
             and (((.input.command | contains($n)) and ($printed[.id] // "" | contains($n)))
                  or ((.input.command | test($line)) and ($printed[.id] // "" | bare($line)))))))
      | $rule
    ' --args "$@" 2>/dev/null
    printf '\n#status %s %s' "${PIPESTATUS[0]}" "${PIPESTATUS[1]}")" || return 1
  out="${out//$'\r'/}" # jq for Windows ends its lines with CRLF
  status="${out##*#status }"
  case "$status" in
    "0 0"|"1 0") ;;
    *) return 1 ;;
  esac
  receipted=$'\n'"${out%#status *}"$'\n'
}

emit_decision() { # deny|allow-with-warning, text
  if [ "$1" = deny ]; then
    # A field without a method makes gh send a POST: the way out for a read, said with every denial of such a call.
    if [ "$api_implicit" = 1 ]; then
      set -- "$1" "$2 Only reading the reviews? A field without --method makes gh api send a POST; add --method GET."
    fi
    if [ "$api_deep" = 1 ]; then
      set -- "$1" "$2 Code nested more than 16 levels deep (bash -c, eval, iex) is not read and counts as a review post."
    fi
    if [ "$api_param" = 1 ]; then
      set -- "$1" "$2 A \${...} holding a quote, backslash, backtick, \$( or \$' is not read: from it on, the command counts as a review post."
    fi
    if [ "$api_overlong" = 1 ]; then
      set -- "$1" "$2 A gh api call longer than ${api_window} bytes is read as a review post: put long field values in a file (-F body=@file)."
    fi
    [ -z "$started_now" ] || rm -f "$started_now" 2>/dev/null || true
    jq -cn --arg reason "$2" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }' || true
  else
    jq -cn --arg m "$2" '{systemMessage: $m}' || true
  fi
}

# Path and blob SHA only: never the content of the rule.
deny_unread() {
  local trigger="$1" rule="$2" sha
  sha="$(git -C "$ROOT" hash-object -- "${ROOT}/${rule}" 2>/dev/null || true)"
  local why=""
  local i
  for i in "${!owed_trigs[@]}"; do
    if [ "${owed_trigs[$i]}" = "$trigger" ]; then
      why=" The session started '${owed_cmds[$i]}' (UserPromptExpansion of ${owed_cmds[$i]}), which owes this read; reading the file lifts the block."
    fi
  done
  if [ "$trigger" = pr ] && [ "$dismissal" = 1 ]; then
    why+=" A review's dismissal is the merger's step; its procedure stands in .claude/skills/controller-mode/SKILL.md, step 5."
  fi
  emit_decision deny "Point-of-use rule gate (AGENTS.md, section \"Session Start: Read Before Anything Else\", step 3): this is the first '${trigger}' action of the session and '${rule}' (blob ${sha:-unknown}) has not been read. Read it in full with the Read tool, then retry this call.${why}"
}

# Rule gate: every pending trigger needs its read marker (checked above) or a receipt in the transcript.
unjudged=" " # the triggers whose receipts could not be read: the fail-open pass leaves their typed-start debt standing
if [ "${#pending[@]}" -gt 0 ]; then
  if read_receipts "${pending_paths[@]}"; then
    for i in "${!pending[@]}"; do
      trigger="${pending[$i]}"; rule="${pending_paths[$i]}"
      case "$receipted" in
        *$'\n'"$rule"$'\n'*)
          if [ -n "$session" ]; then
            mkdir -p "$gate_dir" 2>/dev/null || true
            : > "${gate_dir}/${session}-read-${who}-${pending_marks[$i]}" 2>/dev/null || true
          fi
          continue ;;
      esac
      deny_unread "$trigger" "$rule"
      exit 0
    done
  else
    for trigger in "${pending[@]}"; do unjudged+="$trigger "; done
  fi
fi

# The gate let this call pass with the owed triggers pending: each read stands (or its file is absent), the debt of the
# typed start ends - for the main thread only, a sub-agent's own read does not settle the main thread's.
if [ "$who" = main ]; then
  for i in "${!owed_files[@]}"; do
    case "$unjudged" in *" ${owed_trigs[$i]} "*) ;; *) rm -f "${owed_files[$i]}" 2>/dev/null || true ;; esac
  done
fi

# --- step 4: the review gate --------------------------------------------------
# A review post needs the posting agent to have read the skill's gates.md and checks.md in
# full (read state or receipt line, like a rule file) and `/pr-poll-review` to have run for
# the PR's current head. The skill
# proves it by printing, with a command of its own at its gate step, one line
#
#   review-head | <owner>/<repo>#<number> | <full 40-hex head SHA>
#
# The line counts like a rule receipt: the command ran, was not refused, and its own result
# shows the line; only what stands after the newest compaction. This step reads the lines,
# asks the forge for the PR's head (`gh api`, one call, only here) and compares. A head
# that moved since the skill ran is a review of an older state: refused.
#
# Fail-open where the forge cannot answer (no gh, offline, unknown PR): a line for the named
# PR is then enough, and the call goes through with a systemMessage that says the head was
# not compared. No line at all is refused whatever gh does - that is the case the gate is for.
#
# Cost: a long session's transcript runs to tens of MB, and the hook has 30 s before it fails open. So the scan
# starts at the newest compaction, found once with grep (the quoted key and value stand verbatim only in a real
# line - inside a JSON string every quote is escaped), and only the lines that can matter reach jq: the skill's
# line and a compaction. jq's raw-line read is the slow step (about 5 s for 38 MB on Git Bash). Every step of that
# pipe must succeed (grep may find nothing); a failing one is a read error and fails open, silently, like a missing
# transcript. Whether a release was given before the post is not checked here: it is a rule for the reviewer
# (`.agents/rules/review.md`), not a mechanism (maintainer's decision on ww3d/playbook#359).
review_heads=""
read_review_heads() { # sets review_heads ("owner/repo#n sha" lines); 1 when unreadable
  local out status cut=1 hits
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  hits="$(grep -n -o -F -e '"subtype":"compact_boundary"' -e '"hookName":"SessionStart:compact"' \
    -- "$transcript" 2>/dev/null)" || true
  if [ -n "$hits" ]; then cut="${hits##*$'\n'}"; cut="${cut%%:*}"; fi
  [[ $cut =~ ^[0-9]+$ ]] || cut=1
  out="$(tail -n "+${cut}" -- "$transcript" 2>/dev/null \
    | grep -F -e 'review-head |' -e '"subtype":"compact_boundary"' -e '"hookName":"SessionStart:compact"' \
      2>/dev/null \
    | jq -nRr '
        [ inputs | fromjson? // empty ] as $all
      | ([ $all | to_entries[]
           | select((.value.type == "system" and .value.subtype == "compact_boundary")
                    or (.value.type == "attachment"
                        and .value.attachment.hookName? == "SessionStart:compact"))
           | .key ] | last // -1) as $cut
      | [ $all | to_entries[] | select(.key > $cut) | .value ] as $in
      | [ $in[] | select(.type == "user") | .message.content[]?
          | select(.type == "tool_result" and .is_error != true
                   and (.tool_use_id | type == "string"))
          | { key: .tool_use_id,
              value: (.content | if type == "string" then .
                                 elif type == "array" then map(.text? // "" | strings) | join("\n")
                                 else "" end) } ]
        | from_entries as $printed
      | $in[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and (.id | type == "string")
               and (.input.command? | type == "string")
               and (.input.command | contains("review-head |")))
      | ($printed[.id] // "")
      | scan("review-head \\| ([^ |\\n]+#[0-9]+) \\| ([0-9a-f]{40})")
      | join(" ")
    ' 2>/dev/null
    printf '\n#status %s' "${PIPESTATUS[*]}")" || return 1
  out="${out//$'\r'/}"
  status="${out##*#status }"
  # tail, grep (1: no line matched), jq.
  case "$status" in "0 0 0"|"0 1 0") ;; *) return 1 ;; esac
  review_heads=$'\n'"${out%#status *}"
}

# The PR a review post names: sets target_repo ("owner/repo" or empty), target_pull (number or empty), asg_repos
# (the GH_REPO= values that reach the call: any one that names another repo blocks) and cd_state (the folder it runs
# in, field 7 of its record). From the connector's input, or from the post's entry of find_posts.
parse_review_target() {
  target_repo="" target_pull="" asg_repos=() cd_state=""
  if [ "$review_via" = mcp ]; then
    [ -z "$mcp_owner" ] || [ -z "$mcp_repo" ] || target_repo="${mcp_owner}/${mcp_repo}"
    target_pull="$mcp_pull"
    return 0
  fi
  target_repo="${post_repo[post_i]}"; target_pull="${post_pull[post_i]}"; cd_state="${post_cd[post_i]}"
  local IFS=$'\035'
  set -f
  # shellcheck disable=SC2206 # splitting at \035 is the point here; globbing is off
  asg_repos=(${post_asg[post_i]})
  set +f
}

# The skill's reference files a review post rests on. Each one counts when this reader read it
# in full (the marker record-rule-read.sh leaves) or printed its receipt line like a rule file;
# a receipt found is remembered as the marker. Fail-open where the transcript cannot be read.
require_skill_references() {
  local ref path sha missing=() paths=()
  for ref in gates checks; do
    path=".claude/skills/pr-poll-review/reference/${ref}.md"
    [ -f "${ROOT}/${path}" ] || continue
    if [ -n "$session" ] && [ -e "${gate_dir}/${session}-read-${who}-skill-pr-poll-review-${ref}" ]; then continue; fi
    missing+=("$ref"); paths+=("$path")
  done
  [ "${#missing[@]}" -gt 0 ] || return 0
  read_receipts "${paths[@]}" || return 0
  local i
  for i in "${!missing[@]}"; do
    case "$receipted" in
      *$'\n'"${paths[$i]}"$'\n'*)
        if [ -n "$session" ]; then
          mkdir -p "$gate_dir" 2>/dev/null || true
          : > "${gate_dir}/${session}-read-${who}-skill-pr-poll-review-${missing[$i]}" 2>/dev/null || true
        fi
        continue ;;
    esac
    sha="$(git -C "$ROOT" hash-object -- "${ROOT}/${paths[$i]}" 2>/dev/null || true)"
    emit_decision deny "Review gate: '${paths[$i]}' (blob ${sha:-unknown}) has not been read by the agent posting this review. Read it in full with the Read tool, then retry this call."
    exit 0
  done
}

gate_notes=()
declare -A origin_of=()
# The PR of the review post at hand: sets `post_key` ("owner/repo#number", or empty when the post names no
# PR). A post that names no repo takes the origin remote's.
resolve_review_target() {
  local url d=""
  parse_review_target
  repo_of "$target_repo"; target_repo="$repo_v"
  # No repo named, but a change of folder before the call: gh takes the repo of that folder (`I`: one it cannot read).
  if [ -z "$target_repo" ] && [ "$review_via" != mcp ] && [ -n "$cd_state" ]; then
    case "$cd_state" in
      I) ;;
      D/*|D[A-Za-z]:*) d="${cd_state#D}" ;;
      *) d="${cwd:-$ROOT}"; d="${d%/}/${cd_state#D}" ;;
    esac
    # The origin of a folder is read once per command, however many posts run in it.
    url=""
    if [ -n "$d" ]; then
      if [ -z "${origin_of[$d]+x}" ]; then origin_of[$d]="$(git -C "$d" remote get-url origin 2>/dev/null || true)"; fi
      url="${origin_of[$d]}"
    fi
    if [[ ${url//$'\r'/} =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then target_repo="${BASH_REMATCH[1]%.git}"
    else
      emit_decision deny "Review gate: a change of folder before this review post (${d:-a folder that cannot be read}) leaves its repository unknown. Name it: -R <owner>/<repo> for gh pr review, repos/<owner>/<repo>/... for gh api."
      exit 0
    fi
  fi
  if [ -z "$target_repo" ]; then
    # The origin remote is read once per command, however many posts name no repo.
    if [ -z "${origin_repo+x}" ]; then
      origin_repo=""
      url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
      if [[ ${url//$'\r'/} =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then origin_repo="${BASH_REMATCH[1]%.git}"; fi
    fi
    target_repo="$origin_repo"
  fi
  post_key=""
  if [ -n "$target_repo" ] && [ -n "$target_pull" ]; then post_key="${target_repo}#${target_pull}"; fi
}

# Whether a '/pr-poll-review' line exists for the PR (no network).
has_review_line() { # key
  local line sha found=1
  shopt -s nocasematch
  while IFS=' ' read -r line sha; do
    if [ -n "$line" ] && [[ $line == "$1" ]]; then found=0; break; fi
  done <<<"$review_heads"
  shopt -u nocasematch
  return "$found"
}

# One PR: its '/pr-poll-review' line must name the PR's current head. The head is the PR's own answer over
# REST (why REST: .agents/rules/pr.md "Forge Tooling"), asked once per PR. A deny
# ends the hook; what the gate could not decide is a note, said once at the end. All calls of one command share one
# deadline (`forge_budget` seconds), so several PRs cannot add up past the hook's 30 s; a PR left without time is a
# head the forge could not answer. The clock is `RULE_GATE_NOW_EPOCH` (epoch seconds) when set, otherwise `date +%s`
# - a program a test replaces by a stand-in on PATH - so no test has to wait for time to pass.
forge_budget=15 forge_deadline=0
read_clock() { if [ -n "${RULE_GATE_NOW_EPOCH:-}" ]; then now_s="$RULE_GATE_NOW_EPOCH"; else now_s="$(date +%s 2>/dev/null)" || now_s="${EPOCHSECONDS:-$SECONDS}"; fi; }
check_review_head() { # key
  local key="$1" repo pull view="" line sha current=0 left
  repo="${key%#*}"; pull="${key##*#}"
  read_clock; left=$((forge_deadline - now_s))
  if [ "$left" -gt 0 ] && command -v gh >/dev/null 2>&1; then
    view="$({ cd "$ROOT" 2>/dev/null && timeout "$left" gh api "repos/${repo}/pulls/${pull}" --jq .head.sha 2>/dev/null; } || true)"
    view="${view//$'\r'/}"
  fi
  if ! [[ $view =~ ^[0-9a-f]{40}$ ]]; then
    gate_notes+=("Review gate: the PR head could not be read from the forge (gh missing, offline or unknown PR); the head of ${key} was not compared with '/pr-poll-review'.")
    return 0
  fi
  shopt -s nocasematch
  while IFS=' ' read -r line sha; do
    if [ -n "$line" ] && [[ $line == "$key" ]] && [ "$sha" = "$view" ]; then current=1; break; fi
  done <<<"$review_heads"
  shopt -u nocasematch
  if [ "$current" = 1 ]; then return 0; fi
  emit_decision deny "Review gate: ${key} has a new head (${view}) since '/pr-poll-review' ran for it. Run the skill again for the current head, then post."
  exit 0
}

review_gate() {
  local i n=1 key keys=() k seen v
  [ -f "${ROOT}/.claude/skills/pr-poll-review/SKILL.md" ] || return 0 # no such skill here: nothing to demand
  require_skill_references
  read_review_heads || return 0
  if [ "${review_heads//[$'\n']/}" = "" ]; then
    emit_decision deny "Review gate: no '/pr-poll-review' ran in this session (after the last compaction), so a review cannot be posted. Run the skill; its gate step prints 'review-head | <owner>/<repo>#<number> | <head SHA>', which this gate reads."
    exit 0
  fi
  # Every `gh pr review` and every `gh api` post of the command is a post of its own.
  # First all posts against the skill's lines, which needs no network: a missing line ends the hook at once.
  # Only then the forge is asked, once per PR - a hanging `gh` must not eat the hook's time before a verdict.
  if [ "$review_via" != mcp ]; then n=${#post_pull[@]}; fi
  for ((i = 0; i < n; i++)); do
    post_i=$i
    resolve_review_target
    key="$post_key"
    if [ -z "$key" ]; then
      gate_notes+=("Review gate: the PR of this review post could not be identified (a GraphQL post names node ids only, or the PR is not named and gh is unavailable); a '/pr-poll-review' line exists, the head was not compared.")
      continue
    fi
    # Which earlier `GH_REPO=` reaches `gh` (a prefix of another command does not) is not parsed: any one that
    # names another repo than the one checked blocks.
    for v in ${asg_repos[@]+"${asg_repos[@]}"}; do
      if [ "${v,,}" != "${target_repo,,}" ]; then
        emit_decision deny "Review gate: the command sets GH_REPO=${v} before this review post, which differs from the PR checked (${key}). Post with -R <owner>/<repo> and without a differing GH_REPO."
        exit 0
      fi
    done
    if ! has_review_line "$key"; then
      emit_decision deny "Review gate: '/pr-poll-review' did not run for ${key} in this session. Run the skill for this PR; its gate step prints 'review-head | ${key} | <head SHA>'."
      exit 0
    fi
    seen=0
    for k in ${keys[@]+"${keys[@]}"}; do if [ "${k,,}" = "${key,,}" ]; then seen=1; fi; done
    if [ "$seen" = 0 ]; then keys+=("$key"); fi
  done
  read_clock; forge_deadline=$((now_s + forge_budget))
  for k in ${keys[@]+"${keys[@]}"}; do check_review_head "$k"; done
  if [ "${#gate_notes[@]}" -gt 0 ]; then emit_decision allow "${gate_notes[0]}"; fi
}

if [ "$review_post" = 1 ]; then
  review_via=cli
  case "$tool" in mcp__*) review_via=mcp ;; esac
  review_gate
fi

exit 0
