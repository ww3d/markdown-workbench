#!/usr/bin/env bash
# Hook suite section: guard-kill.sh, cost of a long command (timed)
# Run alone: bash .claude/hooks/tests/cases/guard-kill-timing.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# hook-tests: run alone - its cases measure wall time, so run-tests.sh starts it after the parallel sections
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh: cost of a long command =="
# Many words that hold "kill" in one statement: the scan matches the pattern once per statement, not once
# per word, so its cost grows in step with the text. The long-path cases compare two timings (4x the words
# must cost under 8x), which does not depend on the machine's speed; the short-path case counts the pattern
# runs the hook reports under GUARD_KILL_TRACE instead, because a fixed factor (a missing stop costs ~5x)
# hides in a ratio and wall time wobbles. A real kill behind the words is still found.
# `timeout` and the absolute cap only keep a regression from hanging the suite.
guard_ms() { # prefix, count, path template (N = number) -> globals ms, out
  local c t0 t1 i
  c="$1 $(for i in $(seq 1 "$2"); do printf '%s ' "${3//N/$i}"; done); kill 1234"
  c="$(kill_event Bash "$c")"
  t0=$EPOCHREALTIME
  out="$(printf '%s' "$c" | timeout 25 bash "$guard" 2>&1)"
  t1=$EPOCHREALTIME
  ms="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"
}
best_ms() { # prefix, count, template -> global ms: the faster of two runs (a CPU burst hits one), one run when slow
  local first
  guard_ms "$@"; first=$ms
  if [ "$first" -lt 10000 ]; then guard_ms "$@"; [ "$ms" -le "$first" ] || ms=$first; fi
}
scaled_kill() { # label, prefix, small count, template (N = number), hang cap in ms for 4x the count
  local small big got ratio
  best_ms "$2" "$3" "$4"; small=$ms
  best_ms "$2" "$(($3 * 4))" "$4"; big=$ms
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "$got" = deny ] && has_text 1234 "$out"; then ok "$1: the real kill is found" "$got"; else bad "$1: the real kill is found" "$got" 'deny 1234'; fi
  ratio="$(awk -v a="$small" -v b="$big" 'BEGIN { if (a < 20) a = 20; printf "%.1f", b / a }')"
  # A run that hit the 25 s `timeout` ends at the same time whatever its size, which would read as a flat ratio.
  if [ "$small" -lt 20000 ] && [ "$big" -lt 20000 ] && awk -v r="$ratio" 'BEGIN { exit !(r < 8) }'; then ok "$1: 4x the words cost under 8x" "${small} ms -> ${big} ms, ratio ${ratio}"
  else bad "$1: 4x the words cost under 8x" "${small} ms -> ${big} ms, ratio ${ratio}" 'ratio < 8, no timeout'; fi
  if [ "$big" -lt "$5" ]; then ok "$1: under $5 ms" "${big} ms"; else bad "$1: under $5 ms" "${big} ms" "< $5 ms"; fi
}
long_path='/usr/local/bin/something/kill-switch-config-N.yaml'
scaled_kill '400 long paths after echo'        'echo'      100  "$long_path"   15000
scaled_kill '400 long paths after sudo echo'   'sudo echo' 100  "$long_path"   15000

finish
