#!/usr/bin/env bash
#
# SessionStart hook (matcher "compact|clear|startup") and SessionEnd hook (matcher "clear") - EINLESEN after a
# compaction (ww3d/playbook#487): writes what the summary can lose, read from the transcript from the cursor of the
# last save (session-state.sh save) to its end, and points the session at it. Generic, byte-identical across
# consumers. Core: lib/state.sh.
#
# The same at the other cuts (ww3d/playbook#727):
#   startup     with <project>/.agent/succession.json (the starting tool names the predecessor)
#               and no <state>/<session>-succession.done: session-state.sh restore --succession writes the restore
#               file, the lock and the marker cut=switch (lib/successor.sh); without the file the hook ends at once.
#   clear       /clear gives a new session id: the session before it (from <gate>/clear-from, which its SessionEnd
#               leaves) is read from the cursor of its last save, the open boxes of its list come along; lock and
#               marker cut=clear, the lock without a line count.
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
# pb-hook stop warns at the turn end while a box is open (ticks.sh guard).
# The marker <gate>/<session>-cut-pending starts the report after the cut (session-state.sh report); a marker an
# earlier compaction left is reported first, with done false. Then it is written with restore=pending, before the
# transcript is read, and replaced by its full content at the end.
# The hook has a budget of its own, RESTORE_BUDGET_S (default 75 s, under the 90 s of settings.json): the read of the
# transcript, the match against the carriers and the list each get what is left. Where it runs out, the file holds
# what was read, its first box asks for a save and the marker says incomplete=<seconds> (ww3d/playbook#750).
# PLAYBOOK_RESTORE_CLOCK replaces the clock of the budget (a command printing seconds since the start).
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
field hook_event_name; event="$val"; field source; src="${val:-compact}"
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
root="${root%/}"

# /clear gives the session a new id: its SessionEnd notes the session before it for the restore after it.
if [ "$event" = SessionEnd ]; then
  field reason
  [ "$val" != clear ] || printf 'session=%s\ntranscript=%s\nat=%s\n' "$session" "$transcript" "$(date +%s)" \
    > "$gate_dir/clear-from" 2>/dev/null
  exit 0
fi

# A successor's start: the file of the starting tool, once per session; without it nothing happens.
if [ "$src" = startup ]; then
  succ="$root/.agent/succession.json"
  [ -n "$root" ] && [ -f "$succ" ] && [ ! -e "$root/.agent/state/$session-succession.done" ] || exit 0
  out="$(CLAUDE_PROJECT_DIR="$root" timeout 80 bash "$here/session-state.sh" restore --succession "$succ" --session "$session" \
    ${transcript:+--transcript "$transcript"} 2>&1)"; rc=$?
  win "$succ"
  if [ "$rc" -eq 0 ]; then
    sys="Restore after the switch written: ${out%%$'\n'*}"
    ctx="This session succeeds the predecessor $shown names. $out"
  else
    sys="Restore after the switch not written (exit $rc)"
    ctx="This session succeeds the predecessor $shown names, but its restore file was not written (exit $rc): $out Run bash .claude/hooks/session-state.sh restore --succession .agent/succession.json, or name why the file does not apply with bash .claude/hooks/session-state.sh restore --none \"<reason>\"."
  fi
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(esc "$(printf '%s' "$sys" | mask)")" "$(esc "$(printf '%s' "$ctx" | mask)")"
  exit 0
fi
[ "$src" = compact ] || [ "$src" = clear ] || exit 0

# A sub-agent's compaction leaves the main thread as it is.
# shellcheck source=SCRIPTDIR/lib/compaction.sh
if [ "$src" = compact ] && . "$here/lib/compaction.sh" 2>/dev/null; then
  field model; compaction_owner "$session" "$transcript" "$val" "$gate_dir"
  [ "$compaction_by" != helper ] || exit 0
