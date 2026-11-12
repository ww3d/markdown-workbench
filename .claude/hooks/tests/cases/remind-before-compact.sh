#!/usr/bin/env bash
# Hook suite section: remind-before-compact.sh, the reminder before the compaction
# Run alone: bash .claude/hooks/tests/cases/remind-before-compact.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== remind-before-compact.sh: before the limit (ww3d/playbook#487) =="
remind_cs="$hooks/remind-before-compact.sh"
rm_tx="$fix/remind.jsonl"
usage_line() { # tokens in the cache read -> one assistant line with that fill
  printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":5}}}\n' "$(($1 - 2))"
}
cs_remind() { # session, transcript, then NAME=value env settings or one bare sub-agent id
  local s="$1" t="$2" a="" e=(); shift 2
  # the 15-second look is the hook's own; a test starts every call with a state old enough to pass it
  mkdir -p "$cs_gate"; [ -n "${CS_KEEP_STATE:-}" ] || printf '0 0\n' > "$cs_gate/$s-remind-state"
  for x in "$@"; do case "$x" in *=*) e+=("$x") ;; *) a="$x" ;; esac; done
  remind_event "$s" "$t" "$a" \
    | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u ANTHROPIC_MODEL -u CLAUDE_CODE_DISABLE_1M_CONTEXT \
      TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="${CS_ROOT:-}" "${e[@]}" bash "$remind_cs"
}
remind_ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
usage_line 100000 > "$rm_tx"
out="$(cs_remind rm1 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"; rc=$?
expect 'remind: below 85 percent of the default limit, rc 0 and no output' '0:' "$rc:$out"
usage_line 150000 > "$rm_tx"
out="$(cs_remind rm1 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"; rc=$?
expect 'remind: past 85 percent, rc 0' 0 "$rc"
ctx="$(remind_ctx "$out")"
check_contains 'remind: the hint asks for SICHERN first' 'SICHERN' "$ctx"
check_contains 'remind: the hint names session-state.sh save' 'session-state.sh save' "$ctx"
check_not_contains 'remind: the hint names no helper' 'cross-check.md' "$ctx"
expect 'remind: the event name is PostToolUse' PostToolUse "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
present_file 'remind: the run is marked' "$cs_gate/rm1-remind-sent"
out="$(cs_remind rm1 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
expect 'remind: once per run' '' "$out"
cs_save rm1 "$rm_tx" >/dev/null 2>&1
absent_file 'a compaction ends the run: its mark goes' "$cs_gate/rm1-remind-sent"
out="$(cs_remind rm1 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
check_contains 'remind: after the compaction the next run reminds again' 'SICHERN' "$(remind_ctx "$out")"
check_not_contains 'remind: without a kind the hint names no pair check' 'pair-check.md' "$ctx"
# A boundary after the last usage: that fill is from before the compaction, so the run stays silent and unmarked;
# a new usage after the boundary counts again.
{ usage_line 180000; boundary; } > "$rm_tx"
out="$(cs_remind rm30 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"; rc=$?
expect 'boundary after the last usage: rc 0 and no output' '0:' "$rc:$out"
absent_file 'boundary after the last usage: no run mark' "$cs_gate/rm30-remind-sent"
absent_file 'boundary after the last usage: no mark of the kind' "$cs_gate/rm30-remind-mark"
usage_line 180000 >> "$rm_tx"
out="$(cs_remind rm30 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
check_contains 'a new usage after the boundary: the reminder comes again' 'SICHERN' "$(remind_ctx "$out")"
present_file 'a new usage after the boundary: the run is marked' "$cs_gate/rm30-remind-sent"
# Large tool results since the last answer count before the next answer measures them (about 4 characters a
# token), even inside the 15-second pause. Limit 168,000 of a 200,000 window, the notice from 142,800.
cs_big() { # session, transcript, characters of the tool result -> the hook's output, the pause running
  local p; p="$(remind_event "$1" "$2")"; printf '%s 0\n' "$(date +%s)" > "$cs_gate/$1-remind-state"
  printf '%s,"tool_response":"%s"}\n' "${p%\}}" "$(printf '%*s' "$3" '' | tr ' ' x)" \
    | env -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u ANTHROPIC_MODEL -u CLAUDE_CODE_DISABLE_1M_CONTEXT TMPDIR="$cs_tmp" \
      CLAUDE_PROJECT_DIR="" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 bash "$remind_cs" 2>&1
}
usage_line 120000 > "$rm_tx"
expect 'big results: 12,500 more tokens stay below the notice' '' "$(cs_big rm40 "$rm_tx" 50000)"
check_contains 'big results: the next one carries the estimate past 85 percent' 'SICHERN' "$(remind_ctx "$(cs_big rm40 "$rm_tx" 50000)")"
present_file 'big results: the estimate marks the run' "$cs_gate/rm40-remind-sent"
expect 'big results: the estimate spends the one notice once' '' "$(cs_big rm40 "$rm_tx" 50000)"
cs_big rm41 "$rm_tx" 50000 >/dev/null; usage_line 121000 >> "$rm_tx"
expect 'big results: a new answer measures them, the estimate starts anew' '' "$(cs_big rm41 "$rm_tx" 50000)"
{ usage_line 140000; boundary; } > "$rm_tx"
expect 'big results: right after a compaction no estimate' '' "$(cs_big rm42 "$rm_tx" 100000)"
absent_file 'big results: right after a compaction the run stays unmarked' "$cs_gate/rm42-remind-sent"
# The hooks of one parallel turn can run at once: a line a sibling wrote under this fill stays counted.
usage_line 120000 > "$rm_tx"; printf '100000 400000\n120000 50000\n' > "$cs_gate/rm44-remind-pend"
check_contains "big results: a sibling's line under the same fill stays counted" 'SICHERN' \
  "$(remind_ctx "$(cs_big rm44 "$rm_tx" 50000)")"
