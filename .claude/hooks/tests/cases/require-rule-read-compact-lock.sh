#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, the lock after a compaction
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-compact-lock.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"
use_rc_root

echo "== require-rule-read.sh: the lock after a compaction (ww3d/playbook#487) =="
lk_state="$cs_proj/.agent/state"
lk_lock() { # session, transcript, [from], [to] - a lock with the session's unread restore file under the project
  mkdir -p "$lk_state"
  [ -e "$lk_state/$1-restore.md" ] || printf '# Restore\n\n## History without a carrier\n\n- [ ] L1 - human: offen\n' > "$lk_state/$1-restore.md"
  printf 'from=%s\nto=%s\ntranscript=%s\nneed=compact.restore %s\n' "${3:-0}" "${4:-0}" "$2" "$lk_state/$1-restore.md" > "$cs_gate/$1-compact-lock"
}
# session, [stop_hook_active] -> global lk_v ALLOW, BLOCK or WARN of require-receipt.sh, its raw output in lk_so
lk_stop() {
  lk_so="$(stop_in "$fix/no-receipt.jsonl" "${2:-false}" "$1" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" bash "$stop" 2>&1)"
  if has_text '"decision":"block"' "$lk_so"; then lk_v=BLOCK
  elif has_text 'systemMessage' "$lk_so"; then lk_v=WARN
  elif [ -z "$lk_so" ]; then lk_v=ALLOW; else lk_v="ERR $lk_so"; fi
}

# The restore writes a lock that needs the restore file and chat.md, and no helper (ww3d/playbook#621).
for m in local-ci-silence local-naming; do : > "$cs_gate/lk1-read-main-$m"; done
cs_save lk1 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
out="$(cs_restore lk1 "$fix/compact-state.jsonl" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
lock="$(cat "$cs_gate/lk1-compact-lock" 2>/dev/null)"
expect 'lock: two needs, the restore file and chat.md' 2 "$(grep -c '^need=' <<<"$lock")"
expect 'lock: one need is compact.restore' 1 "$(lk_need lk1 compact.restore)"
expect 'lock: one need is chat' 1 "$(lk_need lk1 chat)"
check_contains 'lock: the chat need names the project chat.md' 'chat.md' "$(grep '^need=chat ' <<<"$lock")"
check_contains 'lock: the chat need is under the project root' 'cs-proj' "$(grep '^need=chat ' <<<"$lock")"
check_contains 'lock: the hint names chat.md' 'chat.md in full as well' "$ctx"
for m in local-ci-silence local-naming pr; do expect "lock: the rule file $m is no need" 0 "$(lk_need lk1 "$m")"; done
check_line 'lock: it starts at the cursor of the last save' 'from=0' "$lock"
for w in helper cross-check; do check_not_contains "lock: the lock asks for no $w" "$w" "$lock"; done
for w in cross-check pair-check 'start the helper'; do check_not_contains "lock: the hint asks for no helper ($w)" "$w" "$ctx"; done
check_contains 'lock: the hint names the gate' 'require-rule-read.sh holds' "$ctx"
expect 'lock: a call of the main thread is denied' LOCK "$(lk_verdict lk1 Bash)"
out="$(lk_out lk1 Edit)"
for w in helper cross-check; do check_not_contains "denial: names no $w" "$w" "${out//Sub-agents/x}"; done
expect 'valve: the third denial in the turn' LOCK "$(LK_INPUT='{"description":"Pruefung","prompt":"recherchiere"}' lk_verdict lk1 Agent)"
expect 'valve: after the third denial the rest of the turn passes' PASS "$(lk_verdict lk1 Bash)"
present_file 'valve: the lock stays for the next turn' "$cs_gate/lk1-compact-lock"
printf '999999 0\n' > "$cs_gate/lk1-compact-lock-denies"
expect 'lock: an Agent call is held like any other' LOCK "$(LK_INPUT='{"description":"Pruefung","prompt":"recherchiere"}' lk_verdict lk1 Agent)"
expect 'lock: a Task call is held like any other' LOCK "$(LK_INPUT='{"prompt":"recherchiere"}' lk_verdict lk1 Task)"
expect 'lock: a helper prompt opens nothing' LOCK \
  "$(LK_INPUT='{"prompt":"follow .claude/skills/chat-handoff/reference/pair-check.md"}' lk_verdict lk1 Agent)"
