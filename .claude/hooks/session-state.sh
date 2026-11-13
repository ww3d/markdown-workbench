#!/usr/bin/env bash
#
# SICHERN before a compaction or a switch (ww3d/playbook#487): what the session was told, asked, decided and
# promised since its cursor, held against the texts of its carriers. Generic, byte-identical across consumers;
# a command the session runs, no hook. Core: lib/state.sh; the report after each cut: lib/cut.sh.
#
# Usage:  bash session-state.sh save [--carrier <owner/repo#N>]... [--transcript <path>] [--session <id>]
#         bash session-state.sh report [--undone] [--transcript <path>] [--session <id>]
#         bash session-state.sh report --replay <transcript>...
#   --carrier     a carrier of the session (tracking issue, PR); repeatable. Its body, the bodies it links
#                 (one level) and the text of PLAYBOOK_CARRIER_TEXT_CMD form the haystack.
#   --transcript  default: the marker's transcript, else <CLAUDE_CODE_SESSION_ID>.jsonl under ~/.claude/projects/*/
#   --session     default: CLAUDE_CODE_SESSION_ID
#   --undone      report the standing marker as a line with done false (restore-compact-state.sh, before a new one)
#   --replay      one line per main-thread compaction of each transcript on stdout, from the transcript alone;
#                 writes nothing (what needs the restore file stands in notChecked)
#
# Files, under <project>/.agent/state/ (git-ignored):
#   <session>-save.md  the work list: "- [ ] L<line> <UTC> <art>: <text>" per candidate no carrier holds and per
#                      own report of an action (pushed, sent, commented) without its tool call in its turn (claim);
#                      the session carries each or ticks it "- [x] <box> -> <proof>", and runs save again
#   <session>-pairs.md "L<line> <art>: <candidate> => <owner/repo#N>: <carrier line>" per candidate a carrier
#                      holds, rebuilt each run; a helper checks them where the kind compacts (pair-check.md)
#   <session>.json     cursor (transcript, line, uuid), checked (UTC), checkedAt, checkLine and the carriers,
#                      written on exit 0 of save; lastCutUuid and lastCutLine, the newest boundary report has seen
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
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/state.sh
. "${BASH_SOURCE[0]%/*}/lib/state.sh"
# shellcheck source=SCRIPTDIR/lib/cut.sh
. "${BASH_SOURCE[0]%/*}/lib/cut.sh"

usage() { sed -n '7,17p' "$0" | sed 's/^# \{0,1\}//'; }
cmd="${1:-}"
case "$cmd" in save|report) shift ;; *) usage >&2; exit 2 ;; esac
carriers=(); transcript=""; session="${CLAUDE_CODE_SESSION_ID:-}"; undone=""
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
    --carrier) [ "$cmd" = save ] || { usage >&2; exit 2; }
      [[ ${2:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] || { echo "--carrier takes owner/repo#N: '${2:-}'" >&2; exit 2; }
      carriers+=("$2"); shift 2 ;;
    --undone) [ "$cmd" = report ] || { usage >&2; exit 2; }
      undone=1; shift ;;
    --transcript) transcript="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --session) session="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || { echo "no session id: set CLAUDE_CODE_SESSION_ID or pass --session" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || mapfile -t carriers <<< "$(printf '%s\n' "${carriers[@]}" | sort -u)"
nojq=""; command -v jq >/dev/null 2>&1 || nojq=1
[ -z "$nojq" ] || [ "$cmd" = report ] || { echo "jq missing" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || command -v gh >/dev/null 2>&1 || { echo "gh missing" >&2; exit 2; }

if [ "$cmd" = report ]; then
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

# The report after each cut: report itself, and the first step of save (a standing marker as done false).
if [ -n "$nojq" ]; then
  # Without jq the marker's cut still gets its line: a bare one with notChecked jq, then the marker goes.
  if [ -r "$cut_gate/$session-cut-pending" ]; then
    d=true; [ -z "$undone" ] || d=false
    cut_bare "$session" "$d" >> "$state_dir/cuts.jsonl" && rm -f "$cut_gate/$session-cut-pending"
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

state_cursor "$state_file" "$state_tx"
echo "$state_start_note"

work="$(mktemp -d "${TMPDIR:-/tmp}/session-state.XXXXXX")" || { echo "no temp folder" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
state_extract "$state_tx" "$state_start" > "$work/cand.jsonl" || { echo "transcript not parsed: $state_tx" >&2; exit 2; }
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
# The pairs, rebuilt each run: what a carrier holds, with the carrier line that holds it.
mv -f "$work/pairs.txt" "$pairs" || { echo "cannot write $pairs" >&2; exit 2; }
state_worklist "$work/open.jsonl" "$list" "$list" || { echo "cannot write $list" >&2; exit 2; }

if [ "$state_open" -gt 0 ]; then
  echo "$state_open open in $list: carry each to a carrier or tick it '- [x] <box> -> <proof>', then run save again"
  exit 3
fi

end_line=""; end_uuid=""
{ IFS= read -r end_line; IFS= read -r end_uuid; } <<< "$(jq -r 'select(has("end")) | .end // {} | (.line // "" | tostring), (.uuid // "")' < "$work/cand.jsonl")" || true
# A jq for Windows ends its lines with CR LF.
end_line="${end_line%$'\r'}"; end_uuid="${end_uuid%$'\r'}"
if ! [[ $end_line =~ ^[0-9]+$ ]]; then end_line=$((state_start - 1)); fi
checked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
checked="${checked_at:0:13}${checked_at:14:2}Z"
check_line="checked: $checked · cursor: $state_tx L$end_line $end_uuid"
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
