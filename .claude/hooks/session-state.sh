#!/usr/bin/env bash
#
# SICHERN before a compaction or a switch (ww3d/playbook#487): what the session was told, asked, decided and
# promised since its cursor, held against the texts of its carriers. Generic, byte-identical across consumers;
# a command the session runs, no hook. Core: lib/state.sh; the report after each cut: lib/cut.sh.
#
# Usage:  bash session-state.sh save [--carrier <owner/repo#N>]... [--transcript <path>] [--session <id>]
#         bash session-state.sh report [--undone] [--transcript <path>] [--session <id>]
#         bash session-state.sh report --replay <transcript>...
#         bash session-state.sh restore --from <owner/repo#N | its issue URL> [--predecessor <name>]
#              [--carrier <owner/repo#N>]... [--session <id>]
#         bash session-state.sh restore --none "<reason>" [--session <id>]
#         bash session-state.sh restore --succession <.agent/succession.json> [--carrier <owner/repo#N>]...
#              [--session <id>]
#   --carrier     a carrier of the session (tracking issue, PR); repeatable. Its body, the bodies it links
#                 (one level) and the text of PLAYBOOK_CARRIER_TEXT_CMD form the haystack.
#   --transcript  default: the marker's transcript, else <CLAUDE_CODE_SESSION_ID>.jsonl under ~/.claude/projects/*/
#   --session     default: CLAUDE_CODE_SESSION_ID
#   --undone      report the standing marker as a line with done false (restore-compact-state.sh, before a new one)
#   --replay      one line per main-thread compaction of each transcript on stdout, from the transcript alone;
#                 writes nothing (what needs the restore file stands in notChecked)
#   --from        restore: the carrier whose "## Hand-back" (else body) holds the predecessor's check line
#   --predecessor restore: the predecessor's name for PLAYBOOK_CARRIER_TEXT_CMD posts
#                 (default: the id of its transcript)
#   --none        restore: no predecessor (a first start) and why; lifts the lock of /controller-mode like --from
#                 and the lock of a switch
#   --succession  restore: the file the starting tool left (restore-compact-state.sh at the start runs it)
#
# Files, under <project>/.agent/state/ (git-ignored):
#   <session>-save.md  the work list, a list of ticks.sh with its side list <session>-save.json: "- [ ] K<n> L<line>
#                      <UTC> <art>: <text>" per candidate no carrier holds and per own report of an action (pushed,
#                      sent, commented) without its tool call in its turn (claim); the session carries each and runs
#                      save again, or closes it with ticks.sh close (a reference that holds the box's core)
#   <session>-pairs.md "L<line> <art>: <candidate> => <owner/repo#N>: <carrier line>" per candidate a carrier
#                      holds, rebuilt each run; a helper checks them where the kind compacts (pair-check.md)
#   <session>.json     cursor (transcript, line, uuid), checked (UTC), checkedAt, checkLine and the carriers,
#                      written on exit 0 of save; lastCutUuid and lastCutLine, the newest boundary report has seen;
#                      revivedFrom, the id a revived session took its state from
#   ticks/<session>/unexamined.json  transcript and line, the end of the reading whose unexamined sentences a
#                      report counted; written by every save, also one that ends with open boxes
#   cuts.jsonl         one JSON line per cut (v 1), sent true once PLAYBOOK_CARRIER_TEXT_CMD report took it; a line
#                      with sent false goes again at the next report
#
# report: the marker <gate>/<session>-cut-pending of restore-compact-state.sh as a line (done true, freeAt now),
# then each main-thread boundary since the last reported one without a line (hook none), then the channel. save
# does the same as its first step, a standing marker as done false. Nothing of it ever blocks.
# Exit: save - 0 no box open (cursor and check line written, the check line printed), 3 boxes open, 2 a read
# error (transcript, carrier, jq or gh missing) or a usage error; the output names what was missing.
# report - 0 done (a missing transcript is a line with transcript-unreadable, a missing jq a bare line with notChecked
# jq), 2 a failed read or a usage error;
# with --replay the lines on stdout, 2 where no transcript was readable.
# restore --from (lib/successor.sh): the successor's <session>-restore.md from the predecessor's transcript after the
# cursor of its check line, the carriers changed since that line and the predecessor's open posts, then the lock and a
# marker cut=switch as after a compaction. Exit 0 written (an unreadable transcript is named in the file), 2 a read
# error (the carrier, jq or gh missing) or a usage error.
# save and restore check the state of every reference in the pairs and open boxes (lib/stale.sh): a contradiction is
# a box "stale: ...", an unresolved reference the note "stale check: <n> not checked (<why>)".
# A start of /controller-mode leaves <gate>/<session>-restore-owed (require-rule-read.sh): every call but reading and
# this restore is refused until restore --from has written the restore file or restore --none named its reason.
# restore --none: removes that marker and appends a line cut "no-predecessor" with the reason to cuts.jsonl, sent with
# the next report; while the lock of a switch stands (cut=switch), it lifts that lock instead and reports the switch
# with the reason. Exit 0 done, 1 an empty reason, 2 a usage error.
# restore --succession: as --from, the carrier being the file's task where it is owner/repo#N, else none; the check
# line counts only where it names one of the file's transcripts, else the read starts at the predecessor's bookmark
# (<workDir>/.agent/state/<id>.json), else at line 1. On exit 0 it leaves <state>/<session>-succession.done, and a
# later start of the session does not read the file again.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/state.sh
. "${BASH_SOURCE[0]%/*}/lib/state.sh"
# shellcheck source=SCRIPTDIR/lib/cut.sh
. "${BASH_SOURCE[0]%/*}/lib/cut.sh"

