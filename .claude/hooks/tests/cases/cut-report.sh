#!/usr/bin/env bash
# Hook suite section: the report after each cut (ww3d/playbook#487, decisions 24-30 in
# docs/decisions/2026-11-12T2316Z-playbook-487-meldung-decisions.md) - the marker of restore-compact-state.sh, the
# line require-receipt.sh has session-state.sh report write, silent cuts, the further channel and the replay.
# Run alone: bash .claude/hooks/tests/cases/cut-report.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== report after each cut: marker, line, silent cuts, channel, replay (ww3d/playbook#487) =="
ss="$hooks/session-state.sh"
proj="$fix/cut-proj"; mkdir -p "$proj/.agents/rules"
printf '9.8.7\n' > "$proj/VERSION"
printf '# chat\n' > "$proj/.agents/rules/chat.md"
# Its own repository with an origin: the repo field comes from there, never from the checkout around the suite.
git init -q "$proj" && git -C "$proj" remote add origin https://github.com/acme/widget.git
cuts="$proj/.agent/state/cuts.jsonl"

# Transcript lines beside the harness's own: an answer with usage, a boundary with its numbers, a lock denial.
ans() { # message id, input, cache write, cache read, output
  line "\"type\":\"assistant\",\"message\":{\"id\":\"$1\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\",\"content\":[{\"type\":\"text\",\"text\":\"x\"}],\"usage\":{\"input_tokens\":$2,\"cache_creation_input_tokens\":$3,\"cache_read_input_tokens\":$4,\"output_tokens\":$5}}"
}
cut() { # trigger, preTokens, postTokens
  line "\"type\":\"system\",\"subtype\":\"compact_boundary\",\"isSidechain\":false,\"content\":\"Conversation compacted\",\"compactMetadata\":{\"trigger\":\"$1\",\"preTokens\":$2,\"postTokens\":$3,\"durationMs\":900}"
}
denied() { # tool id, n of 3
  call "$1" Bash '{"command":"ls"}'
  js "After the compaction this session is locked until it has read in full with the Read tool:
- /x/restore.md
Sub-agents are not locked. Valve: denial $2 of 3 in this turn; after the third the rest of this turn passes."
  line "\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$1\",\"is_error\":true,\"content\":$REPLY}]}"
}
restore() { # session, transcript -> the SessionStart hook of the compaction
  restore_event "$1" "$2" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" "$BASH" "$restore_cs" > /dev/null 2>&1
  # The marker's time on the fixture clock (the boundaries come at 10:mm), as the hook stamps it before the boundary.
  [ ! -f "$cs_gate/$1-cut-pending" ] || sed -i 's/^at=.*/at=2026-11-12T10:00:00Z/' "$cs_gate/$1-cut-pending"
}
stop() { # session, transcript, [PATH] -> the Stop hook's output
  stop_in "$2" false "$1" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" PATH="${3:-$PATH}" bash "$stop" 2>&1
}
read_all() { # session -> every need of its lock read in full, as record-rule-read.sh leaves it
  touch "$cs_gate/$1-read-main-compact.restore" "$cs_gate/$1-read-main-chat"
}
tick() { # session -> the boxes of the restore file ticked: the first carried, the rest struck
  local f; f="$proj/.agent/state/$1-restore.md"
  awk '/^- \[ \] / { n++; sub(/^- \[ \] /, "- [x] "); $0 = $0 (n == 1 ? " -> ww3d/playbook#487" : " -> erledigt") } { print }' \
    "$f" > "$f.t" && mv -f "$f.t" "$f"
}
cutline() { jq -c --arg s "$1" 'select(.session == $s)' "$cuts" 2>/dev/null | tr -d '\r'; } # session -> its lines
field() { jq -r "$2" <<< "$1" 2>/dev/null | tr -d '\r'; } # line, jq path

# --- a compaction of the main thread, worked off: one line done true, the marker gone ---
tx="$fix/cut1.jsonl"; fresh
{ human 'Bitte den Bau fertig machen.'; said 'Ich mache den Bau heute fertig.'; said 'Ich schicke die Liste morgen an ctrl-x.'
  ans m0 5 6 7 8; } > "$tx"
