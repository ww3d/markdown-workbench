#!/usr/bin/env bash
# Hook suite section: restore-compact-state.sh, the cross-check of the replay
# Run alone: bash .claude/hooks/tests/cases/compact-state-cross-check.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== restore-compact-state.sh / require-rule-read.sh / require-receipt.sh: the cross-check covers the whole replay, the lock has two phases, the turn end holds in phase 1 (ww3d/playbook#487) =="
# REQ-001, 002, 004: to = transcript line count at restore time; the hint names the new range and
# says the newest part since the previous compaction is included; the restore file carries the
# "Results of sub-agents (newest first)" section built from tool_result of main-thread Agent/Task
# tool_use calls and from task-notification user lines. No cs_save: the save belongs to another
# transcript here (its save file would pin $stop to the saved line count and swallow the newest
# part); without it the hook falls back to the last compact_boundary of the restore transcript.
rm -f "$cs_gate/cc1-compact-rules" 2>/dev/null || true
out="$(cs_restore cc1 "$fix/compact-state-helper-results.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
cc_body="$(cat "$cs_gate/cc1-compact-restore.md" 2>/dev/null)"
cc_total="$(wc -l < "$fix/compact-state-helper-results.jsonl" | tr -d ' ')"
cc_to="$(sed -n 's/^to=//p' "$cs_gate/cc1-compact-lock" 2>/dev/null)"
expect 'REQ-001: to is the transcript line count at restore time' "$cc_total" "$cc_to"
check_line 'REQ-001: the cross-check starts after the last mark (0 here)' 'from=0' "$(cat "$cs_gate/cc1-compact-lock" 2>/dev/null)"
check_contains 'REQ-002: the hint names the new range (mark+1-end)' "lines 1-${cc_total} of" "$ctx"
check_contains 'REQ-002: the hint says the newest part is checked too' 'newest part since the previous compaction' "$ctx"
check_contains 'REQ-004: the section Results of sub-agents is there' 'Results of sub-agents (newest first)' "$cc_body"
check_contains 'REQ-004: a tool_result of an Agent call lands as a helper result' 'Konkurrent WaselX exportiert in Nerzfell.v2' "$cc_body"
check_contains 'REQ-004: a task-notification lands as a helper result' 'Export-Spalte XVZ fehlt im Datensatz 42' "$cc_body"
check_contains 'REQ-004: the Agent description names the helper' 'competitor-check' "$cc_body"
# A fixture without helpers writes _none_ under the section (gegeprobe to REQ-004).
# compact-state.jsonl carries one task-notification; the counter drops it.
rm -f "$cs_gate/cc2-compact-rules" 2>/dev/null || true
grep -v 'task-notification' "$fix/compact-state.jsonl" > "$fix/compact-state-no-helpers.jsonl"
cs_restore cc2 "$fix/compact-state-no-helpers.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
cc2_body="$(cat "$cs_gate/cc2-compact-restore.md" 2>/dev/null)"
# One block, heading and _none_ together: check_contains matches a needle of several lines line by line.
blk=$'## Results of sub-agents (newest first)\n\n_none_'
if [[ ${cc2_body//$'\r'/} == *"$blk"* ]]; then got=block; else got=missing; fi
expect 'REQ-004 counter: without helpers the section says _none_' block "$got"
# REQ-001 counter: when the mark already matches the end, no cross-check need.
rm -f "$cs_gate/cc3-compact-rules" 2>/dev/null || true
printf '%s\n' "$cc_total" > "$cs_gate/cc3-cross-check-mark"
cs_restore cc3 "$fix/compact-state-helper-results.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
expect 'REQ-001 counter: to == from makes no cross-check need' 0 "$(lk_need cc3 compact.crosscheck)"

# REQ-042: without a compaction summary in the transcript the loss line names the helper, with one
# the old loss check runs. The hint carries the new line too (gegeprobe: a fixture with a summary
# never names the helper there).
rm -f "$cs_gate/cc_no_summary-compact-rules" 2>/dev/null || true
out="$(cs_restore cc_no_summary "$fix/compact-state-no-summary.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
cc_ns_body="$(cat "$cs_gate/cc_no_summary-compact-restore.md" 2>/dev/null)"
check_contains 'REQ-042: the loss line names the helper when the summary is missing' 'the cross-check helper does the loss check' "$cc_ns_body"
check_contains 'REQ-042: the hint carries the new loss line too' 'the cross-check helper does the loss check' "$ctx"
# Gegenprobe: a fixture with a summary never says the helper does the loss check.
rm -f "$cs_gate/cc_with_summary-compact-rules" 2>/dev/null || true
cs_restore cc_with_summary "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
cc_ws_body="$(cat "$cs_gate/cc_with_summary-compact-restore.md" 2>/dev/null)"
check_not_contains 'REQ-042 counter: with a summary the loss line does not mention the helper' 'the cross-check helper does the loss check' "$cc_ws_body"

echo "== restore-compact-state.sh / require-rule-read.sh: no gap after left-out entries, the open own sentence, one range (ww3d/playbook#487 follow-up) =="
# Entries the restore file leaves out to stay bounded: the range reaches back to the part's start even
# where the mark lies later, and the hint names the left-out lines.
gp_total="$(wc -l < "$fix/compact-state-many.jsonl" | tr -d ' ')"
printf '100\n' > "$cs_gate/gp1-cross-check-mark"
out="$(cs_restore gp1 "$fix/compact-state-many.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
gp_lock="$(cat "$cs_gate/gp1-compact-lock" 2>/dev/null)"
check_line 'left out: the range starts at the part, before the mark' 'from=0' "$gp_lock"
check_line 'left out: the lock names the range 1-based' "lines=1-$gp_total" "$gp_lock"
check_contains 'left out: the hint names the left-out lines' 'left out older entries of lines 1-' "$ctx"
check_contains 'left out: the hint names the range' "lines 1-$gp_total of" "$ctx"
expect 'left out: the hint stays under 2,000 characters' 1 "$([ "${#ctx}" -gt 0 ] && [ "${#ctx}" -lt 2000 ] && echo 1 || echo 0)"
# Counter: nothing left out, nothing named.
rm -f "$cs_gate/gp2-compact-rules" 2>/dev/null || true
out="$(cs_restore gp2 "$fix/compact-state-helper-results.jsonl" "$PATH" "$cs_proj" 2>&1)"
check_not_contains 'left out counter: a file with every entry names no left-out lines' 'left out older entries of lines' \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"

# The last turn before the compaction: always in the range and named in the hint, even past the mark.
gp_total="$(wc -l < "$fix/compact-state-open-step.jsonl" | tr -d ' ')"
gp_all="$(<"$fix/compact-state-open-step.jsonl")"
gp_turn=""
if [[ $gp_all == *'Wie viele Labels'* ]]; then gp_pre="${gp_all%%'Wie viele Labels'*}"; gp_pre="${gp_pre//[!$'\n']/}"; gp_turn=$(( ${#gp_pre} + 1 )); fi
printf '%s\n' "$((gp_total - 1))" > "$cs_gate/gp3-cross-check-mark"
out="$(cs_restore gp3 "$fix/compact-state-open-step.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
gp_lock="$(cat "$cs_gate/gp3-compact-lock" 2>/dev/null)"
check_line 'last turn: the range reaches back to its first line' "from=$((gp_turn - 1))" "$gp_lock"
check_contains 'last turn: the hint names its lines' "Check the last turn before the compaction (lines $gp_turn-" "$ctx"
# Counter: a mark at the end makes no cross-check, so no last-turn line either.
printf '%s\n' "$gp_total" > "$cs_gate/gp4-cross-check-mark"
out="$(cs_restore gp4 "$fix/compact-state-open-step.jsonl" "$PATH" "$cs_proj" 2>&1)"
check_not_contains 'last turn counter: no cross-check due, no last-turn line' 'Check the last turn' \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"

# The open own sentence fills Step and Todos where no skill call and no todo stand.
gp_body="$(cat "$cs_gate/gp3-compact-restore.md" 2>/dev/null)"
gp_step="$(printf '%s\n' "$gp_body" | sed -n '/^## Step$/,/^## Todos$/p')"
check_contains 'open step: the promise of the last answer is the step' \
  'Open own sentence of the last answer (no later tool result proves it done): Ich zaehle jetzt die Labels' "$gp_step"
check_not_contains 'open step: no "none found" beside it' 'none found' "$gp_step"
check_contains 'open step: the todos carry it as open' '- [open] Ich zaehle jetzt die Labels' \
  "$(printf '%s\n' "$gp_body" | sed -n '/^## Todos$/,/^## Rule/p')"
# Counter: a later tool result with its key words proves it, and a sentence in the perfect promises nothing.
rm -f "$cs_gate/gp5-compact-rules" 2>/dev/null || true
cs_restore gp5 "$fix/compact-state-open-step-proven.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
gp_body="$(cat "$cs_gate/gp5-compact-restore.md" 2>/dev/null)"
check_line 'open step counter: a proven promise leaves the step at none found' 'none found' \
  "$(printf '%s\n' "$gp_body" | sed -n '/^## Step$/,/^## Todos$/p')"
blk=$'## Todos\n\n_none_'
if [[ ${gp_body//$'\r'/} == *"$blk"* ]]; then got=block; else got=missing; fi
expect 'open step counter: the todos stay empty' block "$got"
# Counter: a skill call stays the step; the open sentence stands beside it.
rm -f "$cs_gate/gp6-compact-rules" 2>/dev/null || true
cs_restore gp6 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
check_line 'open step counter: a skill call stays the step' 'skill dev-task org/repo#1' \
  "$(sed -n '/^## Step$/,/^## Todos$/p' "$cs_gate/gp6-compact-restore.md" 2>/dev/null)"

# One range: the hint, the lock and the lock's denial name the same lines.
rm -f "$cs_gate/gp7-compact-rules" 2>/dev/null || true
printf '1\n' > "$cs_gate/gp7-cross-check-mark"
out="$(cs_restore gp7 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
gp_lines="$(sed -n 's/^lines=//p' "$cs_gate/gp7-compact-lock" 2>/dev/null)"
check_contains 'one range: the hint names the lock'"'"'s lines' "lines ${gp_lines:-none} of" "$ctx"
reason="$(lk_out gp7 Bash | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)"
check_contains 'one range: the denial names the same lines' "lines ${gp_lines:-none}," "$reason"
printf 'from=3\nto=7\nlines=2-7\ntranscript=/t/gp8.jsonl\nneed=compact.crosscheck %s\n' "$cs_gate/gp8-cross-check.md" > "$cs_gate/gp8-compact-lock"
check_contains 'one range: the denial takes lines= as written, not from+1' 'on transcript /t/gp8.jsonl, lines 2-7,' \
  "$(lk_out gp8 Bash | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)"
expect 'one range: the lock'"'"'s lines start after from' "$(( $(sed -n 's/^from=//p' "$cs_gate/gp7-compact-lock") + 1 ))" "${gp_lines%%-*}"

# cross-check.md names the two checks the helper owes in any case.
gp_ref="$(cat "$repo_root/.claude/skills/chat-handoff/reference/cross-check.md")"
check_contains 'cross-check.md: a done claim is read at its carrier, the carrier alone is not enough' \
  'dass der Traeger existiert, reicht nicht' "$gp_ref"
check_contains 'cross-check.md: the last turn before the compaction is checked for promises in any case' \
  'letzten Zugs vor der Verdichtung' "$gp_ref"
check_contains 'cross-check.md: the range reaches back over left-out entries' 'aus Platzgruenden weglaesst' "$gp_ref"

# The sender of a peer message without "from": a pinboard notice, the delivery id, the first word.
PLAYBOOK_NOTICE_SENDER_RE='pinboard=Meldungen vom Pinboard|Fragen-Seite' cs_restore gp9 "$fix/compact-state-senders.jsonl" >/dev/null 2>&1
gp_body="$(sed -n '/^## Messages of other sessions/,/^## The maintainer/p' "$cs_gate/gp9-compact-restore.md" 2>/dev/null)"
check_line 'sender: a notice matching PLAYBOOK_NOTICE_SENDER_RE at the text start takes its name' '### pinboard' "$gp_body"
check_line 'sender: without from, the delivery id' '### msg_01AbC9' "$gp_body"
check_line 'sender: without from or id, the first word' '### Seeadler' "$gp_body"
check_not_contains 'sender: never unknown' '### unknown' "$gp_body"
check_contains 'sender counter: a from in the delivery line wins over pinboard in the text' '### ctrl-test-8' "$gp_body"
cs_restore gp9b "$fix/compact-state-senders.jsonl" >/dev/null 2>&1
gp_body="$(sed -n '/^## Messages of other sessions/,/^## The maintainer/p' "$cs_gate/gp9b-compact-restore.md" 2>/dev/null)"
check_line 'sender counter: without the variable no notice name, the first word' '### Meldungen' "$gp_body"
check_not_contains 'sender counter: the hook names no org tool by itself' '### pinboard' "$gp_body"
PLAYBOOK_NOTICE_SENDER_RE='pinboard=Pinboard' cs_restore gp9c "$fix/compact-state-senders.jsonl" >/dev/null 2>&1
check_not_contains 'sender counter: the pattern counts at the text start only' '### pinboard' \
  "$(sed -n '/^## Messages of other sessions/,/^## The maintainer/p' "$cs_gate/gp9c-compact-restore.md" 2>/dev/null)"
PLAYBOOK_NOTICE_SENDER_RE='pinboard=(' cs_restore gp9d "$fix/compact-state-senders.jsonl" >/dev/null 2>&1
check_line 'sender counter: a broken pattern breaks nothing' '### msg_01AbC9' \
  "$(sed -n '/^## Messages of other sessions/,/^## The maintainer/p' "$cs_gate/gp9d-compact-restore.md" 2>/dev/null)"

# Rule files to reread: only files that are there, where the project root is known.
printf 'lines=0\n.agents/rules/nosuch-rule.md\n.agents/rules/pr.md\n' > "$cs_gate/gp10-compact-rules"
cs_restore gp10 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
gp_rules="$(sed -n '/^## Rule files to reread/,/^## /p' "$cs_gate/gp10-compact-restore.md" 2>/dev/null)"
check_not_contains 'rule list: a path that names no file is left out' 'nosuch-rule' "$gp_rules"
check_line 'rule list counter: a file that is there stays' '- .agents/rules/pr.md' "$gp_rules"
printf 'lines=0\n.agents/rules/nosuch-rule.md\n' > "$cs_gate/gp11-compact-rules"
cs_restore gp11 "$fix/compact-state.jsonl" >/dev/null 2>&1
check_contains 'rule list counter: without a project root nothing is dropped' 'nosuch-rule' \
  "$(cat "$cs_gate/gp11-compact-restore.md" 2>/dev/null)"

# The total cap: above 80,000 characters the restore file keeps whole lines up to it and names the rest file.
out="$(cs_restore gp12 "$fix/compact-state-big.jsonl" "$PATH" "$cs_proj" 2>&1)"
gp_size="$(wc -c < "$cs_gate/gp12-compact-restore.md" 2>/dev/null | tr -d ' ')"
expect 'cap: the restore file stays near 80,000 characters' 1 "$([ "${gp_size:-0}" -gt 70000 ] && [ "${gp_size:-0}" -le 80300 ] && echo 1 || echo 0)"
present_file 'cap: the rest goes to a file of its own' "$cs_gate/gp12-compact-restore-rest.md"
# The hook names the rest file in the form the Read tool takes: Windows form where cygpath makes one.
gp_rest="$cs_gate/gp12-compact-restore-rest.md"
if command -v cygpath >/dev/null 2>&1; then gp_rest="$(cygpath -w "$gp_rest")"; fi
check_contains 'cap: the restore file names the rest file' "the rest stands in $gp_rest" \
  "$(tail -n 2 "$cs_gate/gp12-compact-restore.md" 2>/dev/null)"
check_contains 'cap: the hint names the cut and the rest file' "It is cut at 80000 characters: the end of its long sections stands in $gp_rest" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
gp_body="$(cat "$cs_gate/gp12-compact-restore.md" 2>/dev/null)"
for h in '## Step' '## Todos' '## Rule files to reread' '## Loss check' '## Start order'; do
  if has_line "$h" "$gp_body"; then ok "cap: the short section $h stays in the restore file" found
  else bad "cap: the short section $h stays in the restore file" "no line: $h" found; fi
done
check_not_contains 'cap: the rest file holds only the end of the long sections' '## Step' \
  "$(cat "$cs_gate/gp12-compact-restore-rest.md" 2>/dev/null)"
cs_restore gp13 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
absent_file 'cap counter: a small file writes no rest file' "$cs_gate/gp13-compact-restore-rest.md"

# The late loss check: the restore found no summary; the first call of the lock after it arrives appends the result.
gp_t="$cs_tmp/gp14.jsonl"; cp "$fix/compact-state-no-summary.jsonl" "$gp_t"
js "$gp_t"; printf '{"session_id":"gp14","transcript_path":%s,"hook_event_name":"SessionStart","source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" "$BASH" "$restore_cs" >/dev/null 2>&1
check_line 'late loss: the lock waits for the summary' 'loss=pending' "$(cat "$cs_gate/gp14-compact-lock" 2>/dev/null)"
lk_out gp14 Bash >/dev/null
check_line 'late loss counter: no summary yet, still pending' 'loss=pending' "$(cat "$cs_gate/gp14-compact-lock" 2>/dev/null)"
check_not_contains 'late loss counter: nothing appended without the summary' 'after the summary arrived' \
  "$(cat "$cs_gate/gp14-compact-restore.md" 2>/dev/null)"
printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary: nur der Start."}}' >> "$gp_t"
: > "$cs_gate/gp14-read-main-compact.restore"
lk_out gp14 Bash >/dev/null
gp_body="$(cat "$cs_gate/gp14-compact-restore.md" 2>/dev/null)"
check_contains 'late loss: the result goes to the restore file' '## Loss check after the summary arrived' "$gp_body"
check_line 'late loss: the lost input is named' '- "Pruefe das Luchsfell am Traeger."' "$gp_body"
check_line 'late loss: the lock line turns to done' 'loss=done' "$(cat "$cs_gate/gp14-compact-lock" 2>/dev/null)"
absent_file 'late loss: a lost input makes the restore file unread again' "$cs_gate/gp14-read-main-compact.restore"
gp_t="$cs_tmp/gp15.jsonl"; cp "$fix/compact-state-no-summary.jsonl" "$gp_t"
js "$gp_t"; printf '{"session_id":"gp15","transcript_path":%s,"hook_event_name":"SessionStart","source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" "$BASH" "$restore_cs" >/dev/null 2>&1
printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary: Pruefe Luchsfell Traeger, Startauftrag Luchsfell."}}' >> "$gp_t"
: > "$cs_gate/gp15-read-main-compact.restore"
lk_out gp15 Bash >/dev/null
check_contains 'late loss counter: a summary with the key words loses nothing' 'has its key words in the summary' \
  "$(cat "$cs_gate/gp15-compact-restore.md" 2>/dev/null)"
present_file 'late loss counter: nothing lost, the read stays' "$cs_gate/gp15-read-main-compact.restore"
# The late check judges the full input, not the 117 characters the restore file shows.
gp_t="$cs_tmp/gp17.jsonl"; cp "$fix/compact-state-no-summary-long.jsonl" "$gp_t"
js "$gp_t"; printf '{"session_id":"gp17","transcript_path":%s,"hook_event_name":"SessionStart","source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" "$BASH" "$restore_cs" >/dev/null 2>&1
printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary: pruefe Luchsbau gruendlich, schreibe Befund Traeger, danach Abstimmung Team."}}' >> "$gp_t"
: > "$cs_gate/gp17-read-main-compact.restore"
lk_out gp17 Bash >/dev/null
check_contains 'late loss: the words past 117 characters count (branch and deadline missing)' 'Missing from the summary (1' \
  "$(cat "$cs_gate/gp17-compact-restore.md" 2>/dev/null)"
absent_file 'late loss: the long lost input makes the restore file unread' "$cs_gate/gp17-read-main-compact.restore"

# The helper's started marker stands only when the call passes every gate of the hook: a later denial
# (agents.md unread) takes it back, so phase 2 never opens without a helper.
printf 'to=1\nneed=compact.crosscheck %s\n' "$cs_gate/gp16-cross-check.md" > "$cs_gate/gp16-compact-lock"
out="$(LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' lk_out gp16 Agent)"
check_contains 'started marker: the rule gate denies the helper while agents.md is unread' 'agents.md' "$out"
absent_file 'started marker: a denied helper start leaves no marker' "$cs_gate/gp16-cross-check-started"
: > "$cs_gate/gp16-read-main-agents"
LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' lk_out gp16 Agent >/dev/null
present_file 'started marker counter: with agents.md read the helper start leaves the marker' "$cs_gate/gp16-cross-check-started"
check_not_contains 'late loss counter: a restore with the summary writes no pending line' 'loss=pending' \
  "$(cat "$cs_gate/gp13-compact-lock" 2>/dev/null)"

# REQ-005: an Agent/Task call whose input names cross-check.md writes the started marker; without
# the name it does not. The gate's lock from cc1 is still there.
cc_lk_out() { # session, tool, extra_input_fields, [agent_id]
  local s n t; js "$1"; s="$REPLY"; js "$2"; n="$REPLY"; js "$fix/compact-state-helper-results.jsonl"; t="$REPLY"
  { printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":%s' "$s" "$t" "$n" "$3"
    if [ -n "${4:-}" ]; then js "$4"; printf ',"agent_id":%s' "$REPLY"; fi
    printf '}\n'; } \
    | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1
}
cc_verdict() { case "$1" in *'this session is locked'*|*'Phase 2 of the compaction lock'*) printf 'LOCK' ;; *) printf 'PASS' ;; esac; }
rm -f "$cs_gate/cc1-cross-check-started"
: > "$cs_gate/cc1-read-main-agents"; : > "$cs_gate/cc4-read-main-agents" # agents.md read: no later gate denies
cc_lk_out cc1 Agent '{"description":"competitor-check","prompt":"follow .claude/skills/chat-handoff/reference/cross-check.md"}' >/dev/null
present_file 'REQ-005: an Agent call naming cross-check.md writes the started marker' "$cs_gate/cc1-cross-check-started"
rm -f "$cs_gate/cc4-cross-check-started"
cc_lk_out cc1 Agent '{"description":"other","prompt":"look up a repo"}' >/dev/null
# cc1 marker already exists from the first call; a fresh session's would not.
rm -f "$cs_gate/cc4-cross-check-started"
printf 'from=0\nto=5\ntranscript=/t/x.jsonl\nneed=compact.restore /t/r.md\nneed=compact.crosscheck /t/c.md\n' > "$cs_gate/cc4-compact-lock"
cc_lk_out cc4 Agent '{"description":"other","prompt":"look up a repo"}' >/dev/null
absent_file 'REQ-005 counter: an Agent call without cross-check.md writes no marker' "$cs_gate/cc4-cross-check-started"
# REQ-005: Task is treated like Agent.
rm -f "$cs_gate/cc4-cross-check-started"
cc_lk_out cc4 Task '{"description":"x","prompt":"follow cross-check.md"}' >/dev/null
present_file 'REQ-005: a Task call naming cross-check.md writes the marker' "$cs_gate/cc4-cross-check-started"

# Phase 2 setup: everything but compact.crosscheck read, cross-check-started marker there.
# Shared across the phase-2 cases below; the fixture uses a lock with one unread need (the restore file) and the
# helper, both marked read / started.
cc_setup_phase2() { # session
  local s="$1"
  : > "$cs_gate/$s-compact-lock-denies"  # fresh valve
  printf 'from=0\nto=42\ntranscript=/t/x.jsonl\nneed=compact.restore %s\nneed=compact.crosscheck %s\n' \
    "$cs_proj/.agents/rules/chat.md" "$cs_gate/$s-cross-check.md" > "$cs_gate/$s-compact-lock"
  : > "$cs_gate/$s-read-main-compact.restore"
  : > "$cs_gate/$s-cross-check-started"
}

# REQ-006 (part 1): without PLAYBOOK_LOCK_SEND_RE phase 2 passes every call.
# `env -u` does not act on a shell function, so the variable is overridden to empty for the
# call - the hook treats empty and unset the same (REQ-006, bash =~ needs a non-empty RE).
cc_setup_phase2 cc5
expect 'REQ-006 no re: Bash passes' PASS "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='' cc_lk_out cc5 Bash '{"command":"gh pr comment 1 --body x"}')")"
expect 'REQ-006 no re: a non-Bash tool passes' PASS "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='' cc_lk_out cc5 mcp__github__add_issue_comment '{"owner":"o","repo":"r","issue_number":1,"body":"x"}')")"

# REQ-006 (part 2): with PLAYBOOK_LOCK_SEND_RE only matching Bash/PowerShell calls lock.
cc_setup_phase2 cc6
# Reproduce a sending command of the session tool (rc send/ask/answer): PLAYBOOK_LOCK_SEND_RE
# matches it with bash =~; a mismatch is a different word.
out="$(PLAYBOOK_LOCK_SEND_RE='rc[[:space:]]+(send|ask|answer)' cc_lk_out cc6 Bash '{"command":"rc send ctrl \"status\""}')"
expect 'REQ-006 match: a matching Bash call locks' LOCK "$(cc_verdict "$out")"
check_contains 'REQ-008: the phase 2 message names the pattern' 'rc[[:space:]]+(send|ask|answer)' "$out"
check_contains 'REQ-008: the phase 2 message names the helper file' "$cs_gate/cc6-cross-check.md" "$out"
check_contains 'REQ-008: the phase 2 message names the helper runtime' 'started' "$out"
: > "$cs_gate/cc6-compact-lock-denies"
expect 'REQ-006 miss: a non-matching Bash call passes' PASS \
  "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='rc[[:space:]]+send' cc_lk_out cc6 Bash '{"command":"ls -la"}')")"
expect 'REQ-006: a non-Bash tool passes in phase 2 even with the regex' PASS \
  "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='rc[[:space:]]+send' cc_lk_out cc6 mcp__github__add_issue_comment '{"owner":"o","repo":"r","issue_number":1,"body":"x"}')")"

# REQ-007: phase 1 (helper not started) locks like today; a matching command locks in phase 1 too
# because phase 1 does not look at the regex.
cc_setup_phase2 cc7
rm -f "$cs_gate/cc7-cross-check-started"  # revert to phase 1
expect 'REQ-007: phase 1 locks a Bash call without the regex' LOCK \
  "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='' cc_lk_out cc7 Bash '{"command":"ls"}')")"
: > "$cs_gate/cc7-compact-lock-denies"
# Phase 1 counter: when the restore file is unread phase 2 cannot start even with the regex.
cc_setup_phase2 cc8
rm -f "$cs_gate/cc8-read-main-compact.restore"  # restore file still unread
expect 'phase 1: an unread restore file keeps it' LOCK \
  "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='nothing' cc_lk_out cc8 Bash '{"command":"ls"}')")"

# REQ-009: require-receipt.sh (Stop) blocks the turn end while phase 1 stands; phase 2 is free;
# stop_hook_active warns; without a lock the turn ends. The transcript carries a receipt so the
# receipt check passes and the compact lock is what the hook judges.
cc_stop() { # session, stop_hook_active -> stdout
  local s t; js "$1"; s="$REPLY"; js "$fix/with-receipt.jsonl"; t="$REPLY"
  printf '{"transcript_path":%s,"session_id":%s,"stop_hook_active":%s}\n' "$t" "$s" "$2" \
    | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$stop" 2>&1
}
cc_setup_phase2 cc9
rm -f "$cs_gate/cc9-cross-check-started" "$cs_gate/cc9-read-main-compact.restore"  # phase 1
out="$(cc_stop cc9 false)"
case "$out" in *'"decision":"block"'*) ok 'REQ-009: phase 1 blocks the turn end' block ;; *) bad 'REQ-009: phase 1 blocks the turn end' "$out" block ;; esac
check_contains 'REQ-009: the block names the compaction lock' 'compaction lock' "$out"
# Phase 2: stop passes.
cc_setup_phase2 cc10
out="$(cc_stop cc10 false)"
case "$out" in '') ok 'REQ-009: phase 2 lets the turn end' allow ;; *) bad 'REQ-009: phase 2 lets the turn end' "$out" allow ;; esac
# stop_hook_active in phase 1: warn, do not block (loop guard).
cc_setup_phase2 cc11
rm -f "$cs_gate/cc11-cross-check-started"
out="$(cc_stop cc11 true)"
case "$out" in *'"decision":"block"'*) bad 'REQ-009: stop_hook_active in phase 1 warns, never blocks' "$out" warn ;;
  *systemMessage*) ok 'REQ-009: stop_hook_active in phase 1 warns' warn ;;
  *) bad 'REQ-009: stop_hook_active in phase 1 warns' "$out" warn ;; esac
