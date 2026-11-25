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
# or closes each box with ticks.sh close (the file is a list of the tick tool, its side list <session>-restore.json);
# require-receipt.sh warns at the turn end while a box is open (ticks.sh guard).
# The marker <gate>/<session>-cut-pending starts the report after the cut (session-state.sh report); a marker an
# earlier compaction left is reported first, with done false.
# A transcript too large to read in time (no save: from line 1) is read from its last 6 MB; the cursor line says so.
# A sub-agent's compaction (lib/compaction.sh) writes neither file, lock nor marker. Without jq or a readable transcript
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
# shellcheck source=SCRIPTDIR/lib/tempdir.sh
. "${BASH_SOURCE[0]%/*}/lib/tempdir.sh" 2>/dev/null && hook_tmpdir || exit 0
gate_dir="$hook_tmp/claude-rule-gate"
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
rules=""; saved=-1; instructed=""; save_file="${gate_dir}/${session}-compact-rules"
if [ -r "$save_file" ]; then
  saved=0
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in instructed=1) instructed=1 ;; lines=*|instructed=*|"") ;; *) rules="$rules$l"$'\n' ;; esac
  done < "$save_file"
  rm -f "$save_file" 2>/dev/null
fi
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
root="${root%/}"
[ -n "$root" ] && [ -d "$root" ] || exit 0
# The report after each cut (lib/cut.sh): a marker the last compaction left stands as its line with done false,
# before this compaction's restore replaces its file.
cut_marker="${gate_dir}/${session}-cut-pending"
if [ -f "$cut_marker" ]; then
  # Only a written line drops it; after a failed report this compaction's marker replaces it below, and the old cut
  # counts as hook ran by the restore trace in the transcript, not as a silent cut.
  if CLAUDE_PROJECT_DIR="$root" timeout 10 bash "$here/session-state.sh" report --undone --session "$session" \
    ${transcript:+--transcript "$transcript"} > /dev/null 2>&1; then
    rm -f "$cut_marker" 2>/dev/null
  fi
fi
# Only files that are there: a read record entry that names no file is no rule.
kept=""
while IFS= read -r l; do [ -z "$l" ] || [ ! -e "$root/$l" ] || kept="$kept$l"$'\n'; done <<< "$rules"
rules="$kept"

state_dir="$root/.agent/state"
mkdir -p "$state_dir" 2>/dev/null || exit 0
restore="$state_dir/$session-restore.md"
work="$(hook_mktemp -d restore-state 2>/dev/null)" || exit 0
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
  ufrom="$(state_unexamined_from "$(state_unexamined_mark "$state_dir" "$session")" "$transcript")"
  # shellcheck disable=SC2016 # $1 to $4 belong to the inner bash
  extract() { timeout "$1" bash -c 'tail -n "+$2" "$1" | jq -R -n -c --argjson start "$2" --argjson from "$4" "$3"' _ "$transcript" \
    "$state_start" "$state_extract_jq" "$ufrom" > "$work/cand.jsonl" 2>/dev/null; }
  if ! extract "${PLAYBOOK_RESTORE_READ_SECS:-30}"; then
    # The whole read outlasted its time (a very large transcript without a save, ww3d/playbook#692): with nothing
    # read, no history would come back, so the last PLAYBOOK_RESTORE_TAIL_BYTES are read, and the cursor line says so.
    total="$(wc -l < "$transcript" | tr -d ' ')"
    win="$(tail -c "${PLAYBOOK_RESTORE_TAIL_BYTES:-6000000}" "$transcript" | wc -l | tr -d ' ')"
    if [[ $total =~ ^[0-9]+$ && $win =~ ^[0-9]+$ ]] && [ $((total - win + 1)) -gt "$state_start" ]; then
      state_start=$((total - win + 1)); from=$((state_start - 1))
      state_start_note="${state_start_note%%: *}: the transcript is too large to read in time, the history before L$state_start is not read"
      extract 20 || note="jq could not read the last part of the transcript within 20 s"
    else note="jq could not read the transcript within ${PLAYBOOK_RESTORE_READ_SECS:-30} s"; fi
  fi