cs_state "$proj" cut1 1 2026-11-12T1004Z 2026-11-12T10:04:30Z
restore cut1 "$tx"
mk="$cs_gate/cut1-cut-pending"
present_file 'marker: the restore leaves it' "$mk"
check_line 'marker: it names the compaction kind' 'cut=compact' "$(cat "$mk" 2>/dev/null)"
check_line 'marker: it names the need of the restore file' 'need=compact.restore' "$(cat "$mk" 2>/dev/null)"
{ cut auto 180000 9000; summary 'Zusammenfassung'; ans m1 10 100 1000 50; ans m2 20 200 2000 60; } >> "$tx"
o_held="$(stop cut1 "$tx")"
check_contains 'held: the unread restore still holds the turn end' '"decision":"block"' "$o_held"
check_line 'held: the hold is counted in the marker' 'stopHolds=1' "$(cat "$mk" 2>/dev/null)"
absent_file 'held: no line while the restore is not done' "$cuts"
read_all cut1; tick cut1
out="$(stop cut1 "$tx")"
expect 'done: the turn end passes as without a report' '' "$out"
absent_file 'done: the marker is dropped after the line' "$mk"
l="$(cutline cut1)"
expect 'done: exactly one line' 1 "$(grep -c . <<< "$l")"
expect 'done: v 1, done true, hook ran, cut compact' '1 true ran compact' "$(field "$l" '"\(.v) \(.done) \(.hook) \(.cut)"')"
expect 'done: the boundary of this compaction' '00000005-aaaa-4bbb-8ccc-dddddddddddd 2026-11-12T10:05:00.000Z' \
  "$(field "$l" '"\(.boundaryUuid) \(.boundaryAt)"')"
expect 'done: trigger and tokens of the boundary' 'auto 180000 9000' "$(field "$l" '"\(.trigger) \(.preTokens) \(.postTokens)"')"
expect 'done: saved, with the lines between cursor and boundary' 'true 4' "$(field "$l" '"\(.saved) \(.cursorGap)"')"
expect 'done: version, kind, place from the project' '9.8.7 unknown local' "$(field "$l" '"\(.playbookVersion) \(.kind) \(.place)"')"
expect 'done: owner/repo from the origin' acme/widget "$(field "$l" '.repo')"
expect 'done: the boxes, carried and struck' '0 1 1' "$(field "$l" '.boxes.history | "\(.open) \(.carried) \(.struck)"')"
expect 'done: the hold counted' 1 "$(field "$l" '.lock.stopHolds')"
expect 'done: each need with its seconds' 'chat compact.restore' "$(field "$l" '.lock.needs | keys | join(" ")')"
expect 'done: seconds to free and freeAt are set' 'true true' "$(field "$l" '"\(.secondsToFree > 0) \(.freeAt | test("^20[0-9-]+T[0-9:]+Z$"))"')"
expect 'done: tokens after the boundary only, by kind' '30 300 3000 110' \
  "$(field "$l" '.tokens | "\(.input) \(.cacheWrite) \(.cacheRead) \(.output)"')"
expect 'done: no alarm' '[]' "$(field "$l" '.alarm | tostring')"
expect 'done: without the channel it stays local' 'false ["channel"]' "$(field "$l" '"\(.sent) \(.notChecked | tostring)"')"
check_not_contains 'done: no sentence of the history in the line' 'Bau fertig' "$l"
out="$(stop cut1 "$tx")"
expect 'done: the next turn end writes nothing more' 1 "$(cutline cut1 | grep -c .)"

# --- the verdict is the same with and without a report ---
tx="$fix/cut1b.jsonl"; fresh
{ human 'a'; cut auto 1 1; ans n1 1 1 1 1; } > "$tx"
v_plain="$(stop cut1b "$tx")"
printf 'cut=compact\nfrom=0\ntranscript=%s\nstopHolds=0\n' "$tx" > "$cs_gate/cut1b-cut-pending"
expect 'verdict: unchanged by a report' "$v_plain" "$(stop cut1b "$tx")"

# --- a helper's compaction: no marker, no line ---
tx="$fix/cut2.jsonl"; fresh
{ human 'Pruef das mit einem Helfer.'; call toolu_h1 Agent '{"description":"Pruefung","prompt":"x"}'; } > "$tx"
restore cut2 "$tx"
absent_file 'helper: no marker' "$cs_gate/cut2-cut-pending"
expect 'helper: no line' '' "$(cutline cut2)"

