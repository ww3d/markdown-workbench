#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, the lock after a compaction
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-compact-lock.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"
use_rc_root
use_csnojq

echo "== require-rule-read.sh: the lock after a compaction (ww3d/playbook#439) =="
for m in chat local-ci-silence local-naming; do : > "$cs_gate/lk1-read-main-$m"; done
cs_save lk1 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
out="$(cs_restore lk1 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
for m in compact.restore compact.crosscheck; do
  expect "lock: the restore names the need $m" 1 "$(lk_need lk1 "$m")"
done
for m in chat local-ci-silence local-naming; do
  expect "lock: the rule file $m read before is no need (read before the next action of its kind)" 0 "$(lk_need lk1 "$m")"
done
expect 'lock: a rule file with a trigger is no need' 0 "$(lk_need lk1 pr)"
check_line 'lock: the cross-check starts after the last mark' 'from=0' "$(cat "$cs_gate/lk1-compact-lock" 2>/dev/null)"
check_contains 'lock: the hint names the lock' 'require-rule-read.sh blocks' "$ctx"
check_contains 'lock: the hint says a rule file is read before the next action of its kind' 'before the next action of its kind' "$ctx"
check_contains 'lock: the restore file says the same' 'before the next action of its kind' "$(cat "$cs_gate/lk1-compact-restore.md" 2>/dev/null)"
check_contains 'lock: the hint names the helper where the older part grew' 'reference/cross-check.md' "$ctx"
expect 'lock: the hint stays under 2,000 characters' 1 "$([ "${#ctx}" -lt 2000 ] && echo 1 || echo 0)"
expect 'lock: a call of the main thread is denied' LOCK "$(lk_verdict lk1 Bash)"
expect 'lock: an Agent call naming cross-check.md passes, it starts the helper' PASS "$(LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' lk_verdict lk1 Agent)"
expect 'lock: a Task call naming cross-check.md passes' PASS "$(LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' lk_verdict lk1 Task)"
rm -f "$cs_gate/lk1-cross-check-started" # phase 1 again for the cases below: the helper has not run
expect 'lock: a sub-agent is free' PASS "$(lk_verdict lk1 Bash agent-x1)"
expect 'lock: the second denial in the turn' LOCK "$(lk_verdict lk1 Edit)"
expect 'lock: the third denial in the turn' LOCK "$(lk_verdict lk1 Write)"
expect 'valve: after the third denial the rest of the turn passes' PASS "$(lk_verdict lk1 Bash)"
present_file 'valve: the lock stays for the next turn' "$cs_gate/lk1-compact-lock"
printf '999999 3\n' > "$cs_gate/lk1-compact-lock-denies"
expect 'valve: a new turn locks again' LOCK "$(lk_verdict lk1 Bash)"
# Reads: the restore file in parts, the last part reaching its end.
restore_lk1="$cs_gate/lk1-compact-restore.md"; total="$(wc -l < "$restore_lk1" | tr -d ' ')"
lk_to="$(sed -n 's/^to=//p' "$cs_gate/lk1-compact-lock" 2>/dev/null)"
lk_read lk1 "$cs_gate/other-compact-restore.md"
absent_file "read: another session's restore file does not count" "$cs_gate/lk1-read-main-compact.restore"
# A sub-agent that reads the restore file reads it for itself: the main thread stays locked.
lk_read lk1 "$restore_lk1" "" "" agent-r1
present_file 'read: a sub-agent read is named for the sub-agent' "$cs_gate/lk1-read-agent-r1-compact.restore"
absent_file 'read: a sub-agent read is no main-thread read' "$cs_gate/lk1-read-main-compact.restore"
expect 'lock: a sub-agent read does not release the main thread' LOCK "$(lk_verdict lk1 Bash)"
lk_read lk1 "$restore_lk1" "1 2 $total"
absent_file 'read: a part short of the end does not count' "$cs_gate/lk1-read-main-compact.restore"
lk_read lk1 "$restore_lk1" "3 $((total - 2)) $total"
present_file 'read: the part reaching the end counts' "$cs_gate/lk1-read-main-compact.restore"
# The restore file read, the listed rule files still unread: only the cross-check result holds the lock.
: > "$cs_gate/lk1-compact-lock-denies"
expect 'lock: the cross-check result still missing locks' LOCK "$(lk_verdict lk1 Bash)"
: > "$cs_gate/lk1-cross-check.md"; lk_read lk1 "$cs_gate/lk1-cross-check.md" "1 1 1"
expect 'lock: restore file and result read release, with the listed rule files unread' PASS "$(lk_verdict lk1 Bash)"
absent_file 'release: the lock file goes' "$cs_gate/lk1-compact-lock"
expect 'release: the mark is the end of the checked part' "${lk_to:-none}" "$(cat "$cs_gate/lk1-cross-check-mark" 2>/dev/null)"
expect 'release: the checked part is not empty' 1 "$([[ $lk_to =~ ^[1-9][0-9]*$ ]] && echo 1 || echo 0)"
# The next compaction of the same session: the older part did not grow, so no cross-check. What the
# earlier lock left - its result, a denial count, a gapless-read state - goes with the new restore.
rm -f "$cs_gate"/lk1-read-main-*
printf '5 2\n' > "$cs_gate/lk1-compact-lock-denies"; printf '1 3\n' > "$cs_gate/lk1-read-main-compact.restore.upto"
printf '1 3\n' > "$cs_gate/lk1-read-main-compact.crosscheck.upto"; printf '1 3\n' > "$cs_gate/lk1-read-agent-r1-compact.restore.upto"
out="$(cs_restore lk1 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" 2>&1)"
absent_file 'new restore: the stale cross-check result goes' "$cs_gate/lk1-cross-check.md"
absent_file 'new restore: the denial count goes' "$cs_gate/lk1-compact-lock-denies"
absent_file 'new restore: the gapless-read state goes' "$cs_gate/lk1-read-main-compact.restore.upto"
absent_file 'new restore: the cross-check read state goes' "$cs_gate/lk1-read-main-compact.crosscheck.upto"
absent_file 'new restore: a sub-agent read state goes' "$cs_gate/lk1-read-agent-r1-compact.restore.upto"
expect 'not grown: no cross-check need' 0 "$(lk_need lk1 compact.crosscheck)"
check_not_contains 'not grown: the hint names no helper' 'cross-check.md' \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
expect 'not grown: the restore file still locks' LOCK "$(lk_verdict lk1 Bash)"
# Valve: a need whose file is gone passes; the cross-check result is the one exception.
printf 'to=1\nneed=compact.restore %s\n' "$cs_gate/no-such-chat.md" > "$cs_gate/lk2-compact-lock"
expect 'valve: a missing file passes' PASS "$(lk_verdict lk2 Bash)"
printf 'to=1\nneed=compact.crosscheck %s\n' "$cs_gate/lk3-cross-check.md" > "$cs_gate/lk3-compact-lock"
expect 'lock: a missing cross-check result does not pass' LOCK "$(lk_verdict lk3 Bash)"
expect 'lock: with only the result missing the helper Agent call passes' PASS "$(LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' lk_verdict lk3 Agent)"
# Only the cross-check helper starts under the lock (ww3d/playbook#487): another Agent or Task call is held
# in phase 1; in phase 2 it passes like every call that is no send command.
for s in lk19 lk20; do printf 'to=1\nneed=compact.crosscheck %s\n' "$cs_gate/$s-cross-check.md" > "$cs_gate/$s-compact-lock"; done
expect 'lock: an Agent call without cross-check.md is held in phase 1' LOCK "$(LK_INPUT='{"prompt":"recherchiere"}' lk_verdict lk19 Agent)"
expect 'lock: a Task call without cross-check.md is held in phase 1' LOCK "$(LK_INPUT='{"prompt":"recherchiere"}' lk_verdict lk19 Task)"
absent_file 'lock: a held Agent call writes no started marker' "$cs_gate/lk19-cross-check-started"
: > "$cs_gate/lk20-cross-check-started"
expect 'lock: in phase 2 another Agent call passes' PASS "$(LK_INPUT='{"prompt":"recherchiere"}' lk_verdict lk20 Agent)"
# Valve: a hook error passes - here the denial count cannot be written.
printf 'need=compact.restore %s\n' "$cs_proj/.agents/rules/chat.md" > "$cs_gate/lk4-compact-lock"; mkdir -p "$cs_gate/lk4-compact-lock-denies"
expect 'valve: a hook error passes' PASS "$(lk_verdict lk4 Bash)"
# Without jq the restore file still stands and locks; the older part is unknown, so no cross-check.
cs_restore lk5 "$fix/compact-state.jsonl" "$csnojq" "$cs_proj" >/dev/null 2>&1
expect 'without jq: the restore file is a need' 1 "$(lk_need lk5 compact.restore)"
expect 'without jq: no cross-check need' 0 "$(lk_need lk5 compact.crosscheck)"
# Every compaction with a growing transcript needs the cross-check now (ww3d/playbook#487,
# REQ-001): the first compaction too, since `to > from` holds whenever the mark is 0 and the
# transcript carries lines.
cs_restore lk6 "$fix/compact-state-tasks.jsonl" >/dev/null 2>&1
expect 'first compaction: cross-check need (ww3d/playbook#487)' 1 "$(lk_need lk6 compact.crosscheck)"
# The fixture for the helper's probe: a maintainer answer only as a message, in the older part.
cs_restore lk7 "$fix/compact-state-answer.jsonl" >/dev/null 2>&1
expect 'answer fixture: the older part needs the cross-check' 1 "$(lk_need lk7 compact.crosscheck)"
check_not_contains 'answer fixture: the answer is not in the restore file' 'Seidenreiher' \
  "$(cat "$cs_gate/lk7-compact-restore.md" 2>/dev/null)"