fi

# The forge and the session tool run side by side: the hook has its own time limit (settings.json).
if [ -z "$note" ]; then state_restore_gather "$work" "$transcript" "$state_start" "$checked" "$checked_at" ${carriers[@]+"${carriers[@]}"}
else state_restore_gather "$work" "" 1 "" ""; fi

# The start order of the session (.agent/brief.md, where its tool writes one) is read again with the rule files.
brief=""; [ ! -f "$root/.agent/brief.md" ] || brief=".agent/brief.md"
if [ -n "$rules" ]; then
  rs_rules="The read record ended with the compaction; read each file again in full before the next action of its kind."
elif [ "$saved" -lt 0 ]; then rs_rules="_no save found: the PreCompact hook did not run_"
else rs_rules="_none: no rule file was read before the compaction_"; fi
if [ -n "$brief" ]; then
  rs_rules="$rs_rules"$'\n\n'"The start order ($brief) holds the session's order: read it again in full now."
fi
[ -z "$rules$brief" ] || rs_rules="$rs_rules"$'\n\n'"$(printf '%s%s' "$rules" "${brief:+$brief$'\n'}" | sed '/^$/d; s/^/- /')"
# Did the instruction for the summary arrive (ww3d/playbook#672, decision 5)? The PreCompact hook's last line
# instructed=1, and the check line of the last save verbatim in the summary of this compaction: one behind a main
# boundary after both the save's cursor and the last boundary before the last 20 lines; an older one does not count.
rs_first=""; miss=()
[ -n "$instructed" ] || miss+=("save-compact-state.sh did not finish: no instructed=1")
check_line=""
[ ! -r "$state_dir/$session.json" ] || check_line="$(jq -r '.checkLine // ""' "$state_dir/$session.json" 2>/dev/null | tr -d '\r')"
check_line="${check_line%% · stale check:*}"
if [ -n "$check_line" ] && [ -z "$note" ]; then
  low=$state_cursor_at; [ "$state_cb" -le "$low" ] || low=$state_cb
  sum_n="$(grep -n -F -e '"isCompactSummary":true' -e '"subtype":"compact_boundary"' "$transcript" 2>/dev/null \
    | grep -v -F '"isSidechain":true' | awk -F: -v low="$low" '$1 <= low { next }
      /"isCompactSummary":true/ { if (b) s = $1; next } /"subtype":"compact_boundary"/ { b = 1 } END { print s }')"
  if [ -z "$sum_n" ]; then
    rs_first="compaction check: not checkable (no summary in the transcript when this hook ran)"
  elif ! sed -n "${sum_n}p" "$transcript" | jq -r '.message.content | if type == "array" then map(.text? // "") | join("\n") else . end' \
      2>/dev/null | grep -q -F -- "$check_line"; then
    miss+=("the check line of the last save is not in the summary")
  fi