# --- one answer in three entries of one message.id: its usage counts once ---
tx="$fix/cut3.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut3 "$tx"
{ cut manual 5000 700; ans a1 1 10 100 1; ans a1 1 10 100 2; ans a1 1 10 100 3; ans a2 2 20 200 4; ans a2 2 20 200 5; ans a2 2 20 200 6; } >> "$tx"
read_all cut3; tick cut3
stop cut3 "$tx" > /dev/null
l="$(cutline cut3)"
expect 'message.id: each answer once, the last entry of it' '3 30 300 9' "$(field "$l" '.tokens | "\(.input) \(.cacheWrite) \(.cacheRead) \(.output)"')"
expect 'no save before the boundary: not-saved' 'false ["not-saved"]' "$(field "$l" '"\(.saved) \(.alarm | tostring)"')"

# --- a boundary the hook never saw: the next save writes it, hook none ---
tx="$fix/cut4.jsonl"; fresh
{ human 'Erst arbeiten.'; cut auto 170000 8000; summary 'S'; ans b1 1 1 1 1; said 'Weiter.'; } > "$tx"
out="$(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut4 bash "$ss" save --transcript "$tx" 2>&1)"
l="$(cutline cut4)"
expect 'silent: one line from save' 1 "$(grep -c . <<< "$l")"
expect 'silent: hook none, done false, the numbers of the boundary' 'none false auto 170000 8000' \
  "$(field "$l" '"\(.hook) \(.done) \(.trigger) \(.preTokens) \(.postTokens)"')"
expect 'silent: alarm silent-cut and not-saved' '["not-saved","silent-cut"]' "$(field "$l" '.alarm | tostring')"
expect 'silent: the state file keeps the last reported boundary' 2 "$(jq -r '.lastCutLine' "$proj/.agent/state/cut4.json" | tr -d '\r')"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut4 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'silent: a second run reports it no more' 1 "$(cutline cut4 | grep -c .)"
# A boundary in a helper's file never counts.
mkdir -p "${tx%.jsonl}/subagents"; { cut auto 1 1; } > "${tx%.jsonl}/subagents/agent-a1.jsonl"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut4 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'silent: a helper boundary is no cut' 1 "$(cutline cut4 | grep -c .)"
# A boundary marked isSidechain in the main file neither.
printf '%s\n' '{"uuid":"99999999-aaaa-4bbb-8ccc-dddddddddddd","timestamp":"2026-11-12T11:00:00.000Z","isSidechain":true,"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto"}}' >> "$tx"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut4 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'silent: a side-thread boundary is no cut' 1 "$(cutline cut4 | grep -c .)"

# --- three denials in one turn: the valve ---
tx="$fix/cut5.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut5 "$tx"
{ cut auto 9 9; denied t1 1; denied t2 2; denied t3 3; ans c1 1 1 1 1; } >> "$tx"
read_all cut5; tick cut5
stop cut5 "$tx" > /dev/null
l="$(cutline cut5)"
expect 'valve: three denials counted, valve true' '3 true' "$(field "$l" '"\(.lock.denials) \(.lock.valve)"')"
check_contains 'valve: the alarm names it' 'valve' "$(field "$l" '.alarm | tostring')"

# --- the further channel: a failure keeps the line, the next report sends it again ---
chan="$fix/cut-chan"; mkdir -p "$chan"
printf '#!/usr/bin/env bash\nexit 1\n' > "$chan/fail.sh"
# shellcheck disable=SC2016  # $1 and $2 belong to the stub script, written literally
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$1" "$2" >> "%s/got.txt"\n' "$chan" > "$chan/ok.sh"
tx="$fix/cut6.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut6 "$tx"
{ cut auto 7 7; ans d1 1 1 1 1; } >> "$tx"
read_all cut6; tick cut6
stop_in "$tx" false cut6 | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" PLAYBOOK_CARRIER_TEXT_CMD="bash $chan/fail.sh" bash "$stop" > /dev/null 2>&1
l="$(cutline cut6)"
expect 'channel fails: the line stays local, sent false, channel checked' 'false []' "$(field "$l" '"\(.sent) \(.notChecked | tostring)"')"
absent_file 'channel fails: the marker is dropped all the same' "$cs_gate/cut6-cut-pending"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut6 PLAYBOOK_CARRIER_TEXT_CMD="bash $chan/ok.sh" \
  bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'channel back: the line is sent true' true "$(field "$(cutline cut6)" '.sent')"