check_not_contains 'answer fixture: the commitment is not in the restore file' 'Ich baue Variante b' \
  "$(cat "$cs_gate/lk7-compact-restore.md" 2>/dev/null)"

# The turn count, differential: a tool result, a meta line and a compaction summary start no turn,
# a user line does. The key is the turn start's line number.
lk_user='{"type":"user","message":{"role":"user","content":"Weiter mit der Sperre."}}'
lk_result='{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"ok"}]}}'
lk_meta='{"type":"user","isMeta":true,"message":{"role":"user","content":"<meta>"}}'
lk_summary='{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Zusammenfassung."}}'
lk_asst='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Arbeit."}]}}'
lk_lock() { # session, transcript - a lock with one unread restore file
  printf 'to=0\ntranscript=%s\nneed=compact.restore %s\n' "$2" "$cs_proj/.agents/rules/chat.md" > "$cs_gate/$1-compact-lock"
}
lk_t="$fix/lk8-transcript.jsonl"; printf '%s\n' "$lk_asst" "$lk_user" > "$lk_t"; lk_lock lk8 "$lk_t"
expect 'turn: the first denial' LOCK "$(lk_verdict lk8 Bash)"
expect 'turn: without a uuid the key is the line of the turn start' 'line2 1' "$(lk_denies lk8)"
printf '%s\n' "$lk_result" >> "$lk_t"
expect 'turn: a tool result starts no turn' LOCK "$(lk_verdict lk8 Bash)"
expect 'turn: the count goes on after a tool result' 'line2 2' "$(lk_denies lk8)"
printf '%s\n' "$lk_meta" "$lk_summary" >> "$lk_t"
expect 'turn: a meta line and a summary start no turn' LOCK "$(lk_verdict lk8 Bash)"
expect 'turn: the count goes on after them' 'line2 3' "$(lk_denies lk8)"
expect 'turn: after the third denial the rest of the turn passes' PASS "$(lk_verdict lk8 Bash)"
expect 'turn: and the call after it too' PASS "$(lk_verdict lk8 Edit)"
printf '%s\n' "$lk_user" >> "$lk_t"
expect 'turn: a user line starts a new turn and locks' LOCK "$(lk_verdict lk8 Bash)"
expect 'turn: the new key, the count from 1' 'line6 1' "$(lk_denies lk8)"
# Longer than the 400 lines the gate looks at first: the turn start's uuid, the same from the tail and
# from the full pass.
lk_user_id() { printf '{"type":"user","message":{"role":"user","content":"Weiter."},"uuid":"%s"}' "$1"; }
lk_t="$fix/lk9-transcript.jsonl"
{ for ((i = 0; i < 500; i++)); do printf '%s\n' "$lk_asst"; done
  lk_user_id u-501; printf '\n'; for ((i = 0; i < 5; i++)); do printf '%s\n' "$lk_result"; done; } > "$lk_t"
