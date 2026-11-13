#!/usr/bin/env bash
#
# SessionStart hook (matcher "compact") - EINLESEN after a compaction (ww3d/playbook#487): writes what the summary
# can lose, read from the transcript from the cursor of the last save (session-state.sh save) to its end, and
# points the session at it. Generic, byte-identical across consumers. Core: lib/state.sh.
#
#   <project>/.agent/state/<session>-restore.md, rebuilt at every compaction, eight sections:
#     Step and todos          the work step: the last own text before the compaction; the last skill call or slash
#                             command; the last todo state
#     Rule files to reread    the files read before the compaction (save-compact-state.sh saved the list)
#     History without a carrier  a box per sentence, message, helper result or own promise since the cursor that
#                             no carrier of the last save holds ("unchecked" where the last check line says the
#                             transcript was not readable)
#     Carriers changed since checked  a box per carrier another hand changed after the last save; changes the
#                             session's own write calls made do not count; then PLAYBOOK_CARRIER_TEXT_CMD changed
#     The maintainer's sentences, Messages of other sessions, Helper results - since the cursor, each entry whole
#     Tool additions          the output of PLAYBOOK_CARRIER_TEXT_CMD extra, verbatim
#
# The session reads the file and .agents/rules/chat.md in full - require-rule-read.sh holds its tool calls until
# then (the lock <gate>/<session>-compact-lock, `need=compact.restore <path>`, `need=chat <path>`) - and carries
# or ticks each box "- [x] <box> -> <proof>"; require-receipt.sh holds the turn end while a box is open.
# A sub-agent's compaction (lib/compaction.sh) writes neither file nor lock. Without jq or a readable transcript
# the file names what is missing. Known token shapes are masked. Whatever goes wrong, the hook exits 0.
#
# Stdin:  the SessionStart event JSON. Stdout: the hook's JSON output.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "$here/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
read_hook_payload
input="$hook_input"

field() { # key -> global val, the first string value of "key" in the raw payload
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}
# The same expression as in save-compact-state.sh.
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
esc() { # JSON string body: other control characters dropped, then backslash, quote, \n \r \t
  local s
  s="$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
win() { # path -> global shown, in the form the Read tool takes
  shown="$1"
  if command -v cygpath >/dev/null 2>&1; then shown="$(cygpath -w "$1" 2>/dev/null)" || shown="$1"; fi
}

field session_id; session="$val"
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
field transcript_path; transcript="${val//\\\\//}"
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
{ [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null || exit 0

# A sub-agent's compaction leaves the main thread as it is.
# shellcheck source=SCRIPTDIR/lib/compaction.sh
if . "$here/lib/compaction.sh" 2>/dev/null; then
  field model; compaction_owner "$session" "$transcript" "$val" "$gate_dir"
  [ "$compaction_by" != helper ] || exit 0
fi

# The lock of an earlier compaction goes first, with its denial count and the gapless-read state of its file:
# should the hook end before it writes this one's lock, the session stays free (fail-open).
rm -f "${gate_dir}/${session}-compact-lock" "${gate_dir}/${session}-compact-lock-denies" \
  "${gate_dir}/${session}-read-"*"-compact.restore.upto" 2>/dev/null

# The rule files read before the compaction (save-compact-state.sh); used once.
rules=""; saved=-1; save_file="${gate_dir}/${session}-compact-rules"
if [ -r "$save_file" ]; then
  saved=0
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in lines=*|"") ;; *) rules="$rules$l"$'\n' ;; esac
  done < "$save_file"
  rm -f "$save_file" 2>/dev/null
fi
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
root="${root%/}"
[ -n "$root" ] && [ -d "$root" ] || exit 0
# Only files that are there: a read record entry that names no file is no rule.
kept=""
while IFS= read -r l; do [ -z "$l" ] || [ ! -e "$root/$l" ] || kept="$kept$l"$'\n'; done <<< "$rules"
rules="$kept"

state_dir="$root/.agent/state"
mkdir -p "$state_dir" 2>/dev/null || exit 0
restore="$state_dir/$session-restore.md"
work="$(mktemp -d "${TMPDIR:-/tmp}/restore-state.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "$work"' EXIT
stamp="$(date -u +%Y-%m-%dT%H%MZ 2>/dev/null)" || stamp=""

# shellcheck source=SCRIPTDIR/lib/state.sh
. "$here/lib/state.sh" 2>/dev/null || exit 0
note=""; from=0
if ! command -v jq >/dev/null 2>&1; then note="jq is missing, so the transcript was not read"
elif [ -z "$transcript" ] || [ ! -r "$transcript" ]; then note="the transcript was not found"; fi

if [ -z "$note" ]; then
  state_cursor "$state_dir/$session.json" "$transcript"; from=$((state_start - 1))
  checked=""; checked_at=""; carriers=()
  if [ -r "$state_dir/$session.json" ]; then
    { IFS= read -r checked; IFS= read -r checked_at; } \
      <<< "$(jq -r '(.checked // ""), (.checkedAt // "")' "$state_dir/$session.json" 2>/dev/null | tr -d '\r')" || true
    c_list="$(jq -r '.carriers[]? | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$"))' \
      "$state_dir/$session.json" 2>/dev/null | tr -d '\r')"
    [ -z "$c_list" ] || mapfile -t carriers <<< "$c_list"
  fi
  # shellcheck disable=SC2016 # $1 to $3 belong to the inner bash
  timeout 30 bash -c 'tail -n "+$2" "$1" | jq -R -n -c --argjson start "$2" "$3"' _ "$transcript" "$state_start" "$state_extract_jq" \
    > "$work/cand.jsonl" 2>/dev/null || note="jq could not read the transcript within 30 s"
