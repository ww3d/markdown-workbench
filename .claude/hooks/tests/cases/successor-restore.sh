#!/usr/bin/env bash
# Hook suite section: EINLESEN of a successor after a switch (ww3d/playbook#487, #485) - session-state.sh restore
# --from reads the predecessor's check line at its carrier, writes the restore file from the predecessor's
# transcript after its cursor, the carriers changed since then and its open posts, and leaves the lock and the
# marker cut=switch, which require-receipt.sh turns into the report line.
# Run alone: bash .claude/hooks/tests/cases/successor-restore.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== session-state.sh restore --from: the successor after a switch (ww3d/playbook#487) =="
ss="$hooks/session-state.sh"
proj="$fix/sr-proj"; mkdir -p "$proj/.agents/rules"
printf '# chat\n' > "$proj/.agents/rules/chat.md"
use_forge "$fix/sr-forge"
cfg="$fix/sr-cfg"; mkdir -p "$cfg/projects/p"
posts_cmd="$fix/sr-posts.sh"
# The session tool's stand-in: open posts of the session it is asked about, nothing else.
cat > "$posts_cmd" <<'EOF'
case "$1" in posts) printf '%s\n' "- Antwort an ctrl-x zu #12 steht aus ($2)" "- Auftrag: Welle nach dem Release" ;; esac
exit 0
EOF
sr_run() { # successor session, [extra env assignment] -> the command's output
  local s="$1"; shift
  env "$@" PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CONFIG_DIR="$cfg" \
    "$BASH" "$ss" restore --from ww3d/demo#9 --session "$s" --transcript "$fix/sr-own-$s.jsonl" 2>&1
}
since() { printf '%s\n' "$2" > "$forge/since-$1.json"; }
hand_back() { # check line -> the carrier's body with it in "## Hand-back"
  body ww3d_demo_9 "## Open points

- [ ] Bitte den Export Seidenreiher bauen.

## Hand-back

Check 2026-11-12T1004Z · ctrl-demo-3 · 1 Punkt getragen

\`$1\`

Rotation ready: ctrl-demo-4"
}
own() { fresh; said 'Ich lese den Stand ein.' > "$fix/sr-own-$1.jsonl"; } # successor -> its own short transcript

# --- the predecessor: saved at L3, then a sentence of the maintainer, a message and a helper result
#     no carrier holds ---
pt="$fix/sr-pred-1.jsonl"; fresh
{
  human 'Bitte den Export Seidenreiher bauen.'
  said 'Ich baue den Export Seidenreiher.'
  said 'Gesichert.'
  TX_TS=2026-11-12T10:04:00.000Z call toolu_hb Bash '{"command":"gh issue edit 9 --repo ww3d/demo --body-file hb.md"}'
  TX_TS=2026-11-12T10:04:00.000Z result toolu_hb 'https://github.com/ww3d/demo/issues/9'
  human 'Und vergiss den Kormoranflug-Bericht nicht.'
  peer ctrl-x 'Die Welle Fischadler ist durch.'
  agent toolu_a1 'Befund: der Lauf Sturmtaucher ist rot.'
} > "$pt"
hand_back "checked: 2026-11-12T1003Z · cursor: $pt L3 00000003-aaaa-4bbb-8ccc-dddddddddddd"
since ww3d_demo '[{"number":9,"title":"Export Seidenreiher","updated_at":"2026-11-12T10:30:00Z"}]'
printf '%s\n' '[{"created_at":"2026-11-12T10:04:00Z","updated_at":"2026-11-12T10:04:00Z"},
 {"created_at":"2026-11-12T10:30:00Z","updated_at":"2026-11-12T10:30:00Z"}]' > "$forge/comments-ww3d_demo_9.json"
own s1
out="$(sr_run s1)"; rc=$?; f="$proj/.agent/state/s1-restore.md"
expect 'restore: exit 0 where the file is written' 0 "$rc"
present_file 'restore: the successor has its restore file' "$f"
expect 'restore: the eight sections in their order' \
  "Step and todos|Rule files to reread|History without a carrier|Carriers changed since checked|The maintainer's sentences since the cursor|Messages of other sessions since the cursor|Helper results since the cursor|Tool additions" \
  "$(sed -n 's/^## //p' "$f" | paste -sd '|')"
hist="$(cs_sect 'History without a carrier' "$f")"
check_contains "history: the predecessor's uncarried sentence after its save is an open box" \
  '- [ ] L6 2026-11-12T1006Z human: Und vergiss den Kormoranflug-Bericht nicht.' "$hist"
check_not_contains 'history: what the carrier holds is no box' 'Seidenreiher' "$hist"
check_contains 'history: the start is the cursor of the check line' 'Since the cursor: cursor: after L3' "$hist"
check_contains 'verbatim: the sentence of the maintainer after the cursor' 'Kormoranflug-Bericht' \
  "$(cs_sect "The maintainer's sentences since the cursor" "$f")"
check_not_contains 'verbatim: a sentence before the cursor is not there' 'Seidenreiher' \
  "$(cs_sect "The maintainer's sentences since the cursor" "$f")"
check_contains 'verbatim: the message names its sender' '### L7 2026-11-12T1007Z ctrl-x' "$(cs_sect 'Messages of other sessions since the cursor' "$f")"
check_contains 'verbatim: the helper result' 'Sturmtaucher' "$(cs_sect 'Helper results since the cursor' "$f")"
cc="$(cs_sect 'Carriers changed since checked' "$f")"
check_contains 'changed: since the check line of the predecessor' 'Since 2026-11-12T1003Z (checkedAt 2026-11-12T10:03:00Z)' "$cc"
check_line "changed: another hand's change is a box, the predecessor's own hand-back write is none" \
  '- [ ] ww3d/demo#9 changed since 2026-11-12T10:03:00Z: Export Seidenreiher (changes at 2026-11-12T10:30:00Z)' "$cc"
check_contains 'posts: without the session tool not checked' 'open posts: not checked' "$hist"
check_contains 'step: from the predecessor' 'Step: ' "$(cs_sect 'Step and todos' "$f")"
check_contains 'output: names the file and its open boxes' 'open boxes)' "$out"

# The lock: both needs, no line count (no boundary follows a switch, so no net drops it); held until both are read.
lock="$cs_gate/s1-compact-lock"
expect 'lock: the restore file and chat.md are its needs' '1 1' "$(lk_need s1 compact.restore) $(lk_need s1 chat)"
check_not_contains 'lock: no line count, no transcript - the helper net does not apply' 'from=' "$(cat "$lock")"
expect 'lock: a tool call is held before the read' LOCK "$(lk_verdict s1 Bash)"
expect 'lock: a sub-agent is free' PASS "$(lk_verdict s1 Bash agent-1)"
rm -f "$cs_gate/s1-compact-lock-denies"
lk_read s1 "$f" '' "$proj"; lk_read s1 "$proj/.agents/rules/chat.md" '' "$proj"
expect 'lock: free once both are read in full' PASS "$(lk_verdict s1 Bash)"

# The marker and the report line of the switch.
mk="$cs_gate/s1-cut-pending"
check_line 'marker: cut=switch' 'cut=switch' "$(cat "$mk" 2>/dev/null)"
check_line 'marker: the predecessor from its transcript' 'predecessor=sr-pred-1' "$(cat "$mk" 2>/dev/null)"
check_line 'marker: saved, the check line named a cursor' 'saved=true' "$(cat "$mk" 2>/dev/null)"
o_held="$(stop_in "$fix/sr-own-s1.jsonl" false s1 | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" bash "$stop" 2>&1)"
check_contains 'turn end: held while a box is open' '"decision":"block"' "$o_held"
check_line 'turn end: the hold is counted in the marker' 'stopHolds=1' "$(cat "$mk" 2>/dev/null)"
sed -i 's/^- \[ \] \(.*\)$/- [x] \1 -> ww3d\/demo#9/' "$f"
out="$(stop_in "$fix/sr-own-s1.jsonl" false s1 | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" bash "$stop" 2>&1)"
expect 'turn end: passes once read and settled' '' "$out"
absent_file 'report: the marker is dropped after the line' "$mk"
l="$(jq -c 'select(.session == "s1")' "$proj/.agent/state/cuts.jsonl" 2>/dev/null | tr -d '\r')"
expect 'report: one line, cut switch, done, predecessor' '1 switch true sr-pred-1' \
  "$(grep -c . <<< "$l") $(jq -r '"\(.cut) \(.done) \(.predecessor)"' <<< "$l" | tr -d '\r')"
expect 'report: saved, no alarm, no boundary' 'true [] null' "$(jq -c -r '"\(.saved) \(.alarm) \(.boundaryUuid)"' <<< "$l" | tr -d '\r')"
expect 'report: the boxes carried, the hold counted' '3 1' "$(jq -r '"\(.boxes.history.carried) \(.lock.stopHolds)"' <<< "$l" | tr -d '\r')"

# --- the session tool names the predecessor's open posts: each a box ---
own s2
out="$(sr_run s2 PLAYBOOK_CARRIER_TEXT_CMD="bash $posts_cmd")"; rc=$?; f="$proj/.agent/state/s2-restore.md"
hist="$(cs_sect 'History without a carrier' "$f")"
check_line 'posts: an open answer of the predecessor is a box' '- [ ] post: Antwort an ctrl-x zu #12 steht aus (sr-pred-1)' "$hist"
check_line 'posts: an open order is a box' '- [ ] post: Auftrag: Welle nach dem Release' "$hist"

# --predecessor names the session the tool is asked about; without it, the id of the transcript.
own s2p
env PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CONFIG_DIR="$cfg" \
  PLAYBOOK_CARRIER_TEXT_CMD="bash $posts_cmd" "$BASH" "$ss" restore --from ww3d/demo#9 --predecessor ctrl-alt-7 \
  --session s2p --transcript "$fix/sr-own-s2p.jsonl" >/dev/null 2>&1
check_line 'posts: --predecessor is the name the tool is asked about' \
  '- [ ] post: Antwort an ctrl-x zu #12 steht aus (ctrl-alt-7)' "$(cs_sect 'History without a carrier' "$proj/.agent/state/s2p-restore.md")"

# A failing session tool: its error text is no box, only "not checked" stands.
fail_cmd="$fix/sr-posts-fail.sh"
# shellcheck disable=SC2016 # the stand-in's own script text, expanded when it runs
printf '%s\n' 'case "$1" in posts) echo "rc: unknown verb posts" >&2; exit 3 ;; esac' > "$fail_cmd"
own s2f
out="$(sr_run s2f PLAYBOOK_CARRIER_TEXT_CMD="bash $fail_cmd")"; f="$proj/.agent/state/s2f-restore.md"
hist="$(cs_sect 'History without a carrier' "$f")"
check_not_contains 'posts: a failed call makes no box of its error text' 'post: rc: unknown verb' "$hist"
check_contains 'posts: a failed call stands as not checked' 'open posts: not checked (PLAYBOOK_CARRIER_TEXT_CMD posts failed, exit 3)' "$hist"

# --- a web predecessor: its transcript is not on this machine; the changed carriers still stand ---
hand_back 'checked: 2026-11-12T1003Z · cursor: /home/user/.claude/projects/-home-user-demo/web-77.jsonl L40 00000040-aaaa-4bbb-8ccc-dddddddddddd'
own s3
out="$(sr_run s3)"; rc=$?; f="$proj/.agent/state/s3-restore.md"
expect 'web: exit 0, the file names what it could not read' 0 "$rc"
hist="$(cs_sect 'History without a carrier' "$f")"
check_contains 'web: the history says the transcript is not on this machine' 'is not on this machine' "$hist"
check_contains 'web: the changed carriers stand all the same' '- [ ] ww3d/demo#9 changed since' "$(cs_sect 'Carriers changed since checked' "$f")"
for h in "The maintainer's sentences since the cursor" 'Messages of other sessions since the cursor' 'Helper results since the cursor'; do
  check_contains "web: '$h' says not readable" '_not readable: ' "$(cs_sect "$h" "$f")"
done
check_line 'web: the marker says the history was not read' 'history=unreadable' "$(cat "$cs_gate/s3-cut-pending" 2>/dev/null)"
# The same id under this machine's projects folder is found there.
cp "$pt" "$cfg/projects/p/web-77.jsonl"
own s3b
out="$(sr_run s3b)"; rc=$?; f="$proj/.agent/state/s3b-restore.md"
check_not_contains 'web: the id under the projects folder is read instead' 'is not on this machine' "$(cs_sect 'History without a carrier' "$f")"

# --- no check line: the predecessor did not save; the report carries not-saved ---
body ww3d_demo_9 '## Hand-back

Rotation ready: ctrl-demo-4'
own s4
out="$(sr_run s4)"; rc=$?; f="$proj/.agent/state/s4-restore.md"
check_contains 'unsaved: the history names the missing check line' 'no check line at ww3d/demo#9' "$(cs_sect 'History without a carrier' "$f")"
check_line 'unsaved: the marker says not saved' 'saved=false' "$(cat "$cs_gate/s4-cut-pending" 2>/dev/null)"
lk_read s4 "$f" '' "$proj"; lk_read s4 "$proj/.agents/rules/chat.md" '' "$proj"
stop_in "$fix/sr-own-s4.jsonl" false s4 | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" bash "$stop" >/dev/null 2>&1
l="$(jq -c 'select(.session == "s4")' "$proj/.agent/state/cuts.jsonl" 2>/dev/null | tr -d '\r')"
expect 'unsaved: the line carries the alarm not-saved' '["not-saved"]' "$(jq -c '.alarm' <<< "$l" | tr -d '\r')"

# --- errors: a carrier that cannot be read, a missing --from ---
out="$(env PATH="$forge_bin:$PATH" SS_FORGE="$fix/sr-none" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  "$BASH" "$ss" restore --from ww3d/demo#404 --session s5 2>&1)"
expect 'error: an unreadable carrier is exit 2' 2 "$?"
check_contains 'error: it names the carrier' 'carrier not readable: ww3d/demo#404' "$out"
absent_file 'error: no lock without a restore file' "$cs_gate/s5-compact-lock"
"$BASH" "$ss" restore --session s6 >/dev/null 2>&1
expect 'error: restore without --from is exit 2' 2 "$?"

finish
