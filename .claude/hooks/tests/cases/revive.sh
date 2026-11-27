#!/usr/bin/env bash
# Hook suite section: the save after rc revive (lib/state.sh, state_revive; ww3d/playbook#727) - the session runs under
# a new id on a forked transcript and takes over the old id's cursor, check line, carriers and last list.
# Run alone: bash .claude/hooks/tests/cases/revive.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# No network and no real clock.
# shellcheck disable=SC2016 # jq text, not shell
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

r="$fix/revive"; st="$r/proj/.agent/state"; mkdir -p "$st"
export CLAUDE_PROJECT_DIR="$r/proj" TICKS_NOW="2026-11-25T19:00:00Z"
# shellcheck source=SCRIPTDIR/../../lib/state.sh
. "$hooks/lib/state.sh"
oid=0a0a0a0a-1111-4222-8333-444444444444; nid=0b0b0b0b-1111-4222-8333-444444444444
u() { printf '0000000%s-aaaa-4bbb-8ccc-dddddddddddd' "$1"; }

# The old id: a check line with its cursor at u3 and its last list, one box closed, one open.
jq -n --arg t "$r/old.jsonl" --arg u "$(u 3)" '{cursor: {transcript: $t, line: 900, uuid: $u}, checked: "2026-11-25T1820Z",
  checkedAt: "2026-11-25T18:20:00Z", checkLine: "checked: 2026-11-25T1820Z", carriers: ["o/r#1"], lastCutLine: 700}' > "$st/$oid.json"
d="$(cutlist_dir "$oid")"; mkdir -p "$d"
jq -n --arg o "$oid" '{title: "Save list", gate: "warn", cut: 4, holder: $o, sections: [], closedKeys: ["\($o):x1"],
  keys: ["\($o):k"], created: "2026-11-25T18:00:00Z",
  boxes: [{id: "K1", key: "\($o):a", title: "geschlossen", rule: "core", core: "a", kind: "promise"},
          {id: "K2", key: "\($o):b", title: "offen", rule: "core", core: "b", kind: "promise"}],
  journal: [{seq: 1, box: "K1", how: "set-aside", by: "tool", reason: "r", at: "2026-11-25T18:10:00Z"}]}' \
  | ticks_write "$d/cut-4.json"

# The forked transcript: a "derived-from" line, then the lines after the last compaction with the same uuid.
{ printf '{"type":"derived-from","v":1,"sessionId":"%s","sessions":[{"id":"%s","via":"compact"},{"id":"%s","via":"fork"}]}\n' \
    "$nid" "$oid" "$oid"
  for i in 2 3 4; do
    printf '{"type":"assistant","uuid":"%s","sessionId":"%s","message":{"content":[{"type":"text","text":"x"}]}}\n' "$(u "$i")" "$nid"
  done
} > "$r/new.jsonl"

state_revive "$st" "$nid" "$r/new.jsonl"; rc=$?
expect "revive: taken over from the old id" "0 $oid" "$rc $state_revived"
expect "revive: the cursor by uuid, no old line number" "$(u 3) null" \
  "$(jq -r '"\(.cursor.uuid) \(.cursor.line)"' "$st/$nid.json" | tr -d '\r')"
expect "  on the new transcript" "$(ticks_canon "$r/new.jsonl")" "$(ticks_canon "$(jq -r .cursor.transcript "$st/$nid.json" | tr -d '\r')")"
expect "revive: check line, carriers and the old id come along, the old cut line does not" \
  "checked: 2026-11-25T1820Z o/r#1 $oid null" \
  "$(jq -r '"\(.checkLine) \(.carriers | join(",")) \(.revivedFrom) \(.lastCutLine)"' "$st/$nid.json" | tr -d '\r')"