fi
if [ ${#miss[@]} -gt 0 ]; then
  box="- [ ] compaction instruction did not arrive ($(IFS=';'; printf '%s' "${miss[*]}" | sed 's/;/; /g')) — run bash .claude/hooks/session-state.sh save again"
  rs_first="$box${rs_first:+$'\n\n'$rs_first}"
fi
rs_title="Restore after the compaction${stamp:+ - $stamp}"
rs_lead='Written by restore-compact-state.sh: from the cursor of the last save to the end of the transcript, every entry whole. It comes before the summary. Carry each open box to a carrier or close it with the tool (bash .claude/hooks/ticks.sh close, the line below).'
rs_note="$note"; rs_txnote=""; rs_posts=""; rs_start_note="${state_start_note:-}"
rs_checked="${checked:-}"; rs_checked_at="${checked_at:-}"; rs_carriers=(${carriers[@]+"${carriers[@]}"})
rs_steps=""
[ -n "$note" ] || rs_steps="$(timeout 20 jq -nRr "$state_step_jq" < "$transcript" 2>/dev/null | tr -d '\r')" || rs_steps=""
state_restore_render "$work" | mask > "$work/restore.md" 2>/dev/null
# The restore file is a list of the tick tool (ww3d/playbook#688); should that fail, the plain file stands without one.
# A list another call holds is waited for 10 s, well inside the hook's 90 s.
state_unexamined="$(state_unexamined_new "$work/cand.jsonl" "$(state_unexamined_mark "$state_dir" "$session")" "$transcript" 2>/dev/null)"
# The event of this cut: the uuid of the transcript's last line; a restore built anew for the same stand has the same.
rs_event="$(tail -n 1 "$transcript" 2>/dev/null | jq -r '.uuid // empty' 2>/dev/null | tr -d '\r')"
if ! CLAUDE_PROJECT_DIR="$root" TICKS_LOCK_WAIT=10 STATE_EVENT="$rs_event" state_restore_list "$work/restore.md" "$restore" "$session" compact "$session" \
  "$work/open.jsonl" "$work" "" 2>/dev/null; then
  mv -f "$work/restore.md" "$restore" 2>/dev/null || exit 0
  rm -f "$(ticks_side "$restore")"; CLAUDE_PROJECT_DIR="$root" ticks_register "$restore" 2>/dev/null
fi
n="$(wc -l < "$restore" 2>/dev/null | tr -d ' ')" || n="?"
open="$(state_restore_open "$restore")"
# chat.md belongs to the lock too (ww3d/playbook#621): the next answer to the maintainer follows its rules.
chat_need=""; chat=""
if [ -f "$root/.agents/rules/chat.md" ]; then win "$root/.agents/rules/chat.md"; chat="$shown"; chat_need="need=chat $chat"$'\n'; fi
win "$restore"
lines=0; [ -z "$transcript" ] || [ ! -r "$transcript" ] || lines="$(wc -l < "$transcript" | tr -d ' ')"
printf 'from=%s\nto=%s\ntranscript=%s\nneed=compact.restore %s\n%s' "$from" "$lines" "$transcript" "$shown" "$chat_need" \
  > "${gate_dir}/${session}-compact-lock" 2>/dev/null || true
# The marker of this compaction: require-receipt.sh turns it into the report once the restore is done.
printf 'cut=compact\nat=%s\nfrom=%s\ntranscript=%s\nrestore=%s\nneed=compact.restore\n%sstopHolds=0\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$lines" "$transcript" "$restore" "${chat:+need=chat$'\n'}" \
  > "$cut_marker" 2>/dev/null || true

hint="After the compaction: read $shown ($n lines, $open open boxes) in full with the Read tool before the next step, in parts with offset and limit where it is too large for one read. It holds, from the cursor of the last save, what the summary can lose - the maintainer's sentences, messages of other sessions and helper results whole, what no carrier holds, the carriers another hand changed, the step, the todos and the rule files to read again - and it comes before the summary."
parts="$(state_read_parts "$restore")"
[ -z "$parts" ] || hint="$hint It is above 25,000 tokens: read it in these parts, each with the Read tool's offset and limit - $parts."
both="it is"; [ -z "$chat" ] || { hint="$hint Read $chat in full as well: the next answer to the maintainer follows it."; both="both are"; }
hint="$hint Until $both read in full, require-rule-read.sh holds this session's tool calls; while a box stays open, require-receipt.sh warns at the turn end. Carry each box to a carrier or close it with bash .claude/hooks/ticks.sh close <id> erledigt <reference> | gelesen <change ids> <sentence why nothing is to do> | ungeprueft <reason> --list $shown; a tick written by hand counts as open."
[ -z "$note" ] || hint="$hint Only partly written: $note."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(esc "Restore written: $shown ($n lines, $open open boxes)")" "$(esc "$(printf '%s' "$hint" | mask)")"
exit 0