g="$(cat "$chan/got.txt" 2>/dev/null)"
check_contains 'channel back: the tool got report and the line' 'report {"v":1' "$g"
check_not_contains 'channel back: the line sent carries no sent field' '"sent"' "$g"
expect 'channel back: every unsent line went, each once' "$(grep -c '"sent":true' "$cuts")" "$(grep -c '^report ' <<< "$g")"

# --- the report over its time limit: the verdict stands, the marker stays ---
tx="$fix/cut7.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut7 "$tx"
{ cut auto 3 3; ans e1 1 1 1 1; } >> "$tx"
read_all cut7; tick cut7
slow="$fix/cut-slow"; mkdir -p "$slow"
printf '#!/usr/bin/env bash\nexit 124\n' > "$slow/timeout"; chmod +x "$slow/timeout"
out="$(stop cut7 "$tx" "$slow:$PATH")"
expect 'time limit: the turn end passes as before' '' "$out"
present_file 'time limit: the marker stays for the next turn end' "$cs_gate/cut7-cut-pending"
expect 'time limit: no line yet' '' "$(cutline cut7)"
stop cut7 "$tx" > /dev/null
expect 'time limit: the next turn end writes it' 1 "$(cutline cut7 | grep -c .)"

# --- a new compaction finds the old marker: its line with done false first ---
tx="$fix/cut8.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut8 "$tx"
{ cut auto 11 11; ans f1 1 1 1 1; said 'Weiter ohne Abhaken.'; } >> "$tx"
restore cut8 "$tx"
l="$(cutline cut8)"
expect 'undone: the old marker is a line done false' 'false ran null' "$(field "$l" '"\(.done) \(.hook) \(.freeAt)"')"
present_file 'undone: the new marker stands' "$cs_gate/cut8-cut-pending"
# save reports a standing marker as done false too
{ cut auto 12 12; ans f2 1 1 1 1; } >> "$tx"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut8 bash "$ss" save --transcript "$tx" > /dev/null 2>&1)
expect 'undone by save: a second line done false' 2 "$(cutline cut8 | jq -s 'map(select(.done == false)) | length' | tr -d '\r')"
absent_file 'undone by save: the marker is dropped' "$cs_gate/cut8-cut-pending"

# --- the transcript gone: a line that says so, no silent zero ---
printf 'cut=compact\nfrom=3\ntranscript=%s\nstopHolds=0\n' "$fix/no-such.jsonl" > "$cs_gate/cut9-cut-pending"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut9 bash "$ss" report > /dev/null 2>&1); rc=$?
expect 'unreadable: report ends with 0' 0 "$rc"
l="$(cutline cut9)"
expect 'unreadable: the alarm and what was not checked' '["transcript-unreadable"] ["channel","silent-cuts","transcript"]' \
  "$(field "$l" '"\(.alarm | tostring) \(.notChecked | tostring)"')"

# --- stopped by timeout mid-scan: the unmasked part of the transcript does not stay ---
tx="$fix/cut11.jsonl"; fresh
{ human 'los'; cut auto 100 10; ans t1 1 1 1 1; } > "$tx"
term="$fix/cut-term"; mkdir -p "$term"
# A jq that sends the report the TERM of `timeout` when the scan starts, and is the real one otherwise.
# shellcheck disable=SC2016 # the text of the stand-in script, expanded when it runs
printf '#!/usr/bin/env bash\ncase " $* " in *" live "*) kill -TERM "$(cat %q)"; exit 1 ;; esac\nexec %q "$@"\n' \
  "$term/pid" "$(command -v jq)" > "$term/jq"; chmod +x "$term/jq"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut11 PATH="$term:$PATH" \
  bash -c 'printf "%s" "$$" > "$1"; exec bash "$2" report --transcript "$3"' _ "$term/pid" "$ss" "$tx" > /dev/null 2>&1); rc=$?
expect 'timeout: the report ends on the TERM' 143 "$rc"
expect 'timeout: no part of the transcript stays' '' "$(ls "$cuts".part.* 2>/dev/null)"