state_cursor "$st/$nid.json" "$r/new.jsonl"
expect "revive: the save starts behind the cursor in the new transcript" "4" "$state_start"
nv="$(cutlist_latest "$nid")"
expect "revive: the old last list is the new id's first, same number" "cut-4.md" "${nv##*/}"
expect "revive: holder and keys on the new id, the closed key too" "$nid $nid:a $nid:b $nid:x1 $nid:k" \
  "$(jq -r '"\(.holder) \([.boxes[].key] | join(" ")) \(.closedKeys | join(" ")) \(.keys | join(" "))"' "${nv%.md}.json" \
    | tr -d '\r')"
check_contains "revive: the open box stays open" "- [ ] K2 " "$(cat "$nv")"
check_not_contains "  the closed box is not open again" "- [ ] K1 " "$(cat "$nv")"
expect "revive: the old list stays with the old id" "$oid" "$(jq -r .holder "$d/cut-4.json" | tr -d '\r')"

# The old id saved only with open boxes: no state file, but its list and the mark of the counted reading.
o3=0f0a0a0a-1111-4222-8333-444444444444; n3=0f0b0b0b-1111-4222-8333-444444444444
d3="$(cutlist_dir "$o3")"; mkdir -p "$d3"
sed "s/$oid/$o3/g" "$d/cut-4.json" | ticks_write "$d3/cut-4.json"
jq -n --arg t "$r/old.jsonl" --arg u "$(u 3)" '{transcript: $t, line: 950, uuid: $u}' > "$(state_unexamined_mark "$st" "$o3")"
sed "s/$oid/$o3/g; s/$nid/$n3/g" "$r/new.jsonl" > "$r/n3.jsonl"
state_revive "$st" "$n3" "$r/n3.jsonl"; rc=$?
expect "revive without an old state file: the list comes along" "0 $o3 cut-4.md" "$rc $state_revived $(basename "$(cutlist_latest "$n3")")"
expect "  the mark comes along at the line of its uuid in the new transcript" "3 $(u 3)" \
  "$(jq -r '"\(.line) \(.uuid)"' "$(state_unexamined_mark "$st" "$n3")" | tr -d '\r')"
expect "  and counts from there" 3 "$(state_unexamined_from "$(state_unexamined_mark "$st" "$n3")" "$r/n3.jsonl")"

# The old id had no cursor (its last save ended with open boxes): the save names the takeover once, not at each save.
o2=0d0d0d0d-1111-4222-8333-444444444444; n2=0e0e0e0e-1111-4222-8333-444444444444
jq -n '{cursor: null, checkLine: "checked: 2026-11-25T1700Z", carriers: []}' > "$st/$o2.json"
sed "s/$oid/$o2/g; s/$nid/$n2/g" "$r/new.jsonl" > "$r/n2.jsonl"
save2() { bash "$hooks/session-state.sh" save --transcript "$r/n2.jsonl" --session "$n2" 2>&1; }
check_contains "revive: the first save names the takeover" "revived from $o2" "$(save2)"
check_not_contains "  a later save does not name it again" "revived from" "$(save2)"

# A second save of the new id: its own cursor stands, nothing is taken over again.
jq --arg u "$(u 4)" '.cursor.uuid = $u' "$st/$nid.json" > "$st/x" && mv "$st/x" "$st/$nid.json"
state_revive "$st" "$nid" "$r/new.jsonl"
expect "revive: a session with its own cursor takes nothing over" "" "$state_revived"
expect "  its cursor stays" "$(u 4)" "$(jq -r .cursor.uuid "$st/$nid.json" | tr -d '\r')"

# A transcript without "derived-from" (a fresh session, a compaction): nothing to take over.
other=0c0c0c0c-1111-4222-8333-444444444444
printf '{"type":"assistant","uuid":"%s","message":{"content":[]}}\n' "$(u 2)" > "$r/fresh.jsonl"
state_revive "$st" "$other" "$r/fresh.jsonl"; rc=$?
expect "revive: without derived-from nothing is written" "0  no" \
  "$rc $state_revived $([ -e "$st/$other.json" ] && echo yes || echo no)"