# No lock: the turn ends.
rm -f "$cs_gate/cc12-compact-lock"
out="$(cc_stop cc12 false)"
case "$out" in '') ok 'REQ-009: without a lock the turn ends' allow ;; *) bad 'REQ-009: without a lock the turn ends' "$out" allow ;; esac

# Release wipes the started marker alongside the lock files; a next restore starts fresh.
cc_setup_phase2 cc13
rm -f "$cs_gate/cc13-cross-check-started"  # phase 1 so the normal release path runs
# All read, no helper needed: build a lock without compact.crosscheck.
printf 'from=0\nto=0\ntranscript=/t/x.jsonl\nneed=compact.restore %s\n' "$cs_proj/.agents/rules/chat.md" > "$cs_gate/cc13-compact-lock"
: > "$cs_gate/cc13-read-main-compact.restore"
: > "$cs_gate/cc13-cross-check-started"  # a stale marker
cc_lk_out cc13 Bash '{"command":"ls"}' >/dev/null
absent_file 'REQ-005: release wipes the started marker' "$cs_gate/cc13-cross-check-started"
# A new restore also removes an old started marker (restore-compact-state.sh).
: > "$cs_gate/cc14-cross-check-started"
cs_restore cc14 "$fix/compact-state-helper-results.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
absent_file 'REQ-005: a new restore removes an old started marker' "$cs_gate/cc14-cross-check-started"