lk_lock lk9 "$lk_t"
expect 'long turn: the key from the last 400 lines' LOCK "$(lk_verdict lk9 Bash)"
expect 'long turn: it is the uuid of the turn start' 'u-501 1' "$(lk_denies lk9)"
for ((i = 0; i < 400; i++)); do printf '%s\n' "$lk_result"; done >> "$lk_t"
expect 'long turn: no turn start in the last 400 lines' LOCK "$(lk_verdict lk9 Bash)"
expect 'long turn: the full pass gives the same key' 'u-501 2' "$(lk_denies lk9)"
expect 'long turn: the third denial' LOCK "$(lk_verdict lk9 Bash)"
expect 'long turn: then the turn passes' PASS "$(lk_verdict lk9 Bash)"
lk_user_id u-907 >> "$lk_t" # the newest line without its newline yet
expect 'long turn: a new user line locks again' LOCK "$(lk_verdict lk9 Bash)"
expect 'long turn: its key, the line without a newline read too' 'u-907 1' "$(lk_denies lk9)"

# The restore file read whole, and in parts: the parts count once they close up from line 1 to the
# end, in whatever order their hooks ran (parallel reads of one answer).
lk_f="$cs_gate/lk10-compact-restore.md"; for ((i = 1; i <= 10; i++)); do printf 'Zeile %s\n' "$i"; done > "$lk_f"
lk_m="$cs_gate/lk10-read-main-compact.restore"
lk_read lk10 "$lk_f"
present_file 'read: the restore file read whole counts' "$lk_m"
rm -f "$lk_m" "$lk_m.upto"
lk_read lk10 "$lk_f" "1 10"
absent_file 'read: a part without totalLines does not count' "$lk_m"
lk_read lk10 "$lk_f" "10 1 10"
absent_file 'read: a lone read of the last line does not count' "$lk_m"
lk_read lk10 "$lk_f" "5 3 10"
absent_file 'read: parts with a gap before them do not count' "$lk_m"
lk_read lk10 "$lk_f" "1 4 10"
absent_file 'read: closing up to line 7 is not the end yet' "$lk_m"
lk_read lk10 "$lk_f" "8 2 10"
present_file 'read: parts out of order without a gap up to the end count' "$lk_m"
# A read without offset/limit that returns only the first 2,000 lines is not whole; an empty file is.
lk_read lk16 "$cs_gate/lk16-compact-restore.md" "1 2000 3000"
absent_file 'read: the first 2,000 of 3,000 lines do not count' "$cs_gate/lk16-read-main-compact.restore"
lk_read lk17 "$cs_gate/lk17-compact-restore.md" "1 0 0"
present_file 'read: an empty restore file read counts' "$cs_gate/lk17-read-main-compact.restore"