fi
# The history: this session's own transcript and save, after /clear those of the session before it (at most 10 min old).
hist="$session"; hist_tx="$transcript"; prev_note=""
if [ "$src" = clear ]; then
  hist=""; hist_tx=""; prev_note="the session before /clear is not known (no SessionEnd note in $gate_dir/clear-from)"
  # The host names no order of SessionEnd and SessionStart at /clear: the start waits for the note up to
  # PLAYBOOK_CLEAR_WAIT_SECS (it runs in the background); a note of another session or project is left lying.
  wait_end=$(( $(date +%s) + ${PLAYBOOK_CLEAR_WAIT_SECS:-10} ))
  while [ -n "$prev_note" ]; do
    if [ -r "$gate_dir/clear-from" ]; then
      p_s=""; p_t=""; p_at=0
      while IFS= read -r l || [ -n "$l" ]; do
        l="${l%$'\r'}"
        case "$l" in session=*) p_s="${l#session=}" ;; transcript=*) p_t="${l#transcript=}" ;; at=*) p_at="${l#at=}" ;; esac
      done < "$gate_dir/clear-from"
      if [[ $p_s =~ ^[A-Za-z0-9_-]+$ && $p_at =~ ^[0-9]+$ ]] && [ "$p_s" != "$session" ] && [ "${p_t%/*}" = "${transcript%/*}" ] \
        && [ $(( $(date +%s) - p_at )) -le 600 ]; then
        rm -f "$gate_dir/clear-from" 2>/dev/null
        hist="$p_s"; hist_tx="$p_t"; prev_note=""; break
      fi
    fi
    [ "$(date +%s)" -lt "$wait_end" ] || break
    sleep 0.2
  done
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
[ -n "$root" ] && [ -d "$root" ] || exit 0
# The report after each cut (lib/cut.sh): a marker the last compaction left stands as its line with done false,
# before this compaction's restore replaces its file.
cut_marker="${gate_dir}/${session}-cut-pending"
# The budget: whole seconds since the hook began; a fifth of it is kept for the list and the end.
budget="${RESTORE_BUDGET_S:-75}"; [[ $budget =~ ^[0-9]+$ ]] || budget=75
reserve=$((budget / 5))
budget_left() { # -> global left, the seconds of the budget not used yet, 0 or more
  local now=$SECONDS
  if [ -n "${PLAYBOOK_RESTORE_CLOCK:-}" ]; then now="$(bash -c "$PLAYBOOK_RESTORE_CLOCK" 2>/dev/null | tr -d '\r')"; [[ $now =~ ^[0-9]+$ ]] || now=0; fi
  left=$((budget - now)); [ "$left" -gt 0 ] || left=0
}
hold=""
if [ -f "$cut_marker" ]; then
  # A restore before this one that did not run to its end: what lies before its boundary went through none.
  grep -q '^restore=pending' "$cut_marker" 2>/dev/null && hold=1
  budget_left; report_s=$((left < 10 ? left : 10)); [ "$report_s" -gt 0 ] || report_s=1
  # Only a written line drops it; after a failed report this compaction's marker replaces it below, and the old cut
  # counts as hook ran by the restore trace in the transcript, not as a silent cut.
  if CLAUDE_PROJECT_DIR="$root" timeout "$report_s" bash "$here/session-state.sh" report --undone --session "$session" \
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
# The marker comes first (ww3d/playbook#750): should the hook end before its last step, the cut stands as pending.
cut_head="cut=compact"; [ "$src" != clear ] || cut_head="cut=clear"$'\n'"predecessor=$hist"
lines=0; [ -z "$transcript" ] || [ ! -r "$transcript" ] || lines="$(wc -l < "$transcript" | tr -d ' ')"
printf '%s\nat=%s\nfrom=%s\ntranscript=%s\nrestore=pending\nstopHolds=0\n' "$cut_head" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$lines" "$transcript" > "$cut_marker" 2>/dev/null || true
work="$(hook_mktemp -d restore-state 2>/dev/null)" || exit 0
trap 'rm -rf "$work"' EXIT
stamp="$(date -u +%Y-%m-%dT%H%MZ 2>/dev/null)" || stamp=""

