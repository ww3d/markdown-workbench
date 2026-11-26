#!/usr/bin/env bash
# Hook suite section: every successor is locked until it has read its predecessor (ww3d/playbook#727) - the start
# hook reads .agent/succession.json (the starting tool names the predecessor) and writes the
# restore file, the lock and the marker cut=switch through session-state.sh restore --succession; the check line counts
# only where it names one of the predecessor's transcripts, else the read starts at its bookmark, else at line 1;
# restore --none lifts the lock; /clear is a cut of its own (SessionEnd notes the session before it).
# Run alone: bash .claude/hooks/tests/cases/succession-start.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== restore-compact-state.sh at the start: the successor named by .agent/succession.json (ww3d/playbook#727) =="
ss="$hooks/session-state.sh"
proj="$fix/su-proj"; mkdir -p "$proj/.agents/rules" "$proj/.agent"
printf '# chat\n' > "$proj/.agents/rules/chat.md"
use_forge "$fix/su-forge"
cfg="$fix/su-cfg"; mkdir -p "$cfg/projects/p"
pw="$fix/su-pred-clone"; mkdir -p "$pw/.agent/state"

# The predecessor's run: a sentence before its save at L3, one between, one after the bookmark at L4.
pt="$fix/su-run-1.jsonl"; fresh
{
  human 'Bitte den Export Seidenreiher bauen.'
  said 'Ich baue den Export Seidenreiher.'
  said 'Gesichert.'
  human 'Auch den Albatros pruefen.'
  said 'Mache ich.'
  human 'Und vergiss den Kormoranflug-Bericht nicht.'
} > "$pt"
# A second run of the predecessor (a revive): one more sentence.
pt2="$fix/su-run-2.jsonl"; fresh
{ said 'Wieder da.'; human 'Dann noch der Pelikan-Abgleich.'; } > "$pt2"