expect 'lock: a sub-agent is free' PASS "$(lk_verdict lk1 Bash agent-x1)"
# Reads: another session's file, a sub-agent's read and a short part leave the lock; the part reaching the end lifts it.
f1="$(cs_rfile lk1)"; total="$(wc -l < "$f1" | tr -d ' ')"
lk_read lk1 "$(cs_rfile other)" "" "$cs_proj"
absent_file "read: another session's restore file does not count" "$cs_gate/lk1-read-main-compact.restore"
lk_read lk1 "$f1" "" "$cs_proj" agent-r1
absent_file 'read: a sub-agent read is no main-thread read' "$cs_gate/lk1-read-main-compact.restore"
printf '999999 0\n' > "$cs_gate/lk1-compact-lock-denies"
expect 'lock: a sub-agent read does not release the main thread' LOCK "$(lk_verdict lk1 Bash)"
lk_read lk1 "$f1" "1 2 $total" "$cs_proj"
absent_file 'read: a part short of the end does not count' "$cs_gate/lk1-read-main-compact.restore"
lk_read lk1 "$f1" "3 $((total - 2)) $total" "$cs_proj"
present_file 'read: the part reaching the end counts' "$cs_gate/lk1-read-main-compact.restore"
out="$(lk_out lk1 Bash)"
check_contains 'chat.md unread: the call is still denied' 'this session is locked' "$out"
check_contains 'chat.md unread: the denial names chat.md' 'chat.md' "$out"
check_not_contains 'chat.md unread: the denial no longer names the read restore file' 'lk1-restore.md' "$out"
lk_read lk1 "$cs_proj/.agents/rules/chat.md" "1 1 2" "$cs_proj"
absent_file 'read: a part of chat.md does not count' "$cs_gate/lk1-read-main-chat"
lk_read lk1 "$cs_proj/.agents/rules/chat.md" "" "$cs_proj" agent-r1
expect 'chat.md read by a sub-agent: the main thread stays locked' LOCK "$(lk_verdict lk1 Bash)"
printf '999999 0\n' > "$cs_gate/lk1-compact-lock-denies"
lk_read lk1 "$cs_proj/.agents/rules/chat.md" "" "$cs_proj"
present_file 'read: chat.md in full counts' "$cs_gate/lk1-read-main-chat"
expect 'release: the next call passes' PASS "$(lk_verdict lk1 Bash)"
absent_file 'release: the lock file goes' "$cs_gate/lk1-compact-lock"
absent_file 'release: the denial count goes' "$cs_gate/lk1-compact-lock-denies"
# Read in full, then changed by the session: ticked boxes make the file shorter or longer; the lock stays gone and
# the turn end waits only for open boxes.
sed -i 's/^- \[ \] \(.*\)$/- [x] \1 -> ww3d\/playbook#487/' "$f1"; sed -i '$d' "$f1"
expect 'changed after the full read, shorter: the lock stays gone' PASS "$(lk_verdict lk1 Edit)"
sed -i '/^## History without a carrier$/a - [ ] L99 - human: noch offen' "$f1"
lk_stop lk1; expect 'changed after the full read: the turn end is held for the open box' BLOCK "$lk_v"
check_not_contains 'changed after the full read: not held as unread' 'Not read in full yet' "$lk_so"
sed -i 's/^- \[ \] \(.*\)$/- [x] \1 -> ww3d\/playbook#487/' "$f1"; printf 'Nachtrag der Session.\n\n' >> "$f1"
lk_stop lk1; expect 'changed after the full read, longer, every box ticked: the turn ends' ALLOW "$lk_v"
expect 'changed after the full read, longer: the lock stays gone' PASS "$(lk_verdict lk1 Bash)"

# The next compaction: what the earlier lock left - a denial count, a gapless-read state - goes with the new restore.
printf '5 2\n' > "$cs_gate/lk1-compact-lock-denies"; printf '1 3\n' > "$cs_gate/lk1-read-main-compact.restore.upto"
printf '1 3\n' > "$cs_gate/lk1-read-agent-r1-compact.restore.upto"
cs_restore lk1 "$fix/compact-state.jsonl" >/dev/null 2>&1
absent_file 'new restore: the denial count goes' "$cs_gate/lk1-compact-lock-denies"
absent_file 'new restore: the gapless-read state goes' "$cs_gate/lk1-read-main-compact.restore.upto"
absent_file 'new restore: a sub-agent read state goes' "$cs_gate/lk1-read-agent-r1-compact.restore.upto"
rm -f "$cs_gate/lk1-read-main-compact.restore"
expect 'new restore: the new file locks again' LOCK "$(lk_verdict lk1 Bash)"