# The denial: valid JSON, the missing path (one with backslashes and a quote where the system has them)
# and the helper line; Read and a non-GitHub MCP tool never reach the gate, a GitHub MCP tool does.
lk_dir="$cs_gate/lk11 dir"; mkdir -p "$lk_dir"
if command -v cygpath >/dev/null 2>&1; then : > "$lk_dir/chat.md"; lk_f="$(cygpath -w "$lk_dir/chat.md")"
else lk_f="$lk_dir/back\\slash \"q\".md"; : > "$lk_f"; fi
printf 'from=3\nto=7\ntranscript=/t/lk11.jsonl\nneed=compact.restore %s\nneed=compact.crosscheck %s\n' "$lk_f" "$cs_gate/lk11-cross-check.md" > "$cs_gate/lk11-compact-lock"
out="$(lk_out lk11 Bash)"
expect 'denial: valid JSON with a deny' true \
  "$(printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null || echo false)"
reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)"
check_line 'denial: names the missing file' "- $lk_f" "$reason"
check_contains 'denial: names the helper' 'first start the helper' "$reason"
check_contains 'denial: a lock without lines= counts from after from=' 'on transcript /t/lk11.jsonl, lines 4-7' "$reason"
check_contains 'denial: names the cross-check result' "$cs_gate/lk11-cross-check.md" "$reason"
expect 'lock: a GitHub MCP call is denied' LOCK "$(lk_verdict lk11 mcp__github__get_me)"
expect 'lock: a Read never reaches the gate' PASS "$(lk_verdict lk11 Read)"
expect 'lock: a non-GitHub MCP call never reaches it' PASS "$(lk_verdict lk11 mcp__slack__post)"