fi

# The forge and the session tool run side by side: the hook has its own time limit (settings.json).
export STATE_GH_TIMEOUT=10
if [ -z "$note" ]; then
  if [ ${#carriers[@]} -gt 0 ] && command -v gh >/dev/null 2>&1; then
    ( state_haystack "$work" "${carriers[@]}" > /dev/null 2> "$work/hay.log"; printf '%s' "$state_hay_note" > "$work/hay.note"
      [ -s "$work/hay.log" ] || state_match "$work" "$work/cand.jsonl" > "$work/open.jsonl" 2>/dev/null ) &
    if [[ $checked_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
      mkdir -p "$work/ch" && state_changed "$work/ch" "$checked_at" "$transcript" "$state_start" "${carriers[@]}" > "$work/changed.txt" 2>&1 &
    fi
  fi
  if [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ] && [ -n "$checked" ]; then
    ( rc=0; timeout 60 bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ changed "$checked" > "$work/channel-changed.txt" 2>&1 || rc=$?
      [ "$rc" -eq 0 ] || printf '\nfurther channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD changed %s)\n' \
        "$([ "$rc" -eq 124 ] && echo "timed out after 60 s" || echo "failed, exit $rc")" >> "$work/channel-changed.txt" ) &
  fi
fi
if [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then
  ( rc=0; timeout 60 bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ extra > "$work/extra.txt" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || printf '\ntool additions: not checked (PLAYBOOK_CARRIER_TEXT_CMD extra %s)\n' \
      "$([ "$rc" -eq 124 ] && echo "timed out after 60 s" || echo "failed, exit $rc")" >> "$work/extra.txt" ) &
fi
wait

# Step and todos, over the whole transcript (the todo state can stand before the cursor).
read -r -d '' step_jq <<'JQ'
def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n")
  elif . == null then "" else tostring end;
def oneline($n): gsub("\\s+"; " ") | if length > $n then .[0:$n - 3] + "..." else . end;
def human: .type == "user" and (.isMeta | not) and (.isCompactSummary | not) and (.isSidechain | not)
  and ((.message.content | type) == "string" or ([.message.content[]? | select(.type? == "tool_result")] | length) == 0);
[inputs | (fromjson? // null) | objects | select(.isSidechain != true)] as $e
| ($e | length) as $len
| ((first(range($len - 1; -1; -1) as $k | $e[$k]
     | ([.message.content[]? | objects | select(.type == "tool_use" and .name == "Skill")
         | "skill " + (.input.skill // "?" | tostring) + (if (.input.args // "") != "" then " " + (.input.args | tostring) else "" end)]
        + [select(human) | .message.content | flat | select(test("<command-name>")) as $t
           | ($t | capture("<command-name>(?<n>[^<]*)</command-name>").n | if startswith("/") then . else "/" + . end) as $n
           | ([$t | match("<command-args>([\\s\\S]*?)</command-args>") | .captures[0].string] | first // "") as $a
           # A harness command (model, compact, ...) is no work step.
           | select($n | test("^/(compact|clear|model|config|context|cost|status|help|resume|rewind|permissions|hooks|memory|login|logout|exit)$") | not)
           | $n + (if $a == "" then "" else " " + $a end)])
     | last // empty) // "none found") | oneline(500)) as $step
| ([$e[] | select(.type == "assistant") | .message.content[]? | objects
    | select(.type == "tool_use" and (.name == "TodoWrite" or .name == "TaskCreate" or .name == "TaskUpdate"))] as $tu
   | if ($tu | length) == 0 then []
     elif ($tu | last | .name) == "TodoWrite" then [($tu | last | .input.todos // [])[] | "- [\(.status // "?")] \(.content // .subject // "")"]
     else (reduce ($e[] | select(.type == "user") | .message.content[]? | objects | select(.type == "tool_result"))
             as $r ({}; .[$r.tool_use_id // ""] = ($r.content | flat))) as $res
       | (reduce $tu[] as $u ({};
            if $u.name == "TaskCreate" then
              ([($res[$u.id // ""] // "") | match("Task #([0-9]+)") | .captures[0].string] | first) as $n
              | if $n == null then . else .[$n] = {s: ($u.input.subject // ""), st: "pending"} end
            elif $u.name == "TaskUpdate" and ($u.input.taskId // null) != null then
              ($u.input.taskId | tostring) as $n
              | .[$n] = ((.[$n] // {s: "", st: "pending"}) | .st = ($u.input.status // .st) | .s = ($u.input.subject // .s))
            else . end))
          | to_entries | map(select(.value.st != "deleted")) | sort_by(.key | tonumber? // 0)
          | map("- [\(.value.st)] #\(.key) \(.value.s)") end) as $todos
# The main thread's own boundary is written only after this hook (3 s, measured 2026-11-12): the newest own text
# of the transcript is the step, a boundary in it belongs to an earlier compaction.
| (first(range($len - 1; -1; -1) as $k | $e[$k] | select(.type == "assistant")
     | [.message.content[]? | objects | select(.type == "text") | .text] | join("\n")
     # A read-receipt line ("+ <file> <version> <sha> read") is no work step.
     | gsub("(?m)^\\+ \\S+ .* read( \\(rule\\))?\\s*$"; "") | select(test("[^\\s]")))
   // "none found" | oneline(500)) as $work
| "Step: " + $work + "\n\nSkill: " + $step
  + "\n\nTodos:\n\n" + (if ($todos | length) > 0 then $todos | join("\n") else "_none_" end)
JQ

section() { printf '## %s\n\n%s\n\n' "$1" "${2:-_none_}"; }
{
  printf '# Restore after the compaction%s\n\n' "${stamp:+ - $stamp}"
  printf 'Written by restore-compact-state.sh: from the cursor of the last save to the end of the transcript, every entry whole. It comes before the summary. Carry each open box to a carrier or tick it "- [x] <box> -> <proof>".\n\n'
  [ -z "$note" ] || printf 'Only partly written: %s.\n\n' "$note"
  steps=""
  [ -n "$note" ] || steps="$(timeout 20 jq -nRr "$step_jq" < "$transcript" 2>/dev/null | tr -d '\r')" || steps=""
  section "Step and todos" "${steps:-_not read_}"
  if [ -n "$rules" ]; then
    section "Rule files to reread" "The read record ended with the compaction; read each file again in full before the next action of its kind.

$(printf '%s' "$rules" | sed '/^$/d; s/^/- /')"
  elif [ "$saved" -lt 0 ]; then section "Rule files to reread" "_no save found: the PreCompact hook did not run_"
  else section "Rule files to reread" "_none: no rule file was read before the compaction_"; fi

  if [ -n "$note" ]; then
    for h in "History without a carrier" "Carriers changed since checked" "The maintainer's sentences since the cursor" \
             "Messages of other sessions since the cursor" "Helper results since the cursor"; do section "$h" "_not read: ${note}_"; done
  else
    hist="Since the cursor: $state_start_note."
    # A check line "transcript: not readable" newer than the last save leaves the stretch since it unchecked.
    unread="$(cat "$work"/*.md 2>/dev/null | grep -o 'checked: [0-9TZ-]* · transcript: not readable[^)]*)' | sort | tail -n 1)" || unread=""
    if [ -n "$unread" ] && [[ ${unread#checked: } > ${checked:-0} ]]; then
      hist="$hist"$'\n\n'"Unchecked since ${unread%% ·*}: the last check line says the transcript was not readable (${unread#*not readable })."
    fi
    if [ ${#carriers[@]} -eq 0 ]; then
      hist="$hist No carrier named at the last save (or no save): every candidate since the cursor stands as a box."
      jq -c 'select(has("art"))' < "$work/cand.jsonl" > "$work/open.jsonl"
    elif [ -s "$work/hay.log" ] || [ ! -e "$work/open.jsonl" ]; then
      hist="$hist Carriers not read ($(head -c 300 "$work/hay.log" 2>/dev/null | tr '\r\n' '  ')): every candidate since the cursor stands as a box."
      jq -c 'select(has("art"))' < "$work/cand.jsonl" > "$work/open.jsonl"
    fi
    [ ! -s "$work/hay.note" ] || hist="$hist"$'\n\n'"$(cat "$work/hay.note")"
    boxes="$(jq -r '"- [ ] L\(.l) \(.ts) \(.art): \(.text | gsub("[\t\r\n]"; " ") | if length > 400 then .[0:397] + "..." else . end)"' \
      < "$work/open.jsonl" 2>/dev/null | tr -d '\r')"
    section "History without a carrier" "$hist${boxes:+$'\n\n'$boxes}"

    if [ -z "$checked_at" ]; then changed="Not checked: no save with exit 0 in this session (no checkedAt)."
    elif [ ${#carriers[@]} -eq 0 ]; then changed="Not checked: the last save named no carrier."
    else changed="Since $checked (checkedAt $checked_at), changes of the session's own write calls left out."
      if [ -e "$work/changed.txt" ]; then c_out="$(tr -d '\r' < "$work/changed.txt" 2>/dev/null)"
      elif [ -n "$note" ]; then c_out="carriers changed: not checked ($note)"
      elif ! command -v gh >/dev/null 2>&1; then c_out="carriers changed: not checked (gh not found)"
      else c_out="carriers changed: not checked (checkedAt '$checked_at' is no ISO time)"; fi
      changed="$changed"$'\n\n'"${c_out:-_no carrier changed by another hand_}"
    fi
    if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then changed="$changed"$'\n\n'"further channel: not checked"
    elif [ -n "$checked" ]; then changed="$changed"$'\n\n'"Further channel (PLAYBOOK_CARRIER_TEXT_CMD changed $checked):"$'\n\n'"$(tr -d '\r' < "$work/channel-changed.txt")"; fi
    section "Carriers changed since checked" "$changed"

    # shellcheck disable=SC2016 # jq text, not shell
    entry='"### L\(.l) \(.ts)" + (if .from then " " + .from else "" end) + "\n\n" + (.full // .text)'
    section "The maintainer's sentences since the cursor" \
      "$(jq -r "select(.art == \"human\" or .art == \"open-question\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
    section "Messages of other sessions since the cursor" \
      "$(jq -r "select(.art == \"message\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
    section "Helper results since the cursor" \
      "$(jq -r "select(.art == \"helper\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
  fi
  if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then section "Tool additions" "tool additions: not checked"
  else section "Tool additions" "$(tr -d '\r' < "$work/extra.txt")"; fi
} | mask > "$work/restore.md" 2>/dev/null
mv -f "$work/restore.md" "$restore" 2>/dev/null || exit 0
n="$(wc -l < "$restore" 2>/dev/null | tr -d ' ')" || n="?"
# Boxes stand only in these two sections; a quoted "- [ ]" line elsewhere is text.
open="$(awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## History without a carrier" || $0 == "## Carriers changed since checked"); next }
  s && /^- \[ \]/ { n++ } END { print n + 0 }' "$restore" 2>/dev/null)" || open=0
# chat.md belongs to the lock too (ww3d/playbook#621): the next answer to the maintainer follows its rules.
chat_need=""; chat=""
if [ -f "$root/.agents/rules/chat.md" ]; then win "$root/.agents/rules/chat.md"; chat="$shown"; chat_need="need=chat $chat"$'\n'; fi
win "$restore"
lines=0; [ -z "$transcript" ] || [ ! -r "$transcript" ] || lines="$(wc -l < "$transcript" | tr -d ' ')"
printf 'from=%s\nto=%s\ntranscript=%s\nneed=compact.restore %s\n%s' "$from" "$lines" "$transcript" "$shown" "$chat_need" \
  > "${gate_dir}/${session}-compact-lock" 2>/dev/null || true

hint="After the compaction: read $shown ($n lines, $open open boxes) in full with the Read tool before the next step, in parts with offset and limit where it is too large for one read. It holds, from the cursor of the last save, what the summary can lose - the maintainer's sentences, messages of other sessions and helper results whole, what no carrier holds, the carriers another hand changed, the step, the todos and the rule files to read again - and it comes before the summary."
both="it is"; [ -z "$chat" ] || { hint="$hint Read $chat in full as well: the next answer to the maintainer follows it."; both="both are"; }
hint="$hint Until $both read in full, require-rule-read.sh holds this session's tool calls; while a box stays open, require-receipt.sh holds the turn end. Carry each box to a carrier or tick it '- [x] <box> -> <proof>' in that file."
[ -z "$note" ] || hint="$hint Only partly written: $note."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(esc "Restore written: $shown ($n lines, $open open boxes)")" "$(esc "$(printf '%s' "$hint" | mask)")"
exit 0
