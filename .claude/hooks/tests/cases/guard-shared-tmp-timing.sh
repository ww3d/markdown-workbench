#!/usr/bin/env bash
# Hook suite section: guard-shared-tmp.sh, cost of a long call (timed, ww3d/playbook#719)
# Run alone: bash .claude/hooks/tests/cases/guard-shared-tmp-timing.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# hook-tests: run alone - its cases measure wall time, so run-tests.sh starts it after the parallel sections
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-shared-tmp.sh: cost of a long call (ww3d/playbook#719) =="
# Step 1 cuts the envelope's folders out of the raw text. Cut with a pattern of no fixed length, its cost grows with
# the square of the envelope and a Write of 8 KB runs into Claude Code's 30 s limit, after which the call runs
# unguarded. 4x the text must cost under 8x (a square costs 16x), which does not depend on the machine's speed; the
# guard still warns on a temp path behind the text. `timeout` and the cap only keep a regression from hanging the suite.
gst_guard="$hooks/guard-shared-tmp.sh"
gst_dir="$fix/tmpguard-timing"; mkdir -p "$gst_dir"
unset PLAYBOOK_TMP_GUARD PLAYBOOK_TMP_GUARD_OWN PLAYBOOK_TMP_GUARD_TIMEOUT CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR

gst_event() { # bytes of content, file path -> a Write envelope in Claude Code's field order, with its folders
  local text='Ein Satz mit "Zitat" und Pfad docs/a.md.' c="" p
  while [ "${#c}" -lt "$1" ]; do c+="$text"$'\n'; done
  js "${c:0:$1}"; c="$REPLY"; js "$2"; p="$REPLY"
  printf '{"session_id":"t1","transcript_path":"C:\\\\Users\\\\u\\\\.claude\\\\projects\\\\p\\\\t1.jsonl","cwd":"D:\\\\rc-work\\\\x\\\\playbook","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":%s,"content":%s},"tool_use_id":"toolu_t1","scratchpad_dir":"D:\\\\tmp\\\\claude\\\\t1\\\\scratchpad"}' "$p" "$c"
}
gst_ms() { # bytes, file path -> globals ms, out
  local ev t0 t1
  ev="$(gst_event "$1" "$2")"
  t0=$EPOCHREALTIME
  out="$(printf '%s' "$ev" | TMPDIR="$gst_dir" PLAYBOOK_TMP_GUARD_LOG="$gst_dir/log.jsonl" timeout 25 "$BASH" "$gst_guard" 2>/dev/null)"
  t1=$EPOCHREALTIME
  ms=$(( (10#${t1//[.,]/} - 10#${t0//[.,]/}) / 1000 ))
}
gst_best() { # bytes, file path -> global ms: the faster of two runs (a CPU burst hits one), one run when slow
  local first
  gst_ms "$@"; first=$ms
  if [ "$first" -lt 10000 ]; then gst_ms "$@"; [ "$ms" -le "$first" ] || ms=$first; fi
}
gst_scaled() { # label, small bytes, file path, verdict (PASS|WARN), cap in ms for 4x the bytes
  local small big got ratio
  gst_best "$2" "$3"; small=$ms
  gst_best "$(($2 * 4))" "$3"; big=$ms
  if [ -z "$out" ]; then got=PASS; elif has_text '"additionalContext"' "$out"; then got=WARN; else got=ERR; fi
  expect "$1: the verdict holds" "$4" "$got"
  ratio="$(awk -v a="$small" -v b="$big" 'BEGIN { if (a < 20) a = 20; printf "%.1f", b / a }')"
  # A run that hit the 25 s `timeout` ends at the same time whatever its size, which would read as a flat ratio.
  if [ "$small" -lt 20000 ] && [ "$big" -lt 20000 ] && awk -v r="$ratio" 'BEGIN { exit !(r < 8) }'; then ok "$1: 4x the text costs under 8x" "${small} ms -> ${big} ms, ratio ${ratio}"
  else bad "$1: 4x the text costs under 8x" "${small} ms -> ${big} ms, ratio ${ratio}" 'ratio < 8, no timeout'; fi
  if [ "$big" -lt "$5" ]; then ok "$1: under $5 ms" "${big} ms"; else bad "$1: under $5 ms" "${big} ms" "< $5 ms"; fi
}
gst_scaled 'a Write of 1.5 and 6 KB in the project'  1500 'D:\rc-work\x\playbook\docs\a.md' PASS 5000
gst_scaled 'a Write of 1.5 and 6 KB to /tmp'          1500 '/tmp/prbody.md'                  WARN 5000

finish