# Mutation probes (correction rounds, .agents/rules/pr.md § "Test Runs"):
# REQ-001: setting to back to the older-part growth makes a counter-case lock when the mark equals it.
# This is simulated by rewriting the lock file after restore - the mutation is that the hook would do that.
# A false green here would come from the test calling the mutation itself, which is why the fixture
# below shows the opposite: when `end` is the transcript's full line count, cc3 above saw no need
# at mark == total; a mutated version would still need to prove the counter.
cs_save cc_mut1 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
# cc_mut1 at mark=0, to must equal transcript line count. If the implementation reverted to older-growth,
# cc_mut1 with mark=0 and no previous compaction would still need, but to would equal the older-part end,
# not the transcript's end. The invariant: to == transcript line count.
cs_restore cc_mut1 "$fix/compact-state-helper-results.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
cc_mut_to="$(sed -n 's/^to=//p' "$cs_gate/cc_mut1-compact-lock" 2>/dev/null)"
expect 'mutation REQ-001: to equals the transcript line count, not the older part' "$cc_total" "$cc_mut_to"
# REQ-006 mutation: the gate's phase-2 matcher ignores empty strings; a mutation that locked on
# an empty regex would hit every Bash call. The counter-case already runs under cc5; this doubles.
cc_setup_phase2 cc_mut2
expect 'mutation REQ-006: an empty regex passes every Bash call' PASS \
  "$(cc_verdict "$(PLAYBOOK_LOCK_SEND_RE='' cc_lk_out cc_mut2 Bash '{"command":"rc send x"}')")"