# Valve, fail-open: a need whose file is gone passes; a hook error passes (the denial count cannot be written).
printf 'to=1\nneed=compact.restore %s\n' "$lk_state/no-such-restore.md" > "$cs_gate/lk2-compact-lock"
expect 'valve: a missing file passes' PASS "$(lk_verdict lk2 Bash)"
lk_lock lk4 "$fix/compact-state.jsonl"; mkdir -p "$cs_gate/lk4-compact-lock-denies"
expect 'valve: a hook error passes' PASS "$(lk_verdict lk4 Bash)"
# A repo without .agents/rules/chat.md: the lock needs the restore file only.
lk_nochat="$fix/lk-nochat"; mkdir -p "$lk_nochat"
cs_restore lk13 "$fix/compact-state.jsonl" "" "$lk_nochat" >/dev/null 2>&1
expect 'no chat.md in the repo: one need, the restore file' 1 "$(grep -c '^need=' "$cs_gate/lk13-compact-lock" 2>/dev/null)"
expect 'no chat.md in the repo: no chat need' 0 "$(lk_need lk13 chat)"
# chat.md gone after the restore: the need passes like any missing file.
printf 'to=1\nneed=chat %s\n' "$lk_nochat/.agents/rules/chat.md" > "$cs_gate/lk14-compact-lock"
expect 'valve: a chat.md that is gone passes' PASS "$(lk_verdict lk14 Bash)"

# A restore file larger than one read: the first 2,000 lines do not count;
# the turn end stays held until the rest is read.
lk_lock lk3 "$fix/compact-state.jsonl"
for ((i = 1; i <= 3000; i++)); do printf 'Zeile %s\n' "$i"; done > "$lk_state/lk3-restore.md"
lk_read lk3 "$lk_state/lk3-restore.md" "1 2000 3000" "$cs_proj"
expect 'large file: the first 2,000 lines leave the lock' LOCK "$(lk_verdict lk3 Bash)"
lk_stop lk3; expect 'large file: the turn end is held' BLOCK "$lk_v"
check_contains 'large file: held as not read in full' 'Not read in full yet' "$lk_so"
for w in helper cross-check; do check_not_contains "large file: the stop names no $w" "$w" "$lk_so"; done
lk_stop lk3 true; expect 'large file: the second stop of the turn warns' WARN "$lk_v"
for w in helper cross-check; do check_not_contains "large file: the warning names no $w" "$w" "$lk_so"; done
lk_read lk3 "$lk_state/lk3-restore.md" "2001 1000 3000" "$cs_proj"
lk_stop lk3; expect 'large file: read to the end, the turn ends' ALLOW "$lk_v"
expect 'large file: read to the end, the lock lifts' PASS "$(lk_verdict lk3 Bash)"

