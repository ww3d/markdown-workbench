#!/usr/bin/env bash
# Hook suite section: require-live-state.sh, cost of a hook call without an open event (timed)
# Run alone: bash .claude/hooks/tests/cases/require-live-state-timing.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# hook-tests: run alone - its cases measure wall time, so run-tests.sh starts it after the parallel sections
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-live-state.sh: a call without an open event costs under 50 ms of its own (ww3d/playbook#577) =="
# Stop and record run at every turn end and after every Bash call; without an open event they read no network
# and start no jq. The hook's own cost counts: its time minus the time of an empty bash script that reads the same
# input (a bash start alone costs 80-100 ms on Windows). The best of three runs counts on both sides (a CPU burst
# hits one); `timeout` only keeps a hang out.
live="$hooks/require-live-state.sh"
export TMPDIR="$fix/live-timing"; mkdir -p "$TMPDIR"
empty="$TMPDIR/empty.sh"; printf 'cat >/dev/null\n' > "$empty"
best_ms() { # payload, script, [argument] -> global ms
  local t0 t1 m
  ms=999999
  for _ in 1 2 3; do
    t0=$EPOCHREALTIME
    printf '%s' "$1" | CLAUDE_PROJECT_DIR="$repo_root" timeout 10 bash "$2" ${3:+"$3"} >/dev/null 2>&1
    t1=$EPOCHREALTIME
    m="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"
    [ "$m" -ge "$ms" ] || ms=$m
  done
}
own() { # label, payload, [hook argument]: the hook's best time minus the empty script's
  local base hook cost
  best_ms "$2" "$empty"; base=$ms
  best_ms "$2" "$live" "${3:-}"; hook=$ms
  cost=$((hook - base))
  if [ "$cost" -lt 50 ]; then ok "$1: own cost under 50 ms" "$cost ms ($hook - $base)"
  else bad "$1: own cost under 50 ms" "$cost ms ($hook - $base)" '< 50 ms'; fi
}

own 'stop, nothing recorded' '{"session_id":"timing-1","hook_event_name":"Stop","stop_hook_active":false}'
own 'record, a Bash call without gh' '{"session_id":"timing-1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"stdout":""}}' --record
own 'stop after a call without gh' '{"session_id":"timing-1","hook_event_name":"Stop","stop_hook_active":false}'
own 'record, a Bash call whose output holds gh' '{"session_id":"timing-1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git log -1"},"tool_response":{"stdout":"though the high right"}}' --record
own 'record, a connector read' '{"session_id":"timing-1","hook_event_name":"PostToolUse","tool_name":"mcp__github__get_file_contents","tool_input":{"owner":"o","repo":"r","path":"x"},"tool_response":"x"}' --record

finish