# --- the marker's boundary: never one older than the marker, never one reported already ---
# from=0 (an empty transcript at the hook) and an earlier boundary in reach of the line slack.
tx="$fix/cut12.jsonl"; fresh
{ human 'los'; TX_TS=2026-11-12T09:00:00.000Z cut auto 100 10; ans d1 1 1 1 1; } > "$tx"
printf 'cut=compact\nat=2026-11-12T09:30:00Z\nfrom=0\ntranscript=%s\nstopHolds=0\n' "$tx" > "$cs_gate/cut12-cut-pending"
{ cut auto 200 20; ans d2 1 1 1 1; } >> "$tx"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut12 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'marker: an older boundary is not its own, it stays a silent cut' '200 none 100' \
  "$(cutline cut12 | jq -s -r '"\(map(select(.done))[0].preTokens) \(map(select(.done | not))[0].hook) \(map(select(.done | not))[0].preTokens)"' | tr -d '\r')"
# A marker without a time, the earlier boundary reported already.
tx="$fix/cut13.jsonl"; fresh
{ human 'los'; cut auto 100 10; ans e1 1 1 1 1; cut auto 200 20; ans e2 1 1 1 1; } > "$tx"
printf '%s\n' '{"lastCutUuid":"00000002-aaaa-4bbb-8ccc-dddddddddddd","lastCutLine":2}' > "$proj/.agent/state/cut13.json"
printf 'cut=compact\nfrom=0\ntranscript=%s\nstopHolds=0\n' "$tx" > "$cs_gate/cut13-cut-pending"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut13 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'marker: a reported boundary is not its own' '1 200 true' \
  "$(cutline cut13 | jq -s -r '"\(length) \(.[0].preTokens) \(.[0].done)"' | tr -d '\r')"

# --- the replay: one line per boundary from the transcript alone, nothing written ---
tx="$fix/cut10.jsonl"; fresh
{ human 'los'
  call s1 Bash '{"command":"bash .claude/hooks/session-state.sh save --carrier ww3d/playbook#487"}'
  result s1 'checked: 2026-11-12T1002Z · cursor: /x/cut10.jsonl L1 00000001-aaaa-4bbb-8ccc-dddddddddddd'
  cut auto 100 10
  line '"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:compact","stdout":"{\"systemMessage\":\"Restore written: x (3 lines, 0 open boxes)\"}"}'
  line '"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:compact","content":"Playbook 26.1.0 | Core\n+ AGENTS.md"}'
  denied r1 1; denied r2 2; denied r3 3
  ans g1 1 1 1 1
  cut manual 200 20
  line '"type":"attachment","attachment":{"type":"file","content":"Restore written: quoted in a file, no hook"}'
  call q1 Bash '{"command":"grep -n locked require-rule-read.sh"}'
  result q1 '221: After the compaction this session is locked ... Valve: denial 3 of 3 in this turn'
  ans g2 1 1 1 1
  cut auto 300 30
  line '"type":"attachment","attachment":{"type":"hook_system_message","hookName":"SessionStart:compact","content":"Compact state restored: x (3 lines)"}'
  call r4 Bash '{"command":"ls"}'
  line '"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r4","is_error":true,"content":"PreToolUse:Bash hook error: After the compaction this session is locked until it has read in full"}]}'
} > "$tx"
before="$(cat "$cuts")"
rp="$(TMPDIR="$cs_tmp" bash "$ss" report --replay "$tx" "$fix/no-such.jsonl" 2>/dev/null)"; rc=$?
expect 'replay: exit 0 with one readable transcript' 0 "$rc"
expect 'replay: one line per boundary' 3 "$(grep -c . <<< "$rp")"
r1="$(sed -n 1p <<< "$rp")"; r2="$(sed -n 2p <<< "$rp")"; r3="$(sed -n 3p <<< "$rp")"
expect 'replay: the save before the first boundary, its cursor gap' 'true 3' "$(field "$r1" '"\(.saved) \(.cursorGap)"')"
expect 'replay: the restore hook ran at the first' 'ran' "$(field "$r1" '.hook')"
expect 'replay: version from the receipt, session from the file' '26.1.0 cut10' "$(field "$r1" '"\(.playbookVersion) \(.session)"')"
expect 'replay: the first has the valve' '["valve"]' "$(field "$r1" '.alarm | tostring')"
expect 'replay: restore not checked' '["restore"]' "$(field "$r1" '.notChecked | tostring')"
expect 'replay: the second without save and hook, a quoted restore line is no hook' '["not-saved","silent-cut"]' "$(field "$r2" '.alarm | tostring')"
expect 'replay: a quoted lock text is no denial' 0 "$(field "$r2" '.lock.denials')"
expect 'replay: a denial with the harness prefix counts' 1 "$(field "$r3" '.lock.denials')"
expect 'replay: the restore line of before ww3d/playbook#620 counts as the hook' 'ran' "$(field "$r3" '.hook')"
expect 'replay: nothing written' "$before" "$(cat "$cuts")"
TMPDIR="$cs_tmp" bash "$ss" report --replay "$fix/no-such.jsonl" > /dev/null 2>&1; rc=$?
expect 'replay: exit 2 without a readable transcript' 2 "$rc"
rp="$(TMPDIR="$cs_tmp" CLAUDE_CODE_REMOTE=true bash "$ss" report --replay "$tx" "$tx" 2>/dev/null)"
expect 'replay: a cloud session is web in every transcript' web "$(jq -s -r 'map(.place) | unique | join(",")' <<< "$rp" | tr -d '\r')"