# --- the report after rc revive and what the fork did not copy (ww3d/playbook#750) ---
# The template: the head of a real forked transcript, texts masked; its boundary is line 13.
head_tx="$here/fixtures/revive-fork-head.jsonl"
fold="$(jq -r 'select(.type == "derived-from") | .sessions[-1].id' "$head_tx" | tr -d '\r')"
buid="$(jq -r 'select(.subtype == "compact_boundary") | .uuid' "$head_tx" | tr -d '\r')"
fnew=01a21992-86f4-738a-8751-168b031e33eb
export CLAUDE_PROJECT_DIR="$r/fork" TMPDIR="$r/tmp"; fst="$r/fork/.agent/state"; mkdir -p "$fst" "$TMPDIR"
entry() { printf '{"type":"assistant","uuid":"%s","timestamp":"2026-11-26T01:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}\n' "$1"; }
{ entry "$(u 1)"; entry "$(u 2)"; sed -n '13,20p' "$head_tx"; } > "$r/$fold.jsonl"
{ cat "$head_tx"; for i in $(seq 10 34); do entry "000000$i-aaaa-4bbb-8ccc-dddddddddddd"; done; } > "$r/$fnew.jsonl"
jq -n --arg t "$r/$fold.jsonl" --arg u "$(u 1)" --arg b "$buid" \
  '{cursor: {transcript: $t, uuid: $u}, carriers: [], lastCutUuid: $b, lastCutLine: 3}' > "$fst/$fold.json"

state_revive "$fst" "$fnew" "$r/$fnew.jsonl"
expect "fork: the last reported boundary comes along at the line of its uuid in the new transcript" "$buid 13" \
  "$(jq -r '"\(.lastCutUuid) \(.lastCutLine)"' "$fst/$fnew.json" | tr -d '\r')"
state_cursor "$fst/$fnew.json" "$r/$fnew.jsonl"
expect "fork: a cursor before the forked part is said, the start is behind the boundary" \
  "14 cursor before the forked part (old L1): after the compaction boundary L13, covered by the restore of $fold" \
  "$state_start $state_start_note"
state_cursor "$fst/$fnew.json" "$r/$fnew.jsonl" 1
expect "fork: after a restore that did not run to its end the start stays at line 1" \
  "1 cursor before the forked part (old L1): from line 1" "$state_start $state_start_note"
mkdir -p "$r/w"
expect "fork: an old run without lines after the fork gives no box" "" \
  "$(state_fork_tail "$fst" "$fst/$fnew.json" "$r/$fnew.jsonl" "$r/w")"
{ entry "$(u 7)"; entry "$(u 8)"; } >> "$r/$fold.jsonl"
tail_box="$(state_fork_tail "$fst" "$fst/$fnew.json" "$r/$fnew.jsonl" "$r/w")"
check_contains "fork: an old run that wrote on gives a box with its lines" \
  "Lauf $fold hat nach dem Fork weitergeschrieben (alt L11-L12): bash .claude/hooks/session-state.sh save --transcript" \
  "$(jq -r .text <<< "$tail_box")"
check_contains "  and the call names the old session" "--session $fold" "$(jq -r .text <<< "$tail_box")"
jq --arg u "$(u 8)" '.cursor.uuid = $u' "$fst/$fold.json" > "$r/x" && cp "$r/x" "$r/old-saved.json"
cp "$fst/$fold.json" "$r/old-before.json"; cp "$r/old-saved.json" "$fst/$fold.json"
expect "fork: an old run a save of its own read to its end gives none" "" \
  "$(state_fork_tail "$fst" "$fst/$fnew.json" "$r/$fnew.jsonl" "$r/w")"
cp "$r/old-before.json" "$fst/$fold.json"; rm -f "$fst/$fnew.json"

