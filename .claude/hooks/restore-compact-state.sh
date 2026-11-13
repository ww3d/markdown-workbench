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
# The marker <gate>/<session>-cut-pending starts the report after the cut (session-state.sh report); a marker an
# earlier compaction left is reported first, with done false.
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
rs_title="Restore after the compaction${stamp:+ - $stamp}"
rs_lead='Written by restore-compact-state.sh: from the cursor of the last save to the end of the transcript, every entry whole. It comes before the summary. Carry each open box to a carrier or tick it "- [x] <box> -> <proof>".'
rs_note="$note"; rs_txnote=""; rs_posts=""; rs_start_note="${state_start_note:-}"
rs_checked="${checked:-}"; rs_checked_at="${checked_at:-}"; rs_carriers=(${carriers[@]+"${carriers[@]}"})
rs_steps=""
[ -n "$note" ] || rs_steps="$(timeout 20 jq -nRr "$state_step_jq" < "$transcript" 2>/dev/null | tr -d '\r')" || rs_steps=""
state_restore_render "$work" | mask > "$work/restore.md" 2>/dev/null
mv -f "$work/restore.md" "$restore" 2>/dev/null || exit 0
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
both="it is"; [ -z "$chat" ] || { hint="$hint Read $chat in full as well: the next answer to the maintainer follows it."; both="both are"; }
hint="$hint Until $both read in full, require-rule-read.sh holds this session's tool calls; while a box stays open, require-receipt.sh holds the turn end. Carry each box to a carrier or tick it '- [x] <box> -> <proof>' in that file."
[ -z "$note" ] || hint="$hint Only partly written: $note."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(esc "Restore written: $shown ($n lines, $open open boxes)")" "$(esc "$(printf '%s' "$hint" | mask)")"
exit 0