# The net: a lock older than 30 s whose transcript has no main-thread boundary after the cursor falls - a helper
# compaction lib/compaction.sh did not tell.
fresh; { human 'Arbeit am Export.'; said 'Ich arbeite weiter.'; } > "$fix/lk-net.jsonl"
lk_lock lk5 "$fix/lk-net.jsonl" 1; touch -d '-40 seconds' "$cs_gate/lk5-compact-lock"
expect 'net: an old lock without a main boundary after the cursor falls' PASS "$(lk_verdict lk5 Bash)"
absent_file 'net: the lock goes' "$cs_gate/lk5-compact-lock"
check_contains 'net: the owner log says why' 'helper net: no main compact_boundary after line 1' "$(cat "$cs_gate/lk5-compaction-owner" 2>/dev/null)"
lk_lock lk6 "$fix/lk-net.jsonl" 1
expect 'net: a fresh lock without a boundary holds' LOCK "$(lk_verdict lk6 Bash)"
cp "$fix/lk-net.jsonl" "$fix/lk-net-main.jsonl"; boundary >> "$fix/lk-net-main.jsonl"
lk_lock lk7 "$fix/lk-net-main.jsonl" 1; touch -d '-40 seconds' "$cs_gate/lk7-compact-lock"
expect 'net: an old lock with a main boundary after the cursor holds' LOCK "$(lk_verdict lk7 Bash)"
cp "$fix/lk-net.jsonl" "$fix/lk-net-side.jsonl"
printf '%s\n' '{"type":"system","subtype":"compact_boundary","isSidechain":true}' >> "$fix/lk-net-side.jsonl"
lk_lock lk12 "$fix/lk-net-side.jsonl" 1; touch -d '-40 seconds' "$cs_gate/lk12-compact-lock"
expect "net: a side thread's boundary is no main boundary" PASS "$(lk_verdict lk12 Bash)"
lk_lock lk13 "$fix/lk-net-main.jsonl" 3; touch -d '-40 seconds' "$cs_gate/lk13-compact-lock"
expect 'net: a boundary before the cursor does not count' PASS "$(lk_verdict lk13 Bash)"
# The boundary of this compaction comes after the hook's line count `to`: an earlier one between the cursor and
# `to - 20` belongs to an earlier compaction.
fresh; { human 'Arbeit am Export.'; boundary; for i in $(seq 1 38); do said "Schritt $i."; done; } > "$fix/lk-net-early.jsonl"
lk_lock lk18 "$fix/lk-net-early.jsonl" 1 40; touch -d '-40 seconds' "$cs_gate/lk18-compact-lock"
expect 'net: a boundary of an earlier compaction before to - 20 does not count, the old lock falls' PASS "$(lk_verdict lk18 Bash)"
absent_file 'net: the lock with an earlier boundary goes' "$cs_gate/lk18-compact-lock"
check_contains 'net: the owner log names the helper net' 'helper net' "$(cat "$cs_gate/lk18-compaction-owner" 2>/dev/null)"
cp "$fix/lk-net-early.jsonl" "$fix/lk-net-late.jsonl"; boundary >> "$fix/lk-net-late.jsonl"
lk_lock lk19 "$fix/lk-net-late.jsonl" 1 40; touch -d '-40 seconds' "$cs_gate/lk19-compact-lock"
expect 'net: a boundary after to holds the old lock' LOCK "$(lk_verdict lk19 Bash)"
present_file 'net: the lock with a boundary after to stays' "$cs_gate/lk19-compact-lock"
# The age edge: 30 s is the limit.
lk_lock lk20 "$fix/lk-net.jsonl" 1; touch -d '-28 seconds' "$cs_gate/lk20-compact-lock"
expect 'net: a lock 28 s old holds' LOCK "$(lk_verdict lk20 Bash)"
lk_lock lk21 "$fix/lk-net.jsonl" 1; touch -d '-32 seconds' "$cs_gate/lk21-compact-lock"
expect 'net: a lock 32 s old falls' PASS "$(lk_verdict lk21 Bash)"

# A restore file with an empty last line: the Read tool counts it in totalLines; reading to the last text line is
# the full read.
f22="$lk_state/lk22-restore.md"; { for i in $(seq 1 753); do printf 'Zeile %s\n' "$i"; done; printf '\n'; } > "$f22"
lk_lock lk22 "$fix/compact-state.jsonl"
lk_read lk22 "$f22" "1 753 754" "$cs_proj"
present_file 'read: up to the last text line before an empty last line counts' "$cs_gate/lk22-read-main-compact.restore"
expect 'read: up to the last text line, the lock lifts' PASS "$(lk_verdict lk22 Bash)"

# After the compaction the lock asks for the restore file only: no rule file read before it is asked again before a
# call outside its kind.
for m in chat pr local-naming; do : > "$cs_gate/lk23-read-main-$m"; done
cs_save lk23 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore lk23 "$fix/compact-state.jsonl" >/dev/null 2>&1
lk_read lk23 "$(cs_rfile lk23)" "" "$cs_proj"
out="$(lk_out lk23 Bash)"
expect 'after the restore read: a call outside a rule kind passes' PASS "$(lk_verdict lk23 Bash)"
check_not_contains 'after the restore read: no rule file read before is asked again' 'has not been read' "$out"
absent_file 'after the restore read: the lock is gone' "$cs_gate/lk23-compact-lock"

