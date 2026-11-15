#!/usr/bin/env bash
#
# Replay of the shared-temp guard (ww3d/playbook#619) over real transcripts: runs every Bash, PowerShell, Write,
# Edit and NotebookEdit call of the last N days through the same detection the hook uses (lib/tmp-guard.sh) and
# prints each hit and the sums. The guard is switched to `block` only when this finds no false alarm over 7 days.
#
# Usage:  bash .claude/hooks/tests/replay-tmp-guard.sh [--days N] [--root DIR] [--quiet]
#   --days N   the last N days by the call's own timestamp (default 7)
#   --root DIR transcripts below DIR/**/*.jsonl (default: ${CLAUDE_CONFIG_DIR:-~/.claude}/projects)
#   --quiet    sums only
# Output: one line per hit `HIT <time> <session> <tool> <path> :: <call, one line, 160 characters>`, then
#         `CALLS <n>`, `CANDIDATES <n>` (calls that name a shared root or temp variable at all), `HITS <n>`,
#         `HIT-SESSIONS <n>`, `HIT-PATHS <n>`, `OWN-AREA <n>` (writes into a session scratchpad or /tmp/claude-0/,
#         left out of the hits).
# Cost: one jq reads all files; bash decides on each call with builtins and only a candidate call starts the
# splitter (one awk). The session's scratchpad_dir is not in a transcript: the own area is the session id.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tg_lib="$here/../lib"
# shellcheck source=SCRIPTDIR/../lib/tmp-guard.sh
. "$tg_lib/tmp-guard.sh" || { echo "cannot load lib/tmp-guard.sh" >&2; exit 2; }

days=7; root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; quiet=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:-}"; shift 2 || exit 2 ;;
    --root) root="${2:-}"; shift 2 || exit 2 ;;
    --quiet) quiet=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$days" in ''|*[!0-9]*|0) echo "--days takes a whole number from 1" >&2; exit 2 ;; esac
[ -d "$root" ] || { echo "no transcripts folder: $root" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq needed" >&2; exit 2; }

cutoff="$(date -u -d "-$days days" +%Y-%m-%dT%H:%M:%S 2>/dev/null)" || { echo "date -d needed" >&2; exit 2; }
calls=0; cand=0; hits=0; own=0
declare -A hit_sessions=() hit_paths=()
us=$'\037'; rs=$'\036'
# shellcheck disable=SC2016 # a jq program
prog='select(.type == "assistant" and (.timestamp // "") >= $cut)
  | (.timestamp // "") as $t | (.sessionId // "") as $s
  | .message.content[]? | select(.type == "tool_use" and (.name | IN("Bash", "PowerShell", "Write", "Edit", "NotebookEdit")))
  | [$t, $s, .name, (.input.file_path // .input.notebook_path // .input.command // "" | tostring)]
  | join("\u001f") + "\u001e"'

while IFS= read -r -d "$rs" rec; do
  calls=$((calls + 1))
  ts="${rec%%"$us"*}"; rec="${rec#*"$us"}"
  sid="${rec%%"$us"*}"; rec="${rec#*"$us"}"
  tool="${rec%%"$us"*}"; subject="${rec#*"$us"}"
  [ -n "$subject" ] || continue
  tg_mentions "$subject" || continue
  cand=$((cand + 1))
  tg_init "$sid" ""
  tg_detect "$tool" "$subject" || continue
  [ "${#tg_hits[@]}" -gt 0 ] || continue
  for h in "${tg_hits[@]}"; do
    # A transcript does not hold the live scratchpad_dir: a resumed session writes into the scratchpad of its first
    # id, and a web session into its own /tmp/claude-0/. The hook sees both as the session's own area.
    hn="${h//\\//}"
    if [[ $hn =~ /claude-sessions/claude/[^/]+/[0-9a-f]{8}-[0-9a-f]{4}- || $hn == /tmp/claude-0/* ]]; then own=$((own + 1)); continue; fi
    hits=$((hits + 1)); hit_sessions["$sid"]=1; hit_paths["$h"]=1
    if [ "$quiet" = 0 ]; then
      one="${subject//[$'\n\r\t']/ }"
      printf 'HIT %s %s %s %s :: %.160s\n' "$ts" "$sid" "$tool" "$h" "$one"
    fi
  done
done < <(find "$root" -name '*.jsonl' -mtime "-$((days + 1))" -print0 | xargs -0 -r jq -j --arg cut "$cutoff" "$prog" 2>/dev/null)

printf 'CALLS %s\nCANDIDATES %s\nHITS %s\nHIT-SESSIONS %s\nHIT-PATHS %s\nOWN-AREA %s\n' "$calls" "$cand" "$hits" "${#hit_sessions[@]}" "${#hit_paths[@]}" "$own"