echo "== cross-check.md step 2: rebuke counts as a demand, own proposal stays open, pending of the summary is an input (ww3d/playbook#487 REQ-039..041) =="
# The bash+jq snippet of cross-check.md is extracted from the file itself (first ```bash block),
# so the test checks the shipped snippet and not a copy. The snippet uses $transcript, $von, $bis
# and derives MAIN_AGENT_IDS from the transcript itself (the shipped vorlauf).
cc_md=".claude/skills/chat-handoff/reference/cross-check.md"
cc_snippet="$(awk '/^   ```bash$/{on=1;next} /^   ```$/{on=0} on' "$repo_root/$cc_md" | sed -E 's/^   //')"
cc_fix="$fix/compact-state-rebuke-proposal-pending.jsonl"
cc_total_rpp="$(wc -l < "$cc_fix" | tr -d ' ')"
cc_out="$(transcript="$cc_fix" von=1 bis="$cc_total_rpp" bash -c "$cc_snippet" 2>&1 || true)"
# REQ-039: each rebuke of the maintainer stands as its own IN line with the rebuke's own pattern,
# so the helper can tell it apart from a plain input (the pattern-based assertion is the counter
# the review's REQ-039 asked for, no mock, no LLM semantics).
case "$cc_out" in *$'\n''IN  Z'*'nutzt du denn nicht mcp? warum kommen so fehler?'*) ok 'REQ-039: the first rebuke stands as an IN line with its pattern' 'IN found' ;; *) bad 'REQ-039: the first rebuke stands as an IN line with its pattern' "$cc_out" 'IN found' ;; esac
case "$cc_out" in *$'\n''IN  Z'*'halt dich an die regeln'*) ok 'REQ-039: the second rebuke stands as an IN line with its pattern' 'IN found' ;; *) bad 'REQ-039: the second rebuke stands as an IN line with its pattern' "$cc_out" 'IN found' ;; esac
# REQ-040: an own proposal without future form stays as OUT; the counter-case (an own promise with
# "ich werde ..." as future form) also stands as OUT and both are therefore indistinguishable at
# the jq layer - the helper's step 2 does the semantic split, not the extract.
case "$cc_out" in *'OUT Z4'*'Besser ist eine feste Sperre'*) ok 'REQ-040: an own proposal stands as an OUT line' 'OUT found' ;; *) bad 'REQ-040: an own proposal stands as an OUT line' "$cc_out" 'OUT found' ;; esac
case "$cc_out" in *$'\n''OUT Z'*'Ich werde die Phase 2 pruefen'*) ok 'REQ-040 counter: an own promise with future form stands as OUT too' 'OUT found' ;; *) bad 'REQ-040 counter: an own promise with future form stands as OUT too' "$cc_out" 'OUT found' ;; esac
# REQ-041: PEN carries the summary with its "Pending Tasks" marker AND each pending pattern.
case "$cc_out" in *'PEN Z'*'Pending Tasks'*) ok 'REQ-041: the compact summary stands as a PEN line' 'PEN found' ;; *) bad 'REQ-041: the compact summary stands as a PEN line' "$cc_out" 'PEN found' ;; esac
case "$cc_out" in *'PEN Z'*'Offene Pending-Zeile Fuchsbau'*) ok 'REQ-041: PEN carries the first pending pattern (Fuchsbau)' 'pattern found' ;; *) bad 'REQ-041: PEN carries the first pending pattern (Fuchsbau)' "$cc_out" 'pattern found' ;; esac
case "$cc_out" in *'PEN Z'*'Offene Pending-Zeile Reineke'*) ok 'REQ-041: PEN carries the second pending pattern (Reineke)' 'pattern found' ;; *) bad 'REQ-041: PEN carries the second pending pattern (Reineke)' "$cc_out" 'pattern found' ;; esac
# Counter: the isCompactSummary user line does not also land as IN (its row is PEN alone). Checked
# per line, because case `*A*B*` matches A and B anywhere in the whole output (across lines).
cc_in_re='^IN +Z[0-9]+ .*Pending Tasks'; cc_in=0
while IFS= read -r cc_l; do if [[ $cc_l =~ $cc_in_re ]]; then cc_in=1; break; fi; done <<<"$cc_out"
if [ "$cc_in" = 1 ]; then bad 'REQ-041 counter: the summary is not IN' "$cc_out" 'no IN line with Pending Tasks'; else ok 'REQ-041 counter: the summary is not IN' 'no IN line with Pending Tasks'; fi