# The turn count, differential: a tool result, a meta line and a compaction summary start no turn,
# a user line does. The key is the turn start's line number.
lk_user='{"type":"user","message":{"role":"user","content":"Weiter mit der Sperre."}}'
lk_result='{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"ok"}]}}'
lk_meta='{"type":"user","isMeta":true,"message":{"role":"user","content":"<meta>"}}'
lk_summary='{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Zusammenfassung."}}'
lk_asst='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Arbeit."}]}}'
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
# A broken count under this turn's own key: the count starts again at 1.
lk_lock lk14 "$fix/compact-state.jsonl"; lk_verdict lk14 Bash >/dev/null
read -r lk_k _ < "$cs_gate/lk14-compact-lock-denies"; printf '%s y\n' "$lk_k" > "$cs_gate/lk14-compact-lock-denies"
expect 'valve: a broken denial count locks from 1' LOCK "$(lk_verdict lk14 Bash)"
expect 'valve: the broken count is written anew' "$lk_k 1" "$(lk_denies lk14)"

# The restore file read whole, and in parts: the parts count once they close up from line 1 to the
# end, in whatever order their hooks ran (parallel reads of one answer).
mkdir -p "$lk_state"; lk_f="$lk_state/lk10-restore.md"; for ((i = 1; i <= 10; i++)); do printf 'Zeile %s\n' "$i"; done > "$lk_f"
lk_m="$cs_gate/lk10-read-main-compact.restore"
lk_read lk10 "$lk_f" "" "$cs_proj"
present_file 'read: the restore file read whole counts' "$lk_m"
rm -f "$lk_m" "$lk_m.upto"
lk_read lk10 "$lk_f" "1 10" "$cs_proj"
absent_file 'read: a part without totalLines does not count' "$lk_m"
lk_read lk10 "$lk_f" "10 1 10" "$cs_proj"
absent_file 'read: a lone read of the last line does not count' "$lk_m"
lk_read lk10 "$lk_f" "5 3 10" "$cs_proj"
absent_file 'read: parts with a gap before them do not count' "$lk_m"
lk_read lk10 "$lk_f" "1 4 10" "$cs_proj"
absent_file 'read: closing up to line 7 is not the end yet' "$lk_m"
lk_read lk10 "$lk_f" "8 2 10" "$cs_proj"
present_file 'read: parts out of order without a gap up to the end count' "$lk_m"
lk_read lk17 "$lk_state/lk17-restore.md" "1 0 0" "$cs_proj"
present_file 'read: an empty restore file read counts' "$cs_gate/lk17-read-main-compact.restore"

# The denial: valid JSON with the missing path, also one with backslashes and a quote; Read and a non-GitHub
# MCP tool never reach the gate, a GitHub MCP tool does.
lk_dir="$cs_gate/lk11 dir"; mkdir -p "$lk_dir"
if command -v cygpath >/dev/null 2>&1; then : > "$lk_dir/lk11-restore.md"; lk_f="$(cygpath -w "$lk_dir/lk11-restore.md")"
else lk_f="$lk_dir/back\\slash \"q\".md"; : > "$lk_f"; fi
printf 'from=0\nto=7\ntranscript=%s\nneed=compact.restore %s\n' "$fix/compact-state.jsonl" "$lk_f" > "$cs_gate/lk11-compact-lock"
out="$(lk_out lk11 Bash)"
expect 'denial: valid JSON with a deny' true \
  "$(printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null || echo false)"
reason="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)"
check_line 'denial: names the missing file on a line of its own' "- $lk_f" "$reason"
check_contains 'denial: says how to read it' 'in parts with offset and limit' "$reason"
expect 'lock: a GitHub MCP call is denied' LOCK "$(lk_verdict lk11 mcp__github__get_me)"
expect 'lock: a Read never reaches the gate' PASS "$(lk_verdict lk11 Read)"
expect 'lock: a non-GitHub MCP call never reaches it' PASS "$(lk_verdict lk11 mcp__slack__post)"

# The weekly sweep of read-confirm.sh takes the compaction files too.
cs_sweep="$fix/cs-tmp-sweep/claude-rule-gate"; mkdir -p "$cs_sweep"
for f in old-compact-rules old-compact-lock old-compaction-owner; do : > "$cs_sweep/$f"; touch -d '10 days ago' "$cs_sweep/$f"; done
version_ctx "$fix/no-such-remote" 1.0.0 startup "$fix/cs-tmp-sweep" >/dev/null
absent_file 'sweep: a week-old save goes' "$cs_sweep/old-compact-rules"
absent_file 'sweep: a week-old lock goes' "$cs_sweep/old-compact-lock"
absent_file 'sweep: a week-old owner log goes' "$cs_sweep/old-compaction-owner"

finish