# shellcheck source=SCRIPTDIR/lib/state.sh
. "$here/lib/state.sh" 2>/dev/null || exit 0
note="$prev_note"; from=0; hist_state="$state_dir/${hist:-none}.json"
if [ -n "$note" ]; then :
elif ! command -v jq >/dev/null 2>&1; then note="jq is missing, so the transcript was not read"
elif [ -z "$hist_tx" ] || [ ! -r "$hist_tx" ]; then note="the transcript was not found"; fi

cut_short=""; first=0; short_to="$lines"
if [ -z "$note" ]; then
  state_cursor "$hist_state" "$hist_tx" "$hold"; from=$((state_start - 1)); first=$state_start
  checked=""; checked_at=""; carriers=()
  if [ -r "$hist_state" ]; then
    { IFS= read -r checked; IFS= read -r checked_at; } \
      <<< "$(jq -r '(.checked // ""), (.checkedAt // "")' "$hist_state" 2>/dev/null | tr -d '\r')" || true
    c_list="$(jq -r '.carriers[]? | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$"))' \
      "$hist_state" 2>/dev/null | tr -d '\r')"
    [ -z "$c_list" ] || mapfile -t carriers <<< "$c_list"
  fi
  budget_left; avail=$((left - reserve))
  if [ "$avail" -gt 0 ]; then
    # The whole read gets two thirds, the read of the last part the rest.
    state_read_full=$((avail * 2 / 3)); [ "$state_read_full" -gt 0 ] || state_read_full=1
    state_read_tail=$((avail - state_read_full)); [ "$state_read_tail" -gt 0 ] || state_read_tail=1
    state_extract_bounded "$hist_tx" "$work/cand.jsonl" "$(state_unexamined_from "$(state_unexamined_mark "$state_dir" "${hist:-$session}")" "$hist_tx")" || note="$state_read_note"
    [ -z "$state_read_cut" ] || cut_short=1
  else cut_short=1; note="the budget of $budget s ran out before the transcript was read"; fi
  from=$((state_start - 1))
fi
# A part not read stays for the next save: the cursor line names the first line of this restore.
if [ -n "$cut_short" ]; then
  if [ "$state_start" -gt "$first" ] && [ -z "$note" ]; then
    short_to=$((state_start - 1))
    state_start_note="${state_start_note%%: *}: from L$first, the restore ran out of time, the history before L$state_start is not read"
  else state_start_note="${state_start_note%%: *}: from L$first, the restore ran out of time"; fi
fi

# One step in a shell of its own, ended with all it started when its seconds are over (124).
restore_timed() { # seconds, function, arguments...
  local s="$1"; shift
  # shellcheck disable=SC2016 # $1 belongs to the inner bash
  timeout "$s" "$BASH" -c "$(declare -p rs_carriers 2>/dev/null)"'
    . "$1/lib/state.sh"; shift; "$@"' _ "$here" "$@"
}
# The forge and the session tool run side by side: the hook has its own time limit (settings.json).
gather_args=("" 1 "" "")
[ -n "$note" ] || gather_args=("$hist_tx" "$state_start" "$checked" "$checked_at" ${carriers[@]+"${carriers[@]}"})
budget_left; avail=$((left - reserve))
if [ "$avail" -gt 0 ]; then
  export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$root}" STATE_TOOL_TIMEOUT=$((avail > 62 ? 60 : avail > 2 ? avail - 2 : 1))
  restore_timed "$avail" state_restore_gather "$work" "${gather_args[@]}"; [ $? -ne 124 ] || { cut_short=1; short_to="$lines"; }
else cut_short=1; short_to="$lines"; fi