# The save: the copied boundary is reported already, so it writes no line for it; the box stands in its work list.
printf '{"v":1,"session":"%s","cut":"compact","boundaryUuid":"%s","hook":"ran","sent":true}\n' "$fold" "$buid" > "$fst/cuts.jsonl"
bash "$hooks/session-state.sh" save --transcript "$r/$fnew.jsonl" --session "$fnew" > "$r/save.log" 2>&1
expect "fork: the save writes no line for the copied boundary" 1 "$(grep -c -F "\"boundaryUuid\":\"$buid\"" "$fst/cuts.jsonl")"
check_not_contains "  a save without a marker says nothing of one" "cut-pending" "$(cat "$r/save.log")"
check_not_contains "  and none as a silent cut" 'silent-cut' "$(cat "$fst/cuts.jsonl")"
check_contains "fork: the save's work list holds the box" "hat nach dem Fork weitergeschrieben" "$(cat "$fst/$fnew-save.md" 2>/dev/null)"
# Without the old state's mark the boundary still counts once: one line a boundary, whatever the session.
rm -f "$fst/$fnew".json "$fst/$fnew"-*; jq 'del(.lastCutUuid, .lastCutLine)' "$r/old-before.json" > "$fst/$fold.json"
bash "$hooks/session-state.sh" save --transcript "$r/$fnew.jsonl" --session "$fnew" > "$r/save.log" 2>&1
expect "fork: without that mark the boundary stands once too" 1 "$(grep -c -F "\"boundaryUuid\":\"$buid\"" "$fst/cuts.jsonl")"

# --- the old run's restore never ended: no restore and no save read its lines before the copied boundary ---
om="$TMPDIR/claude-rule-gate/$fold-cut-pending"; mkdir -p "${om%/*}"
unsaved() { rm -rf "$fst/$fnew".json "$fst/$fnew"-* "$fst/ticks/$fnew" "$om" "$fst/$fold-restore.md"; cp "$r/old-before.json" "$fst/$fold.json"; }
fsave() { bash "$hooks/session-state.sh" save --transcript "$r/$fnew.jsonl" --session "$fnew" > "$r/save.log" 2>&1; }
gap="Restore von Lauf $fold lief nicht zu Ende (alt L2-L3): bash .claude/hooks/session-state.sh save --transcript"
unsaved; printf 'cut=compact\nat=2026-11-26T00:59:00Z\nrestore=pending\nstopHolds=0\n' > "$om"; fsave
check_contains "fork, old restore pending: the start holds and the note says why" \
  "from line 1, the restore of $fold did not finish" "$(cat "$r/save.log")"
check_contains "  the work list names the old lines" "$gap" "$(cat "$fst/$fnew-save.md" 2>/dev/null)"
check_contains "  and the save over the old session" "--session $fold" "$(grep -F 'lief nicht zu Ende' "$fst/$fnew-save.md" 2>/dev/null)"
unsaved; printf '## History without a carrier\n\n- [ ] K1 Restore unvollstaendig (Frist 75 s): L2-L3 nicht abgeglichen\n' \
  > "$fst/$fold-restore.md"; fsave
check_contains "fork, old restore with its box open: the work list names the old lines" "$gap" \
  "$(cat "$fst/$fnew-save.md" 2>/dev/null)"
unsaved; jq 'del(.lastCutUuid, .lastCutLine)' "$r/old-before.json" > "$fst/$fold.json"; : > "$fst/cuts.jsonl"
printf 'cut=compact\nat=2026-11-26T19:00:00Z\nfrom=2\nrestore=pending\nstopHolds=0\n' > "$om"; fsave
expect "fork, old restore pending: the copied boundary is named restore-incomplete, once, not silent" "1 true false" \
  "$(jq -rs --arg b "$buid" 'map(select(.boundaryUuid == $b)) | "\(length) \(.[0].alarm | index("restore-incomplete") != null) \(.[0].alarm | index("silent-cut") != null)"' "$fst/cuts.jsonl" | tr -d '\r')"
absent_file "  and the old marker is gone" "$om"
unsaved; : > "$fst/cuts.jsonl"; fsave
check_not_contains "fork: the takeover comes before the report, so a boundary the old id reported gets no line" \
  "$buid" "$(cat "$fst/cuts.jsonl")"
unsaved; fsave
check_not_contains "fork, old restore at its end: no such box" "lief nicht zu Ende" "$(cat "$fst/$fnew-save.md" 2>/dev/null)"
check_not_contains "  and no such note" "did not finish" "$(cat "$r/save.log")"

finish