# --- a boundary without a line whose restore hook ran: hook ran, no silent cut ---
tx="$fix/cut14.jsonl"; fresh
{ human 'los'; TX_TS=2026-11-12T09:00:00.000Z cut auto 100 10
  line '"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:compact","stdout":"{\"systemMessage\":\"Restore written: x\"}"}'
  ans h1 1 1 1 1; } > "$tx"
printf 'cut=compact\nat=2026-11-12T09:30:00Z\nfrom=0\ntranscript=%s\nstopHolds=0\n' "$tx" > "$cs_gate/cut14-cut-pending"
{ cut auto 200 20; ans h2 1 1 1 1; } >> "$tx"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut14 bash "$ss" report --transcript "$tx" > /dev/null 2>&1)
expect 'restore trace: the earlier boundary ran, no silent-cut' 'ran false' \
  "$(cutline cut14 | jq -s -r 'map(select(.preTokens == 100))[0] | "\(.hook) \(.alarm | index("silent-cut") != null)"' | tr -d '\r')"

# --- without jq: a bare line for the marker, the marker gone ---
use_csnojq
printf 'cut=compact\nfrom=0\nstopHolds=0\n' > "$cs_gate/cut15-cut-pending"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" PATH="$csnojq" "$BASH" "$ss" report --session cut15 > /dev/null 2>&1); rc=$?
expect 'no jq: report ends with 0' 0 "$rc"
expect 'no jq: one bare line, jq not checked' '1 ["jq"] true' "$(cutline cut15 | jq -s -r '"\(length) \(.[0].notChecked | tostring) \(.[0].done)"' | tr -d '\r')"
absent_file 'no jq: the marker is dropped' "$cs_gate/cut15-cut-pending"

# --- the channel: each send under 10 s, the first failure ends the sending ---
tl="$fix/cut-timeout"; mkdir -p "$tl"
# shellcheck disable=SC2016 # the text of the stand-in script, expanded when it runs
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> %q\nexec %q "$@"\n' "$tl/log" "$(command -v timeout)" > "$tl/timeout"; chmod +x "$tl/timeout"
grep -q -F '"sent":false' "$cuts" && [ "$(grep -c -F '"sent":false' "$cuts")" -ge 2 ]; expect 'channel: two unsent lines to begin with' 0 "$?"
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut15 PATH="$tl:$PATH" PLAYBOOK_CARRIER_TEXT_CMD="bash $chan/fail.sh" \
  bash "$ss" report --transcript "$fix/cut1.jsonl" > /dev/null 2>&1)
expect 'channel: one try after a failure, under 10 s' '1 ok' "$(awk '{ n++; if ($1 >= 10) bad = 1 } END { print n + 0, (bad ? "over" : "ok") }' "$tl/log" 2>/dev/null)"
# A TERM while sending: the rewritten copy of the lines does not stay.
(cd "$proj" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=cut15 PLAYBOOK_CARRIER_TEXT_CMD="kill -TERM \$(cat $term/pid)" \
  bash -c 'printf "%s" "$$" > "$1"; exec bash "$2" report --transcript "$3"' _ "$term/pid" "$ss" "$fix/cut1.jsonl" > /dev/null 2>&1); rc=$?
expect 'channel: the report ends on the TERM' 143 "$rc"
expect 'channel: no copy of the lines stays' '' "$(ls "$cuts".tmp.* 2>/dev/null)"

