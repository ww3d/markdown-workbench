#!/usr/bin/env bash
#
# SICHERN before a compaction or a switch (ww3d/playbook#487): what the session was told, asked, decided and
# promised since its cursor, held against the texts of its carriers. Generic, byte-identical across consumers;
# a command the session runs, no hook. Core: lib/state.sh.
#
# Usage:  bash session-state.sh save [--carrier <owner/repo#N>]... [--transcript <path>] [--session <id>]
#   --carrier     a carrier of the session (tracking issue, PR); repeatable. Its body, the bodies it links
#                 (one level) and the text of PLAYBOOK_CARRIER_TEXT_CMD form the haystack.
#   --transcript  default: <CLAUDE_CODE_SESSION_ID>.jsonl under ~/.claude/projects/*/
#   --session     default: CLAUDE_CODE_SESSION_ID
#
# Files, under <project>/.agent/state/ (git-ignored):
#   <session>-save.md  the work list: "- [ ] L<line> <UTC> <art>: <text>" per candidate no carrier holds;
#                      the session carries each or ticks it "- [x] <box> -> <proof>", and runs save again
#   <session>.json     cursor (transcript, line, uuid), checked (UTC) and checkLine; written on exit 0 only
#
# Exit: 0 no box open (cursor and check line written, the check line printed), 3 boxes open, 2 a read
# error (transcript, carrier, jq or gh missing) or a usage error; the output names what was missing.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/state.sh
. "${BASH_SOURCE[0]%/*}/lib/state.sh"

usage() { sed -n '7,12p' "$0" | sed 's/^# \{0,1\}//'; }
[ "${1:-}" = save ] || { usage >&2; exit 2; }
shift
carriers=(); transcript=""; session="${CLAUDE_CODE_SESSION_ID:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --carrier) [[ ${2:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] || { echo "--carrier takes owner/repo#N: '${2:-}'" >&2; exit 2; }
      carriers+=("$2"); shift 2 ;;
    --transcript) transcript="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --session) session="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || { echo "no session id: set CLAUDE_CODE_SESSION_ID or pass --session" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || mapfile -t carriers <<< "$(printf '%s\n' "${carriers[@]}" | sort -u)"
command -v jq >/dev/null 2>&1 || { echo "jq missing" >&2; exit 2; }
[ ${#carriers[@]} -eq 0 ] || command -v gh >/dev/null 2>&1 || { echo "gh missing" >&2; exit 2; }

state_transcript "$transcript" "$session" || exit 2
# The project: CLAUDE_PROJECT_DIR, else the session's own cwd from its transcript, else git, else here.
root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || { root="$(head -n 20 "$state_tx" | jq -r 'select(.cwd? | type == "string") | .cwd' 2>/dev/null | head -n 1)"; root="${root%$'\r'}"; [ -d "$root" ] || root=""; }
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="$PWD"
state_dir="${root%/}/.agent/state"
mkdir -p "$state_dir" || { echo "cannot write $state_dir" >&2; exit 2; }
state_file="$state_dir/$session.json"; list="$state_dir/$session-save.md"

state_cursor "$state_file" "$state_tx"
echo "$state_start_note"

work="$(mktemp -d "${TMPDIR:-/tmp}/session-state.XXXXXX")" || { echo "no temp folder" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
state_extract "$state_tx" "$state_start" > "$work/cand.jsonl" || { echo "transcript not parsed: $state_tx" >&2; exit 2; }
state_haystack "$work" "${carriers[@]}" || exit 2
[ ${#carriers[@]} -gt 0 ] || echo "no --carrier: only the further channel is the haystack"
printf '%s' "$state_hay_note"
[ ${#state_bodies[@]} -eq 0 ] || state_open_point_warnings "${state_bodies[@]}"
state_match "$work/hay.txt" "$work/cand.jsonl" > "$work/open.jsonl" || { echo "match failed" >&2; exit 2; }
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
checked="$(date -u +%Y-%m-%dT%H%MZ)"
check_line="checked: $checked · cursor: $state_tx L$end_line $end_uuid"
jq -n --arg t "$state_tx" --argjson l "$end_line" --arg u "$end_uuid" --arg c "$checked" --arg k "$check_line" \
  '{cursor: {transcript: $t, line: $l, uuid: $u}, checked: $c, checkLine: $k}' > "$state_file.tmp" \
  || { echo "cannot write $state_file" >&2; exit 2; }
mv -f "$state_file.tmp" "$state_file" || { echo "cannot write $state_file" >&2; exit 2; }
# The cross-check after the next compaction starts behind the saved line (restore-compact-state.sh).
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
{ mkdir -p "$gate_dir" && printf '%s pre\n' "$end_line" > "$gate_dir/$session-cross-check-mark"; } 2>/dev/null || true
echo "$check_line"
exit 0