pids=(); for _ in 1 2 3 4; do cs_big rm45 "$rm_tx" 20000 >/dev/null & pids+=($!); done; wait "${pids[@]}"
expect 'big results: four at once leave four lines' '4' "$(grep -c '^120000 ' "$cs_gate/rm45-remind-pend")"
usage_line 150000 > "$rm_tx"; printf '%s 0\n' "$(date +%s)" > "$cs_gate/rm43-remind-state"
expect 'small result inside the pause: no look' '' \
  "$(remind_event rm43 "$rm_tx" | TMPDIR="$cs_tmp" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 bash "$remind_cs" 2>&1)"
# the limit's sources, in their order
usage_line 90000 > "$rm_tx"
out="$(cs_remind rm2 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50 2>&1)"
check_contains 'limit: the window times the percentage override' 'SICHERN' "$(remind_ctx "$out")"
out="$(cs_remind rm3 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
expect 'limit: the window alone is no reason at 90,000 of 200,000' '' "$out"
out="$(cs_remind rm4 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000 2>&1)"
check_contains 'limit: a window of 100,000 reminds at 90,000' 'SICHERN' "$(remind_ctx "$out")"
{ printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":100000,"postTokens":9000}}\n'
  usage_line 90000; } > "$rm_tx"
out="$(cs_remind rm5 "$rm_tx" 2>&1)"
check_contains 'limit: without the variables the last compaction point (preTokens) counts' 'SICHERN' "$(remind_ctx "$out")"
out="$(cs_remind rm6 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 2>&1)"
expect 'limit: the variable comes before preTokens' '' "$out"
usage_line 90000 > "$rm_tx"
rm_root="$fix/remind-root"; mkdir -p "$rm_root/.claude"
printf '{"autoCompactWindow": "100000"}\n' > "$rm_root/.claude/settings.json"
out="$(CS_ROOT="$rm_root" cs_remind rm7 "$rm_tx" 2>&1)"
check_contains 'limit: the autoCompactWindow setting counts where nothing before it does' 'SICHERN' "$(remind_ctx "$out")"
# never a block, never an error
out="$(cs_remind rm8 "$fix/nope.jsonl" 2>&1)"; rc=$?
expect 'remind: a missing transcript is silent, rc 0' '0:' "$rc:$out"
printf 'not json at all\n' > "$rm_tx"
out="$(cs_remind rm8 "$rm_tx" 2>&1)"; rc=$?
expect 'remind: a transcript without usage is silent, rc 0' '0:' "$rc:$out"
out="$(printf '{"session_id":"../x"}' | TMPDIR="$cs_tmp" bash "$remind_cs" 2>&1)"; rc=$?
expect 'remind: a session id that is no name is silent, rc 0' '0:' "$rc:$out"
usage_line 190000 > "$rm_tx"
out="$(cs_remind rm9 "$rm_tx" a1 CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
expect 'remind: a sub-agent call is left alone' '' "$out"
# the limit's edges
usage_line 142800 > "$rm_tx"
out="$(cs_remind rm10 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
check_contains 'limit: exactly 85 percent of the point (142,800 of 168,000) reminds' 'SICHERN' "$(remind_ctx "$out")"
usage_line 142799 > "$rm_tx"
out="$(cs_remind rm11 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
expect 'limit: one token below 85 percent is silent' '' "$out"
usage_line 150000 > "$rm_tx"
out="$(cs_remind rm12 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95 2>&1)"
check_contains 'limit: a percentage above 84 cannot raise the point' 'SICHERN' "$(remind_ctx "$out")"
out="$(cs_remind rm13 "$rm_tx" 2>&1)"
expect 'limit: no source for the window, no guess' '' "$out"
out="$(cs_remind rm14 "$rm_tx" ANTHROPIC_MODEL='opus[1m]' 2>&1)"
expect 'limit: a [1m] model in the environment means a window of 1,000,000' '' "$out"
usage_line 720000 > "$rm_tx"
out="$(cs_remind rm15 "$rm_tx" ANTHROPIC_MODEL='opus[1m]' 2>&1)"
check_contains 'limit: 720,000 of a 1,000,000 window reminds' 'SICHERN' "$(remind_ctx "$out")"
usage_line 150000 > "$rm_tx"
mkdir -p "$fix/remind-root-m/.claude"
printf '{"model": "sonnet[1m]"}\n' > "$fix/remind-root-m/.claude/settings.json"
out="$(CS_ROOT="$fix/remind-root-m" cs_remind rm16 "$rm_tx" 2>&1)"
expect 'limit: a [1m] model in the settings means a window of 1,000,000' '' "$out"
printf '{"autoCompactWindow": 100000}\n' > "$fix/remind-root-m/.claude/settings.local.json"
out="$(CS_ROOT="$fix/remind-root-m" cs_remind rm17 "$rm_tx" 2>&1)"
check_contains 'limit: settings.local.json comes before settings.json' 'SICHERN' "$(remind_ctx "$out")"
{ printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual","preTokens":100000,"postTokens":9000}}\n'
  usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm18 "$rm_tx" 2>&1)"