# --- the Stop hook: a warned hold counts too, the report gets at most 10 s ---
tx="$fix/cut16.jsonl"; fresh
{ human 'los'; } > "$tx"
restore cut16 "$tx"
{ cut auto 5 5; ans k1 1 1 1 1; } >> "$tx"
stop_in "$tx" true cut16 | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" bash "$stop" > /dev/null 2>&1
check_line 'warned hold: counted in the marker' 'stopHolds=1' "$(cat "$cs_gate/cut16-cut-pending" 2>/dev/null)"
read_all cut16; tick cut16; : > "$tl/log"
stop cut16 "$tx" "$tl:$PATH" > /dev/null
expect 'time limit: the report runs under 10 s at most' '10' "$(head -n 1 "$tl/log" 2>/dev/null)"

# --- the channel: slow sends end at 8 s, each one taken is written at once, the rest waits ---
sl="$fix/cut-slowsend"; mkdir -p "$sl"
for k in 1 2 3 4 5; do printf '{"v":1,"session":"slow","boundaryUuid":"b%s","notChecked":[],"sent":false}\n' "$k"; done > "$sl/cuts.jsonl"
printf '5\n' > "$sl/clock"
# Each send takes 2.5 s on the stand-in clock and notes how many sends the file already holds.
# shellcheck disable=SC2016 # the text of the stand-in script, expanded when it runs
printf '#!/usr/bin/env bash\ngrep -c sent.:true %q >> %q\nprintf "%%s\\n" $(( $(cat %q) + 25 )) > %q\n' \
  "$sl/cuts.jsonl" "$sl/log" "$sl/clock" "$sl/clock" > "$sl/send.sh"
# shellcheck disable=SC2016 # the text of the driver script, expanded when it runs
printf '. %q\ncut_send "$1"\n' "$hooks/lib/cut.sh" > "$sl/run.sh"
slow_send() { PLAYBOOK_CUT_CLOCK="cat $sl/clock" PLAYBOOK_CARRIER_TEXT_CMD="bash $sl/send.sh" bash "$sl/run.sh" "$sl/cuts.jsonl"; }
slow_send; rc=$?
expect 'slow sends: the sending ends by itself at 8 s' 0 "$rc"
expect 'slow sends: three go before 8 s, two wait' '3 2' "$(grep -c '"sent":true' "$sl/cuts.jsonl") $(grep -c '"sent":false' "$sl/cuts.jsonl")"
expect 'slow sends: each send taken is in the file before the next starts' '0 1 2' "$(tr -d '\r' < "$sl/log" | paste -s -d ' ')"
printf '5\n' > "$sl/clock"; slow_send
expect 'slow sends: the next report sends the rest, nothing twice' '5 5' "$(grep -c '"sent":true' "$sl/cuts.jsonl") $(wc -l < "$sl/log" | tr -d ' ')"
# Another report appends its line while the first send runs: the line stays.
for k in 1 2; do printf '{"v":1,"session":"slow","boundaryUuid":"b%s","notChecked":[],"sent":false}\n' "$k"; done > "$sl/cuts.jsonl"
printf '5\n' > "$sl/clock"
# shellcheck disable=SC2016 # the text of the stand-in script, expanded when it runs
printf 'grep -q other %q || printf "%%s\\n" %q >> %q\n' "$sl/cuts.jsonl" '{"v":1,"session":"other","boundaryUuid":"o1","notChecked":[],"sent":false}' \
  "$sl/cuts.jsonl" > "$sl/send.sh"
slow_send
expect 'slow sends: a line appended meanwhile stays, the sent ones are marked' '1 2 3' \
  "$(grep -c '"session":"other"' "$sl/cuts.jsonl") $(grep -c '"sent":true' "$sl/cuts.jsonl") $(wc -l < "$sl/cuts.jsonl" | tr -d ' ')"

# --- the boxes: the proof is what follows the last arrow ---
bx="$fix/cut-boxes.md"
printf '## History without a carrier\n- [x] A -> https://x.example -> erledigt\n- [x] B -> ww3d/playbook#1\n' > "$bx"
expect 'boxes: an arrow and a link in the box text are no proof' '1 1' \
  "$( (. "$hooks/lib/cut.sh"; cut_boxes "$bx") | jq -r '.history | "\(.carried) \(.struck)"' | tr -d '\r')"


finish