# The start order of the session (.agent/brief.md, where its tool writes one) is read again with the rule files.
brief=""; [ ! -f "$root/.agent/brief.md" ] || brief=".agent/brief.md"
if [ "$src" = clear ]; then rs_rules="_none carried: /clear ends the read record; read each rule file again in full before the next action of its kind_"
elif [ -n "$rules" ]; then
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
[ "$src" != compact ] || [ -n "$instructed" ] || miss+=("save-compact-state.sh did not finish: no instructed=1")
check_line=""
[ ! -r "$state_dir/$session.json" ] || check_line="$(jq -r '.checkLine // ""' "$state_dir/$session.json" 2>/dev/null | tr -d '\r')"
check_line="${check_line%% · stale check:*}"
if [ -n "$check_line" ] && [ -z "$note" ] && [ "$src" = compact ]; then
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
if [ "$src" = clear ]; then
  rs_title="Restore after /clear${stamp:+ - $stamp}"
  rs_lead="Written by restore-compact-state.sh after /clear: the session before it${hist:+ ($hist)} from the cursor of its last save to the end of its transcript, every entry whole. Carry each open box to a carrier or close it with the tool (bash .claude/hooks/ticks.sh close, the line below)."
else
  rs_title="Restore after the compaction${stamp:+ - $stamp}"
  rs_lead='Written by restore-compact-state.sh: from the cursor of the last save to the end of the transcript, every entry whole. It comes before the summary. Carry each open box to a carrier or close it with the tool (bash .claude/hooks/ticks.sh close, the line below).'
fi
rs_note="$note"; rs_txnote=""; rs_posts=""; rs_start_note="${state_start_note:-}"
rs_checked="${checked:-}"; rs_checked_at="${checked_at:-}"; rs_carriers=(${carriers[@]+"${carriers[@]}"})
rs_steps=""
if [ -z "$note" ]; then
  budget_left; avail=$((left - reserve))
  if [ "$avail" -gt 0 ]; then
    rs_steps="$(timeout "$avail" jq -nRr "$state_step_jq" < "$hist_tx" 2>/dev/null)"; [ $? -ne 124 ] || { cut_short=1; short_to="$lines"; }
    rs_steps="${rs_steps//$'\r'/}"
  else cut_short=1; short_to="$lines"; fi
fi
# The box of a restore that ran out of its budget: the first open one, which a save closes.
incomplete_box() { # -> global rs_incomplete, empty where the restore is whole
  rs_incomplete=""
  [ -z "$cut_short" ] || rs_incomplete="- [ ] Restore unvollstaendig (Frist $budget s): L$first-L$short_to nicht abgeglichen — jetzt \`bash .claude/hooks/session-state.sh save\`"
}
incomplete_box
state_restore_render "$work" | mask > "$work/restore.md" 2>/dev/null
# The restore file is a list of the tick tool (ww3d/playbook#688); should that fail, the plain file stands without one.
# A list another call holds is waited for 10 s, within the seconds the list gets (at least 5). After /clear the open
# boxes of the list the session before it left come along.
state_unexamined="$(state_unexamined_new "$work/cand.jsonl" "$(state_unexamined_mark "$state_dir" "${hist:-$session}")" "$hist_tx" 2>/dev/null)"
# The event of this cut: the uuid of the transcript's last line; a restore built anew for the same stand has the same.
rs_event="$(tail -n 1 "$transcript" 2>/dev/null | jq -r '.uuid // empty' 2>/dev/null | tr -d '\r')"
prev_list=""
if [ "$src" = clear ] && [ -n "$hist" ]; then prev_list="$(CLAUDE_PROJECT_DIR="$root" cutlist_latest "$hist")"; [ -z "$prev_list" ] || prev_list="$(ticks_side "$prev_list")"; fi
budget_left; list_s=$((left > 5 ? left : 5))
CLAUDE_PROJECT_DIR="$root" TICKS_LOCK_WAIT=10 STATE_EVENT="$rs_event" state_unexamined="$state_unexamined" \
  restore_timed "$list_s" state_restore_list "$work/restore.md" "$restore" "$session" "$src" \
  "${hist:-$session}" "$work/open.jsonl" "$work" "$prev_list" 2>/dev/null