su_file() { # task, transcripts... -> the succession file of the project
  local task="$1"; shift
  jq -n --arg t "$task" --arg w "$pw" '{v: 1, why: "succeeds", predecessor: {name: "dev-alt-1", id: "sess_alt1", kind: "dev"},
    task: (if $t == "" then null else $t end), transcripts: $ARGS.positional, workDir: $w}' --args "$@" > "$proj/.agent/succession.json"
}
su_event() { # session, source, [event name], [reason] -> a SessionStart (or SessionEnd) payload
  local s t
  js "$1"; s="$REPLY"; js "$fix/su-own-$1.jsonl"; t="$REPLY"
  printf '{"session_id":%s,"transcript_path":%s,"hook_event_name":"%s","source":"%s","reason":"%s"}' \
    "$s" "$t" "${3:-SessionStart}" "$2" "${4:-}"
}
su_start() { # session, [source], [event], [reason], [env assignments]... -> the hook's output
  local s="$1" src="${2:-startup}" ev="${3:-SessionStart}" why="${4:-}"
  shift; [ $# -eq 0 ] || shift; [ $# -eq 0 ] || shift; [ $# -eq 0 ] || shift
  [ -e "$fix/su-own-$s.jsonl" ] || { fresh; said 'Ich lese den Stand ein.' > "$fix/su-own-$s.jsonl"; }
  su_event "$s" "$src" "$ev" "$why" | env "$@" PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
    CLAUDE_CONFIG_DIR="$cfg" "$BASH" "$restore_cs" 2>&1
}
hand_back() { # check line -> the carrier's body with it in "## Hand-back"
  body ww3d_demo_9 "## Open points

- [ ] Bitte den Export Seidenreiher bauen.

## Hand-back

\`$1\`"
}
rf() { printf '%s/.agent/state/%s-restore.md' "$proj" "$1"; }
hist_of() { cs_sect 'History without a carrier' "$(rf "$1")"; }
valve_turns() { # session -> the verdict after three denials in one turn, then the one in the next turn
  local t="$fix/su-own-$1.jsonl"
  rm -f "$cs_gate/$1-compact-lock-denies"
  tx_n=50; human 'Weiter.' >> "$t"
  lk_verdict "$1" Bash > /dev/null; lk_verdict "$1" Bash > /dev/null; lk_verdict "$1" Bash > /dev/null
  printf '%s ' "$(lk_verdict "$1" Bash)"
  tx_n=55; human 'Und weiter.' >> "$t"
  lk_verdict "$1" Bash
}
own_line="checked: 2026-11-12T1003Z · cursor: $pt L3 00000003-aaaa-4bbb-8ccc-dddddddddddd"
foreign_line="checked: 2026-11-12T1003Z · cursor: /home/u/.claude/projects/x/other-session.jsonl L2 00000002-aaaa-4bbb-8ccc-dddddddddddd"

# --- the file stands, the check line of the predecessor counts: restore file, lock, marker; free once read ---
su_file ww3d/demo#9 "$pt"; hand_back "$own_line"
out="$(su_start n1)"
f="$(rf n1)"
present_file 'start: the successor has its restore file' "$f"
check_contains 'start: the hook says so' 'Restore after the switch written' "$out"
check_contains 'head: the check line taken and its section' "Check line taken: \`$own_line\` (section \"Hand-back\" of ww3d/demo#9)" "$(cat "$f")"
check_contains 'history: from the cursor of the check line' 'Since the cursor: cursor: after L3' "$(hist_of n1)"
check_contains 'history: a sentence after the cursor is a box' 'human: Auch den Albatros pruefen.' "$(hist_of n1)"
expect 'lock: the restore file and chat.md' '1 1' "$(lk_need n1 compact.restore) $(lk_need n1 chat)"
expect 'lock: a tool call is held before the read' LOCK "$(lk_verdict n1 Bash)"
check_line 'marker: cut=switch' 'cut=switch' "$(cat "$cs_gate/n1-cut-pending" 2>/dev/null)"
check_line 'marker: the predecessor by its name' 'predecessor=dev-alt-1' "$(cat "$cs_gate/n1-cut-pending" 2>/dev/null)"
present_file 'start: the file is marked as read for this session' "$proj/.agent/state/n1-succession.done"
expect 'valve: after three denials in a turn the next turn locks again' 'PASS LOCK' "$(valve_turns n1)"
rm -f "$cs_gate/n1-compact-lock-denies"
lk_read n1 "$f" '' "$proj"; lk_read n1 "$proj/.agents/rules/chat.md" '' "$proj"
expect 'lock: free once both are read in full' PASS "$(lk_verdict n1 Bash)"

# --- a second start of the same session: the file is not read again, no lock ---
before="$(cksum < "$f")"
out="$(su_start n1)"
expect 'again: the hook says nothing' '' "$out"
absent_file 'again: no lock' "$cs_gate/n1-compact-lock"
expect 'again: the restore file stays as it was' "$before" "$(cksum < "$f")"

# --- no file: no lock, nothing written ---
rm -f "$proj/.agent/succession.json"
out="$(su_start n2)"
expect 'no file: the hook says nothing' '' "$out"
absent_file 'no file: no lock' "$cs_gate/n2-compact-lock"
absent_file 'no file: no restore file' "$(rf n2)"

# --- a quoted check line of another session does not count: the read starts at the predecessor's bookmark ---
su_file ww3d/demo#9 "$pt"; hand_back "$foreign_line"
printf '{"cursor":{"transcript":"%s","line":4,"uuid":"00000004-aaaa-4bbb-8ccc-dddddddddddd"}}\n' "$pt" > "$pw/.agent/state/su-run-1.json"
su_start n3 > /dev/null
check_contains 'foreign line: it does not count, the head says why' 'No check line counts: none of the 1 at ww3d/demo#9 names a transcript of the predecessor (su-run-1)' "$(cat "$(rf n3)")"
check_contains 'foreign line: the read starts at the bookmark' "bookmark $pw/.agent/state/su-run-1.json: cursor: after L4" "$(hist_of n3)"
check_not_contains 'foreign line: a sentence before the bookmark is no box' 'Albatros' "$(hist_of n3)"
check_contains 'foreign line: a sentence after the bookmark is a box' 'Kormoranflug-Bericht' "$(hist_of n3)"
check_line 'foreign line: the marker says not saved' 'saved=false' "$(cat "$cs_gate/n3-cut-pending" 2>/dev/null)"

# --- the predecessor's own line outside "## Hand-back" counts ---
body ww3d_demo_9 "## Open points

- [ ] Stand: \`$own_line\`

## Hand-back

\`$foreign_line\`"
su_start n4 > /dev/null
check_contains "outside Hand-back: the predecessor's line counts, its section named" \
  "Check line taken: \`$own_line\` (section \"Open points\" of ww3d/demo#9)" "$(cat "$(rf n4)")"
check_contains 'outside Hand-back: the read starts at its cursor' 'Since the cursor: cursor: after L3' "$(hist_of n4)"

# --- two lines of the predecessor: the one in "## Hand-back" wins over a later one elsewhere ---
body ww3d_demo_9 "## Hand-back

\`$own_line\`

## Notes

\`${own_line/L3 00000003/L5 00000005}\`"
su_start n4b > /dev/null
check_contains 'both: the line in Hand-back is taken' "(section \"Hand-back\" of ww3d/demo#9)" "$(cat "$(rf n4b)")"
check_contains 'both: the read starts at its cursor' 'Since the cursor: cursor: after L3' "$(hist_of n4b)"

# --- without the file the search stays as it was: "## Hand-back" first, whoever wrote the line ---
body ww3d_demo_9 "## Open points

- [ ] Stand: \`$own_line\`

## Hand-back

\`$foreign_line\`"
fresh; said 'Ich lese.' > "$fix/su-own-n5.jsonl"
env PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CONFIG_DIR="$cfg" \
  "$BASH" "$ss" restore --from ww3d/demo#9 --session n5 --transcript "$fix/su-own-n5.jsonl" > /dev/null 2>&1
check_contains 'no file: the line in Hand-back is taken as before' 'other-session.jsonl is not on this machine' "$(hist_of n5)"

# --- no check line, no bookmark, no carrier: from line 1, the head says so; the read keeps its time limit ---
rm -f "$pw/.agent/state/su-run-1.json"
su_file 'label-without-carrier' "$pt"
su_start n6 > /dev/null
check_contains 'no carrier: the head says the task is no carrier' "No carrier: the task of the succession file \"label-without-carrier\" is no owner/repo#N" "$(cat "$(rf n6)")"
check_contains 'no carrier: no check line counts' 'No check line counts: no carrier to read it from.' "$(cat "$(rf n6)")"
check_contains 'no bookmark: from line 1, the line says so' 'no bookmark of the predecessor' "$(hist_of n6)"
check_contains 'no bookmark: a sentence of line 1 is a box' 'Seidenreiher' "$(hist_of n6)"
su_start n6b '' '' '' PLAYBOOK_RESTORE_READ_SECS=0.001 PLAYBOOK_RESTORE_TAIL_BYTES=400 > /dev/null
check_contains 'limit: a read over its time takes the last part, the line says so' 'the history before L' "$(hist_of n6b)"
check_not_contains 'limit: what lies before the last part is no box' 'Seidenreiher' "$(hist_of n6b)"

# --- two runs: from the bookmark in the first, the second read after it ---
printf '{"cursor":{"transcript":"%s","line":4,"uuid":"00000004-aaaa-4bbb-8ccc-dddddddddddd"}}\n' "$pt" > "$pw/.agent/state/su-run-1.json"
su_file ww3d/demo#9 "$pt" "$pt2"; hand_back "$foreign_line"
su_start n7 > /dev/null
check_contains 'runs: the second run is read after the first' 'Pelikan-Abgleich' "$(hist_of n7)"
check_contains 'runs: the line names both' 'its runs read as one' "$(hist_of n7)"
# The mark of the second run's last save with open boxes: its sentences are counted already (ww3d/playbook#727).
unexamined_of() { jq -r .ownUnexamined "$(sed -n 's/^List of this cut: \(.*\) - close its boxes there.*$/\1/p' "$(rf "$1")" \
  | tr -d '\r' | sed 's/md$/json/')" | tr -d '\r'; }
expect 'runs: without a mark the sentence of the second run counts' 1 "$(unexamined_of n7)"
mkdir -p "$pw/.agent/state/ticks/su-run-2"
jq -n --arg t "$pt2" '{transcript: $t, line: 2, uuid: "00000002-aaaa-4bbb-8ccc-dddddddddddd"}' \
  > "$pw/.agent/state/ticks/su-run-2/unexamined.json"
su_start n7b > /dev/null
expect "runs: what a run's mark covers is not counted again" 0 "$(unexamined_of n7b)"
rm -rf "$pw/.agent/state/ticks/su-run-2"

# --- no transcript readable: history unreadable, the report names predecessor-transcript ---
su_file ww3d/demo#9 "$fix/su-gone.jsonl"; hand_back "$foreign_line"
su_start n8 > /dev/null
check_line 'unreadable: the marker says so' 'history=unreadable' "$(cat "$cs_gate/n8-cut-pending" 2>/dev/null)"
check_contains 'unreadable: the history names the transcripts' "none of the predecessor's transcripts is readable" "$(hist_of n8)"

# --- restore --none lifts the lock of the switch; its reason stands in the report line ---
LK_INPUT='{"command":"bash .claude/hooks/session-state.sh restore --none \"stale file\""}' v="$(lk_verdict n8 Bash)"
expect 'none: a lone restore --none passes the lock' PASS "$v"
LK_INPUT='{"command":"bash .claude/hooks/session-state.sh restore --none \"x\" && rm -rf y"}' v="$(lk_verdict n8 Bash)"
expect 'none: chained to another command it is held' LOCK "$v"
env TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" "$BASH" "$ss" restore --none 'stale file' --session n8 \
  --transcript "$fix/su-own-n8.jsonl" > /dev/null 2>&1
expect 'none: exit 0' 0 "$?"
absent_file 'none: the lock is gone' "$cs_gate/n8-compact-lock"
absent_file 'none: the marker is gone' "$cs_gate/n8-cut-pending"
l="$(jq -c 'select(.session == "n8")' "$proj/.agent/state/cuts.jsonl" 2>/dev/null | tr -d '\r')"
expect 'none: one line, cut switch, the reason, predecessor-transcript not checked' '1 switch stale file true' \
  "$(grep -c . <<< "$l") $(jq -r '"\(.cut) \(.reason) \(.notChecked | index("predecessor-transcript") != null)"' <<< "$l" | tr -d '\r')"

# --- /clear: SessionEnd notes the session before it, the start after it reads that session's history ---
ct="$fix/su-own-c-old.jsonl"; fresh
{ human 'Bitte den Bericht Rohrdommel schreiben.'; said 'Gesichert.'; human 'Und den Austernfischer nicht vergessen.'; } > "$ct"
cs_state "$proj" c-old 2 2026-11-12T1002Z 2026-11-12T10:02:00Z
out="$(su_start c-old clear SessionEnd clear)"
expect 'clear: SessionEnd says nothing' '' "$out"
check_line 'clear: SessionEnd notes the session before it' 'session=c-old' "$(cat "$cs_gate/clear-from" 2>/dev/null)"
out="$(su_start c-new clear)"
f="$(rf c-new)"
present_file 'clear: the session after it has its restore file' "$f"
check_contains 'clear: the history from the cursor of the session before it' 'Austernfischer' "$(hist_of c-new)"
check_not_contains 'clear: a sentence before that cursor is no box' 'Rohrdommel' "$(hist_of c-new)"
check_line 'clear: the lock names its cut' 'cut=clear' "$(cat "$cs_gate/c-new-compact-lock" 2>/dev/null)"
check_not_contains 'clear: the lock carries no line count' 'from=' "$(cat "$cs_gate/c-new-compact-lock" 2>/dev/null)"
check_line 'clear: the marker cut=clear' 'cut=clear' "$(cat "$cs_gate/c-new-cut-pending" 2>/dev/null)"
check_line 'clear: the marker names the session before it' 'predecessor=c-old' "$(cat "$cs_gate/c-new-cut-pending" 2>/dev/null)"
absent_file 'clear: the note is used once' "$cs_gate/clear-from"
expect 'clear: held before the read' LOCK "$(lk_verdict c-new Bash)"
expect 'clear, valve: after three denials in a turn the next turn locks again' 'PASS LOCK' "$(valve_turns c-new)"
out="$(su_start c-lone clear SessionStart '' PLAYBOOK_CLEAR_WAIT_SECS=0)"
check_contains 'clear without a note: the restore says the session before it is not known' 'the session before /clear is not known' "$(cat "$(rf c-lone)")"
present_file 'clear without a note: the lock stands all the same' "$cs_gate/c-lone-compact-lock"

# --- /clear, the start before the end: the start waits for the note; a note of another project is left lying ---
other_note() { printf 'session=x-other\ntranscript=/elsewhere/x-other.jsonl\nat=%s\n' "$(date +%s)" > "$cs_gate/clear-from"; }
other_note
su_start e-new clear SessionStart '' PLAYBOOK_CLEAR_WAIT_SECS=0 > /dev/null
check_contains 'clear: a note of another project is not taken' 'the session before /clear is not known' "$(cat "$(rf e-new)")"
check_line 'clear: the note of another project stays' 'session=x-other' "$(cat "$cs_gate/clear-from" 2>/dev/null)"
dt="$fix/su-own-d-old.jsonl"; fresh
{ human 'Bitte die Liste Zwergtaucher abgleichen.'; said 'Gesichert.'; human 'Dann den Brachvogel melden.'; } > "$dt"
cs_state "$proj" d-old 2 2026-11-12T1002Z 2026-11-12T10:02:00Z
su_start d-new clear SessionStart '' PLAYBOOK_CLEAR_WAIT_SECS=60 > /dev/null &
d_pid=$!
su_start d-old clear SessionEnd clear > /dev/null
wait "$d_pid"
check_contains 'clear, the start before the end: the history of the session before it' 'Brachvogel' "$(hist_of d-new)"
check_line 'clear, the start before the end: the marker names the session before it' 'predecessor=d-old' \
  "$(cat "$cs_gate/d-new-cut-pending" 2>/dev/null)"

finish