usage() { sed -n '7,27p' "$0" | sed 's/^# \{0,1\}//'; }
cmd="${1:-}"
case "$cmd" in save|report|restore) shift ;; *) usage >&2; exit 2 ;; esac
carriers=(); transcript=""; session="${CLAUDE_CODE_SESSION_ID:-}"; undone=""; from=""; pred=""; none=""; none_set=""
succ_file=""; succ_nocarrier=""; none_switch=""
carrier_of() { # owner/repo#N or its issue URL -> owner/repo#N on stdout, exit 1 where it is neither
  local c="$1"
  [[ $c =~ ^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)/?$ ]] && c="${BASH_REMATCH[1]}#${BASH_REMATCH[3]}"
  [[ $c =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] && printf '%s' "$c"
}
if [ "$cmd" = report ] && [ "${1:-}" = --replay ]; then
  shift
  [ $# -gt 0 ] || { usage >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || { echo "jq missing" >&2; exit 2; }
  readable=0
  for t in "$@"; do [ ! -r "$t" ] || readable=1; done
  cut_replay "$@"
  [ "$readable" = 1 ] || exit 2
  exit 0
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --carrier) [ "$cmd" != report ] || { usage >&2; exit 2; }
      [[ ${2:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] || { echo "--carrier takes owner/repo#N: '${2:-}'" >&2; exit 2; }
      carriers+=("$2"); shift 2 ;;
    --undone) [ "$cmd" = report ] || { usage >&2; exit 2; }
      undone=1; shift ;;
    --from) [ "$cmd" = restore ] || { usage >&2; exit 2; }
      from="$(carrier_of "${2:-}")" || { echo "--from takes owner/repo#N or its issue URL: '${2:-}'" >&2; exit 2; }
      shift 2 ;;
    --succession) if [ "$cmd" != restore ] || [ -z "${2:-}" ]; then usage >&2; exit 2; fi
      succ_file="$2"; shift 2 ;;
    --none) if [ "$cmd" != restore ] || [ $# -lt 2 ]; then usage >&2; exit 2; fi
      none="$2"; none_set=1; shift 2 ;;
    --predecessor) [ "$cmd" = restore ] || { usage >&2; exit 2; }
      [[ ${2:-} =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "--predecessor takes a session name: '${2:-}'" >&2; exit 2; }
      pred="$2"; shift 2 ;;
    --transcript) transcript="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --session) session="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || { echo "no session id: set CLAUDE_CODE_SESSION_ID or pass --session" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || mapfile -t carriers <<< "$(printf '%s\n' "${carriers[@]}" | sort -u)"
if [ "$cmd" = restore ] && [ -n "$none_set" ]; then
  if [ -n "$from$pred$succ_file" ] || [ ${#carriers[@]} -gt 0 ]; then
    echo "restore --none takes no --from, --predecessor, --succession or --carrier" >&2; exit 2
  fi
  [[ $none =~ [^[:space:]] ]] || { echo "restore --none takes the reason why there is no predecessor: '$none'" >&2; exit 1; }
  # The way out of the lock of /controller-mode and of a switch: lifted first, so nothing below (jq, the cuts file)
  # can keep it.
  rm -f "$cut_gate/$session-restore-owed"
  if grep -qx 'cut=switch' "$cut_gate/$session-compact-lock" 2>/dev/null; then
    rm -f "$cut_gate/$session-compact-lock" "$cut_gate/$session-compact-lock-denies"; none_switch=1
  fi
fi
[ -z "$from" ] || [ -z "$succ_file" ] || { echo "restore takes --from or --succession, not both" >&2; exit 2; }
nojq=""; command -v jq >/dev/null 2>&1 || nojq=1
[ -z "$nojq" ] || [ "$cmd" = report ] || { echo "jq missing" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || command -v gh >/dev/null 2>&1 || { echo "gh missing" >&2; exit 2; }
if [ "$cmd" = restore ] && [ -z "$none_set" ] && [ -z "$succ_file" ]; then
  [ -n "$from" ] || { echo "restore takes --from <owner/repo#N>, --succession <file> or --none \"<reason>\"" >&2; usage >&2; exit 2; }
  command -v gh >/dev/null 2>&1 || { echo "gh missing" >&2; exit 2; }
fi

if [ "$cmd" = report ] || [ "$cmd" = restore ]; then
  # The marker names the transcript of its compaction; an unreadable one is a line, not an error.
  [ -n "$transcript" ] || [ ! -r "$cut_gate/$session-cut-pending" ] \
    || transcript="$(cut_marker_get "$cut_gate/$session-cut-pending" transcript)"
  state_transcript "$transcript" "$session" 2>/dev/null || state_tx=""
else
  state_transcript "$transcript" "$session" || exit 2
fi
# The project: CLAUDE_PROJECT_DIR, else the session's own cwd from its transcript, else git, else here.
root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || [ -z "$state_tx" ] || { root="$(head -n 20 "$state_tx" | jq -r 'select(.cwd? | type == "string") | .cwd' 2>/dev/null | head -n 1)"; root="${root%$'\r'}"; [ -d "$root" ] || root=""; }
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="$PWD"
state_dir="${root%/}/.agent/state"
mkdir -p "$state_dir" || { echo "cannot write $state_dir" >&2; exit 2; }
state_file="$state_dir/$session.json"; list="$state_dir/$session-save.md"; pairs="$state_dir/$session-pairs.md"

if [ "$cmd" = restore ]; then
  # shellcheck source=SCRIPTDIR/lib/successor.sh
  . "${BASH_SOURCE[0]%/*}/lib/successor.sh"
  cut_facts "$root" "$session"
  if [ -n "$none_set" ]; then
    if [ -n "$none_switch" ] && [ -f "$cut_gate/$session-cut-pending" ]; then succ_none_switch "$none" "$state_dir/cuts.jsonl" || exit 2
    else succ_none "$none" "$state_dir/cuts.jsonl" || exit 2; fi
    exit 0
  fi
  if [ -n "$succ_file" ]; then
    succ_file_read "$succ_file" || { echo "succession file not readable as version 1: $succ_file" >&2; exit 2; }
    from="$(carrier_of "$succ_ftask")" || from=""
    # Without gh the carrier is not read: the restore stands without it, and its head says so.
    if [ -n "$from" ] && ! command -v gh >/dev/null 2>&1; then succ_nocarrier="gh is missing, so the carrier $from was not read"; from=""; fi
  fi
  succ_restore "$from" "$pred" ${carriers[@]+"${carriers[@]}"} || exit 2
  [ -z "$succ_file" ] || printf 'predecessor=%s\nat=%s\n' "$succ_fpred" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$state_dir/$session-succession.done"
  exit 0
fi

# The report after each cut: report itself, and the first step of save (a standing marker as done false).
if [ -n "$nojq" ]; then
  # Without jq the marker's cut still gets its line: a bare one with notChecked jq, then the marker goes.
  if [ -r "$cut_gate/$session-cut-pending" ]; then
    d=true; [ -z "$undone" ] || d=false
    cut_bare "$session" "$d" "$(cut_marker_get "$cut_gate/$session-cut-pending" cut)" >> "$state_dir/cuts.jsonl" \
      && rm -f "$cut_gate/$session-cut-pending"
  fi
  echo "jq missing: bare line in $state_dir/cuts.jsonl" >&2
  exit 0
fi
cut_facts "$root" "$session"
if [ "$cmd" = report ]; then
  mode="done"; [ -z "$undone" ] || mode=undone
  cut_report "$mode" "$state_tx" "$session" "$state_file" "$state_dir/cuts.jsonl" || { echo "report failed" >&2; exit 2; }
  echo "report: $state_dir/cuts.jsonl"
  exit 0
fi
cut_report undone "$state_tx" "$session" "$state_file" "$state_dir/cuts.jsonl" && rm -f "$cut_gate/$session-cut-pending"

# After rc revive: the old id's cursor, check line, carriers and last list come along (lib/state.sh, state_revive).
CLAUDE_PROJECT_DIR="$root" state_revive "$state_dir" "$session" "$state_tx" || { echo "cannot take over the state of the revived session" >&2; exit 2; }
[ -z "$state_revived" ] || echo "revived from $state_revived: its cursor, check line, carriers and last list taken over"
state_cursor "$state_file" "$state_tx"
echo "$state_start_note"

work="$(hook_mktemp -d session-state)" || { echo "no temp folder" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
unexamined_mark="$(state_unexamined_mark "$state_dir" "$session")"
state_extract "$state_tx" "$state_start" "$(state_unexamined_from "$unexamined_mark" "$state_tx")" > "$work/cand.jsonl" || { echo "transcript not parsed: $state_tx" >&2; exit 2; }
state_haystack "$work" "${carriers[@]}" || exit 2
[ ${#carriers[@]} -gt 0 ] || echo "no --carrier: only the further channel is the haystack"
printf '%s' "$state_hay_note"
[ ${#state_bodies[@]} -eq 0 ] || state_open_point_warnings "${state_bodies[@]}"
state_match "$work" "$work/cand.jsonl" > "$work/open.jsonl" || { echo "match failed" >&2; exit 2; }
# A reported action without its tool call in the turn is a box too, carried or not (ww3d/playbook#621).
if state_claims "$state_tx" "$work/cand.jsonl" "$work" > "$work/claims-open.jsonl"; then
  cat "$work/claims-open.jsonl" >> "$work/open.jsonl"
else
  echo "claims: not checked (the tool calls were not read)"
fi
# The state of every reference in the pairs and the open boxes of the carriers, checked here (ww3d/playbook#672).
state_stale_lines "$work" "$work/pairs.txt" ${carriers[@]+"${carriers[@]}"} > "$work/stale-lines.jsonl"
state_stale "$work/stale-lines.jsonl" "$work" >> "$work/open.jsonl"
stale_note="$(head -n 1 "$work/stale.note" 2>/dev/null | tr -d '\r')"
[ -z "$stale_note" ] || echo "$stale_note"
# The pairs, rebuilt each run: what a carrier holds, with the carrier line that holds it; only those no pattern
# judges, filled up to 8 from before the cursor.
if ! { cp "$work/pairs.txt" "$work/pairs.run" && state_pairs_plain < "$work/pairs.run" > "$work/pairs.plain" \
  && state_pairs_fill "$work" "$state_tx" "$state_start" "$work/pairs.plain" > "$pairs"; }; then
  echo "cannot write $pairs" >&2; exit 2
fi
cs_json="$(printf '%s\n' ${carriers[@]+"${carriers[@]}"} | jq -R 'select(length > 0)' | jq -sc .)" || cs_json='[]'
unexamined="$(state_unexamined_new "$work/cand.jsonl" "$unexamined_mark" "$state_tx")"
CLAUDE_PROJECT_DIR="$root" state_worklist "$work/open.jsonl" "$list" "$session" "${unexamined:-0}" "$work" "$cs_json" \
  || { echo "cannot write $list" >&2; exit 2; }
# The save is a cut too (question 1916 a): its report carries the balance of its list.
cut_save "$session" "$state_cut" "$state_dir/cuts.jsonl" "$root" || echo "report of the save: not written"

if [ "$state_open" -gt 0 ]; then
  echo "$state_open open in $state_cut: carry each to a carrier and run save again, or close it with bash .claude/hooks/ticks.sh close <id> erledigt <reference> | ungeprueft <reason> | abgelegt <reason> --list $state_cut"
  exit 3
fi

end_line=""; end_uuid=""
{ IFS= read -r end_line; IFS= read -r end_uuid; } <<< "$(jq -r 'select(has("end")) | .end // {} | (.line // "" | tostring), (.uuid // "")' < "$work/cand.jsonl")" || true
# A jq for Windows ends its lines with CR LF.
end_line="${end_line%$'\r'}"; end_uuid="${end_uuid%$'\r'}"
if ! [[ $end_line =~ ^[0-9]+$ ]]; then end_line=$((state_start - 1)); fi
checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
checked="${checked_at:0:13}${checked_at:14:2}Z"
unchecked_note=""; [ "${state_unchecked:-0}" -eq 0 ] || unchecked_note="unchecked: $state_unchecked"
check_line="checked: $checked · cursor: $state_tx L$end_line $end_uuid${unchecked_note:+ · $unchecked_note}${stale_note:+ · $stale_note}"
# The restore after the next compaction starts behind this cursor and asks the forge for what changed since
# checkedAt at these carriers (restore-compact-state.sh). The report's lastCut fields stay.
last_cut="$(jq -c '{lastCutUuid, lastCutLine} | with_entries(select(.value != null))' "$state_file" 2>/dev/null | tr -d '\r')" || last_cut=""
[ -n "$last_cut" ] || last_cut='{}'
jq -n --argjson lc "$last_cut" --arg t "$state_tx" --argjson l "$end_line" --arg u "$end_uuid" --arg c "$checked" --arg a "$checked_at" \
  --arg k "$check_line" --args '{cursor: {transcript: $t, line: $l, uuid: $u}, checked: $c, checkedAt: $a,
  checkLine: $k, carriers: $ARGS.positional} + $lc' ${carriers[@]+"${carriers[@]}"} > "$state_file.tmp" \
  || { echo "cannot write $state_file" >&2; exit 2; }
mv -f "$state_file.tmp" "$state_file" || { echo "cannot write $state_file" >&2; exit 2; }
echo "$check_line"
exit 0