# REQ-012 HLP foreground form: the shipped vorlauf derives MAIN_AGENT_IDS from the transcript, so
# a fixture with an Agent/Task tool_use produces an "HLP ... sub-agent <id>" row at the jq layer.
cc_fix_hlp="$fix/compact-state-helper-results.jsonl"
cc_total_hlp="$(wc -l < "$cc_fix_hlp" | tr -d ' ')"
cc_out_hlp="$(transcript="$cc_fix_hlp" von=1 bis="$cc_total_hlp" bash -c "$cc_snippet" 2>&1 || true)"
case "$cc_out_hlp" in *'HLP Z'*'sub-agent ag_1'*'Konkurrent WaselX'*) ok 'REQ-012: HLP foreground form (tool_result of an Agent tool_use) stands as HLP sub-agent <id>' 'HLP sub-agent found' ;; *) bad 'REQ-012: HLP foreground form (tool_result of an Agent tool_use) stands as HLP sub-agent <id>' "$cc_out_hlp" 'HLP sub-agent found' ;; esac
case "$cc_out_hlp" in *'HLP Z'*'task-notification: '*'Export-Spalte XVZ'*) ok 'REQ-012: HLP background form (task-notification) still stands' 'HLP task-notification found' ;; *) bad 'REQ-012: HLP background form (task-notification) still stands' "$cc_out_hlp" 'HLP task-notification found' ;; esac

finish
