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

finish
