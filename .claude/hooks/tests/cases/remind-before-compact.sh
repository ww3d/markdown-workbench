#!/usr/bin/env bash
# Hook suite section: remind-before-compact.sh and the gate in save-compact-state.sh
# Run alone: bash .claude/hooks/tests/cases/remind-before-compact.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== remind-before-compact.sh / the gate in save-compact-state.sh: before the limit (ww3d/playbook#439) =="
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
# The cross-check before the compaction (ww3d/playbook#487): the reminder names the range from the mark to the
# line count now and the result file; the save turns the count into the mark "<n> pre" once the result was read.
pc_tx="$fix/remind-pre.jsonl"; for _ in 1 2 3; do usage_line 150000; done > "$pc_tx"
printf '1\n' > "$cs_gate/pc1-cross-check-mark"; : > "$cs_gate/pc1-cross-check-pre-2.md"; : > "$cs_gate/pc1-read-main-compact.crosscheck-pre-2"
ctx="$(remind_ctx "$(cs_remind pc1 "$pc_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)")"
check_not_contains 'pre: the hint names no range any more' 'Zeilen' "$ctx"
check_not_contains 'pre: the hint names no result file' 'cross-check-pre' "$ctx"
expect 'pre: the line count is kept' 3 "$(cat "$cs_gate/pc1-cross-check-pre" 2>/dev/null)"
absent_file 'pre: an earlier result goes' "$cs_gate/pc1-cross-check-pre-2.md"
absent_file 'pre: the read of an earlier result goes' "$cs_gate/pc1-read-main-compact.crosscheck-pre-2"
cs_save pc1 "$pc_tx" >/dev/null 2>&1
expect 'pre: an unread result leaves the mark as it was' 1 "$(cat "$cs_gate/pc1-cross-check-mark" 2>/dev/null)"
absent_file 'pre: the save uses the count once' "$cs_gate/pc1-cross-check-pre"
ctx="$(remind_ctx "$(cs_remind pc2 "$pc_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)")"
expect 'pre: without a mark the line count is kept' 3 "$(cat "$cs_gate/pc2-cross-check-pre" 2>/dev/null)"
: > "$cs_gate/pc2-cross-check-pre-3.md"; lk_read pc2 "$cs_gate/pc2-cross-check-pre-3.md"
present_file 'pre: the read of the result is recorded for its range' "$cs_gate/pc2-read-main-compact.crosscheck-pre-3"
absent_file 'pre: it is no read of the result after a compaction' "$cs_gate/pc2-read-main-compact.crosscheck"
cs_save pc2 "$pc_tx" >/dev/null 2>&1
expect 'pre: a read result sets the mark "<n> pre"' '3 pre' "$(cat "$cs_gate/pc2-cross-check-mark" 2>/dev/null)"
# A late result of an earlier, shorter range releases nothing: the range now runs to 6, the result read to 3.
printf '6\n' > "$cs_gate/pc6-cross-check-pre"; : > "$cs_gate/pc6-cross-check-pre-3.md"; lk_read pc6 "$cs_gate/pc6-cross-check-pre-3.md"
cs_save pc6 "$pc_tx" >/dev/null 2>&1
absent_file 'pre: a result of an earlier range sets no mark' "$cs_gate/pc6-cross-check-mark"
: > "$cs_gate/pc3-compact-lock"
ctx="$(remind_ctx "$(cs_remind pc3 "$pc_tx" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 2>&1)")"
absent_file 'pre: not while a lock of the last compaction stands' "$cs_gate/pc3-cross-check-pre"
check_contains 'pre: the plain reminder comes then' 'SICHERN' "$ctx"
check_not_contains 'pre counter: the plain reminder names no range' 'Zeilen 1-3' "$ctx"
rm -f "$cs_gate/pc3-compact-lock"
# After the compaction a mark "<n> pre" starts the range at <n> and reaches back over nothing; a plain mark of
# the same line reaches back over the last turn before the compaction.
pc_total="$(wc -l < "$fix/compact-state.jsonl" | tr -d ' ')"
printf '%s pre\n' "$((pc_total - 1))" > "$cs_gate/pc4-cross-check-mark"
ctx="$(cs_restore pc4 "$fix/compact-state.jsonl" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
check_line 'pre mark: the range starts at the mark' "from=$((pc_total - 1))" "$(cat "$cs_gate/pc4-compact-lock" 2>/dev/null)"
check_contains 'pre mark: the hint says the lines before were cross-checked' 'cross-checked before the compaction' "$ctx"
check_not_contains 'pre mark: no last turn to reach back over' 'Check the last turn before the compaction' "$ctx"
printf '%s\n' "$((pc_total - 1))" > "$cs_gate/pc5-cross-check-mark"
cs_restore pc5 "$fix/compact-state.jsonl" >/dev/null 2>&1
pc_from="$(sed -n 's/^from=//p' "$cs_gate/pc5-compact-lock" 2>/dev/null)"
expect 'contrast: a plain mark reaches back below the mark' 1 "$([[ $pc_from =~ ^[0-9]+$ ]] && [ "$pc_from" -lt "$((pc_total - 1))" ] && echo 1 || echo 0)"
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
# the gate: a block only behind its switch, once per run
cs_gate_save() { # session, trigger, [switch value]
  { js "$1"; printf '{"session_id":%s,"transcript_path":"","cwd":' "$REPLY"; js "$repo_root"; printf '%s,"hook_event_name":"PreCompact","trigger":' "$REPLY"
    js "$2"; printf '%s}\n' "$REPLY"; } \
    | env -u PLAYBOOK_COMPACT_GATE ${3:+PLAYBOOK_COMPACT_GATE="$3"} TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$save_cs"
}
out="$(cs_gate_save gt1 auto 2>&1)"; rc=$?
expect 'gate: off from the factory, an auto compaction passes' 0 "$rc"; check_contains 'gate: off from the factory, an auto compaction passes'' (the summary instruction)' 'Anweisung fuer die Zusammenfassung' "$out"
out="$(cs_gate_save gt2 auto on 2>&1)"; rc=$?
expect 'gate: on, the first auto compaction of a run is blocked (rc 2)' 2 "$rc"
check_contains 'gate: the block says why and that the next one passes' 'Gegenabgleich' "$out"
present_file 'gate: the block is marked for the reminder' "$cs_gate/gt2-gate-blocked"
present_file 'gate: the rule list is saved before the block, so a compaction that slips through finds it' "$cs_gate/gt2-compact-rules"
out="$(cs_remind gt2 "$fix/nope.jsonl" 2>&1)"
check_contains 'gate: the next tool call tells the model the block happened' 'abgefangen' "$(remind_ctx "$out")"
absent_file 'gate: the reminder consumes the block mark' "$cs_gate/gt2-gate-blocked"
out="$(cs_gate_save gt2 auto on 2>&1)"; rc=$?
expect 'gate: the next auto compaction goes through' 0 "$rc"; check_contains 'gate: the next auto compaction goes through'' (the summary instruction)' 'Anweisung fuer die Zusammenfassung' "$out"
present_file 'gate: the pass saves the rule list' "$cs_gate/gt2-compact-rules"
out="$(cs_gate_save gt2 auto on 2>&1)"; rc=$?
expect 'gate: the run after that is blocked again' 2 "$rc"
out="$(cs_gate_save gt3 manual on 2>&1)"; rc=$?
expect 'gate: a manual compaction is never blocked' 0 "$rc"; check_contains 'gate: a manual compaction is never blocked'' (the summary instruction)' 'Anweisung fuer die Zusammenfassung' "$out"
out="$(cs_gate_save gt4 auto off 2>&1)"; rc=$?
expect 'gate: any value but on leaves it off' 0 "$rc"; check_contains 'gate: any value but on leaves it off'' (the summary instruction)' 'Anweisung fuer die Zusammenfassung' "$out"
# the cross-check mark must outlive the weekly sweep while the session lives
cs_mark="$cs_gate/f2-cross-check-mark"; printf '3\n' > "$cs_mark"; touch -d '10 days ago' "$cs_mark"
cs_save f2 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore f2 "$fix/compact-state.jsonl" >/dev/null 2>&1
if [ -n "$(find "$cs_mark" -mtime -1 2>/dev/null)" ]; then ok 'restore renews the cross-check mark so the sweep keeps it' renewed; else bad 'restore renews the cross-check mark' old renewed; fi
expect 'restore keeps the mark value' 3 "$(cat "$cs_mark")"

finish