# The mark: a release without a cross-check need leaves it; a second compaction starts after it.
printf '7\n' > "$cs_gate/lk12-cross-check-mark"; : > "$cs_gate/lk12-read-main-compact.restore"
printf 'to=99\nneed=compact.restore %s\n' "$cs_proj/.agents/rules/chat.md" > "$cs_gate/lk12-compact-lock"
expect 'mark: a release without a cross-check' PASS "$(lk_verdict lk12 Bash)"
expect 'mark: stays as it was' 7 "$(cat "$cs_gate/lk12-cross-check-mark" 2>/dev/null)"
cs_save lk13 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
printf '1\n' > "$cs_gate/lk13-cross-check-mark"
out="$(cs_restore lk13 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" 2>&1)"
check_line 'mark: the next cross-check starts after it' 'from=1' "$(cat "$cs_gate/lk13-compact-lock" 2>/dev/null)"
check_contains 'mark: the hint names the lines after it' "lines 2-${lk_to:-none} of" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
# A broken count under this turn's own key: the count starts again at 1.
lk_lock lk14 "$fix/compact-state.jsonl"; lk_verdict lk14 Bash >/dev/null
read -r lk_k _ < "$cs_gate/lk14-compact-lock-denies"; printf '%s y\n' "$lk_k" > "$cs_gate/lk14-compact-lock-denies"
# A lock whose `to` is no number releases, but sets no mark.
printf 'to=abc\nneed=compact.crosscheck %s\n' "$cs_gate/lk18-cross-check.md" > "$cs_gate/lk18-compact-lock"
: > "$cs_gate/lk18-read-main-compact.crosscheck"
expect 'mark: a broken to releases' PASS "$(lk_verdict lk18 Bash)"
absent_file 'mark: a broken to sets no mark' "$cs_gate/lk18-cross-check-mark"
expect 'valve: a broken denial count locks from 1' LOCK "$(lk_verdict lk14 Bash)"
expect 'valve: the broken count is written anew' "$lk_k 1" "$(lk_denies lk14)"

# Long paths, as on Windows: four of them (restore file, transcript, the result twice) push the hint
# without its loss check to about 1,950 characters; only the cut loss check keeps it under 2,000,
# and the helper's line stays.
lk_long="$fix/long"; while [ ${#lk_long} -lt 270 ]; do lk_long="$lk_long/abcdefghij"; done
mkdir -p "$lk_long/claude-rule-gate"; cp "$fix/compact-state.jsonl" "$lk_long/transcript.jsonl"
js "$fix/compact-state-part.jsonl"; printf '{"session_id":"lk15","transcript_path":%s,"hook_event_name":"PreCompact","trigger":"auto"}\n' "$REPLY" \
  | TMPDIR="$lk_long" CLAUDE_PROJECT_DIR="$repo_root" bash "$save_cs" >/dev/null 2>&1
js "$lk_long/transcript.jsonl"
out="$(printf '{"session_id":"lk15","transcript_path":%s,"hook_event_name":"SessionStart","source":"compact"}\n' "$REPLY" \
  | TMPDIR="$lk_long" CLAUDE_PROJECT_DIR="$cs_proj" "$BASH" "$restore_cs" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
expect 'long paths: the hint stays under 2,000 characters' 1 "$([ "${#ctx}" -gt 0 ] && [ "${#ctx}" -lt 2000 ] && echo 1 || echo 0)"
check_contains 'long paths: the helper line stays' 'reference/cross-check.md' "$ctx"

# The weekly sweep of read-confirm.sh takes the compaction files too.
cs_sweep="$fix/cs-tmp-sweep/claude-rule-gate"; mkdir -p "$cs_sweep"
for f in old-compact-rules old-compact-restore.md; do : > "$cs_sweep/$f"; touch -d '10 days ago' "$cs_sweep/$f"; done
version_ctx "$fix/no-such-remote" 1.0.0 startup "$fix/cs-tmp-sweep" >/dev/null
absent_file 'sweep: a week-old save goes' "$cs_sweep/old-compact-rules"
absent_file 'sweep: a week-old restore file goes' "$cs_sweep/old-compact-restore.md"

finish