list_rc=$?
if [ "$list_rc" -ne 0 ]; then
  # A list that ran out of time leaves the plain file, which then carries the box.
  if [ "$list_rc" -eq 124 ] && [ -z "$cut_short" ]; then
    cut_short=1; short_to="$lines"; incomplete_box; state_restore_render "$work" | mask > "$work/restore.md" 2>/dev/null
  fi
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
incomplete=""; [ -z "$cut_short" ] || incomplete="incomplete=$budget"$'\n'
if [ "$src" = clear ]; then
  # No boundary follows /clear: the lock carries no line count, so the net for a sub-agent's compaction does not apply;
  # the transcript keys the valve per turn.
  printf 'cut=clear\ntranscript=%s\nneed=compact.restore %s\n%s' "$transcript" "$shown" "$chat_need" > "${gate_dir}/${session}-compact-lock" 2>/dev/null || true
  c_saved=false; [ -z "${checked:-}" ] || c_saved=true
  c_hist='read'; [ -z "$note" ] || c_hist='unreadable'
  printf 'cut=clear\npredecessor=%s\nat=%s\nfrom=%s\ntranscript=%s\nrestore=%s\nneed=compact.restore\n%s%ssaved=%s\nhistory=%s\nstopHolds=0\n' \
    "$hist" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$lines" "$transcript" "$restore" "${chat:+need=chat$'\n'}" "$incomplete" \
    "$c_saved" "$c_hist" > "$cut_marker" 2>/dev/null || true
  hint="After /clear: read $shown ($n lines, $open open boxes) in full with the Read tool before the next step, in parts with offset and limit where it is too large for one read. It holds, from the cursor of the last save of the session before /clear, what /clear dropped - the maintainer's sentences, messages of other sessions and helper results whole, what no carrier holds, the carriers another hand changed and the step."
else
  printf 'from=%s\nto=%s\ntranscript=%s\nneed=compact.restore %s\n%s' "$from" "$lines" "$transcript" "$shown" "$chat_need" \
    > "${gate_dir}/${session}-compact-lock" 2>/dev/null || true
  # The marker of this compaction: pb-hook stop turns it into the report once the restore is done.
  printf 'cut=compact\nat=%s\nfrom=%s\ntranscript=%s\nrestore=%s\nneed=compact.restore\n%s%sstopHolds=0\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$lines" "$transcript" "$restore" "${chat:+need=chat$'\n'}" "$incomplete" \
    > "$cut_marker" 2>/dev/null || true
  hint="After the compaction: read $shown ($n lines, $open open boxes) in full with the Read tool before the next step, in parts with offset and limit where it is too large for one read. It holds, from the cursor of the last save, what the summary can lose - the maintainer's sentences, messages of other sessions and helper results whole, what no carrier holds, the carriers another hand changed, the step, the todos and the rule files to read again - and it comes before the summary."
fi
parts="$(state_read_parts "$restore")"
[ -z "$parts" ] || hint="$hint It is above 25,000 tokens: read it in these parts, each with the Read tool's offset and limit - $parts."
both="it is"; [ -z "$chat" ] || { hint="$hint Read $chat in full as well: the next answer to the maintainer follows it."; both="both are"; }
hint="$hint Until $both read in full, require-rule-read.sh holds this session's tool calls; while a box stays open, pb-hook stop warns at the turn end. Carry each box to a carrier or close it with bash .claude/hooks/ticks.sh close <id> erledigt <reference> | gelesen <change ids> <sentence why nothing is to do> | ungeprueft <reason> --list $shown; a tick written by hand counts as open."
[ -z "$note" ] || hint="$hint Only partly written: $note."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(esc "Restore written: $shown ($n lines, $open open boxes)")" "$(esc "$(printf '%s' "$hint" | mask)")"
exit 0