expect 'limit: the preTokens of a manual compaction say nothing about the point' '' "$out"
{ printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":400000,"postTokens":9000}}\n'
  usage_line 150000; } > "$rm_tx"
out="$(CS_ROOT="$fix/remind-root-m" cs_remind rm19 "$rm_tx" 2>&1)"
expect 'limit: preTokens of an automatic compaction comes before the autoCompactWindow setting' '' "$out"
# the bare model id of the transcript (ww3d/playbook#439, question 460)
model_line() { printf '{"type":"assistant","message":{"model":"%s","role":"assistant"}}\n' "$1"; }
{ model_line claude-fable-5-1; usage_line 720000; } > "$rm_tx"
out="$(cs_remind rm21 "$rm_tx" 2>&1)"
check_contains 'model: a 1M-native id (Fable 5.1) is a window of 1,000,000' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-fable-5-1; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm22 "$rm_tx" 2>&1)"
expect 'model: 150,000 of a 1,000,000 window is silent' '' "$out"
{ model_line claude-opus-4-6; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm23 "$rm_tx" 2>&1)"
check_contains 'model: an older id (Opus 4.6) is a window of 200,000' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-opus-4-7; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm24 "$rm_tx" 2>&1)"
expect 'model: Opus 4.7 is 1M-native' '' "$out"
{ model_line claude-opus-4-7; usage_line 720000; } > "$rm_tx"
out="$(cs_remind rm24b "$rm_tx" 2>&1)"
check_contains 'model: Opus 4.7 is on the list, 720,000 of 1,000,000 reminds' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-sonnet-5-5-20261001; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm25 "$rm_tx" 2>&1)"
expect 'model: an id with a date suffix is read (Sonnet 5.5, 1M)' '' "$out"
{ model_line claude-sonnet-5-5-20261001; usage_line 720000; } > "$rm_tx"
out="$(cs_remind rm25b "$rm_tx" 2>&1)"
check_contains 'model: the dated Sonnet 5.5 id is on the list, 720,000 reminds' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-haiku-4-5-20251001; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm26 "$rm_tx" 2>&1)"
check_contains 'model: Haiku 4.5 with a date suffix is 200,000' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-unknown-9; usage_line 190000; } > "$rm_tx"
out="$(cs_remind rm27 "$rm_tx" 2>&1)"
expect 'model: an id not on the list is silent' '' "$out"
{ model_line claude-fable-5-1; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm28 "$rm_tx" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 2>&1)"
check_contains 'model: CLAUDE_CODE_DISABLE_1M_CONTEXT=1 holds a 1M-native id at 200,000' 'SICHERN' "$(remind_ctx "$out")"
out="$(cs_remind rm29 "$rm_tx" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 ANTHROPIC_MODEL='opus[1m]' 2>&1)"
check_contains 'model: the disable switch also holds a [1m] model at 200,000' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-opus-4-6; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm30 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 2>&1)"
expect 'model: the variable comes before the model id' '' "$out"
{ model_line claude-haiku-5-5; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm31 "$rm_tx" 2>&1)"
expect 'model: Haiku 5.5 is 1M-native' '' "$out"
{ model_line claude-haiku-5-5; usage_line 720000; } > "$rm_tx"
out="$(cs_remind rm31b "$rm_tx" 2>&1)"
check_contains 'model: Haiku 5.5, 720,000 of 1,000,000 reminds' 'SICHERN' "$(remind_ctx "$out")"
{ model_line claude-opus-4-20250514; usage_line 150000; } > "$rm_tx"
out="$(cs_remind rm32 "$rm_tx" 2>&1)"
check_contains 'model: Opus 4 with a date and no minor is 200,000' 'SICHERN' "$(remind_ctx "$out")"
# the 15-second look: one scan, then quiet until it has passed
usage_line 100000 > "$rm_tx"
out="$(CS_KEEP_STATE=1 cs_remind rm20 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
usage_line 150000 > "$rm_tx"
out="$(CS_KEEP_STATE=1 cs_remind rm20 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
expect 'remind: a second call within 15 seconds is not scanned' '' "$out"
printf '0 0\n' > "$cs_gate/rm20-remind-state"
out="$(CS_KEEP_STATE=1 cs_remind rm20 "$rm_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)"
check_contains 'remind: after the 15 seconds the next call reminds' 'SICHERN' "$(remind_ctx "$out")"
cs_save rm20 "$rm_tx" >/dev/null 2>&1
absent_file 'a compaction removes the look state with the run mark' "$cs_gate/rm20-remind-state"
# The former gate switch blocks nothing: every compaction passes with the summary instruction.
js "$fix/compact-state-part.jsonl"
out="$(printf '{"session_id":"gt1","transcript_path":%s,"hook_event_name":"PreCompact","trigger":"auto"}\n' "$REPLY" \
  | PLAYBOOK_COMPACT_GATE=on TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$save_cs" 2>&1)"; rc=$?
expect 'no gate: an auto compaction passes with the switch on' 0 "$rc"
check_contains 'no gate: the summary instruction comes' 'Anweisung fuer die Zusammenfassung' "$out"
absent_file 'no gate: no block mark' "$cs_gate/gt1-gate-blocked"

finish
