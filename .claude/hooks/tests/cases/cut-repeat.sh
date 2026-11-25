#!/usr/bin/env bash
# Hook suite section: what the report of a cut counts when the same stretch is read again, and the keys of a long
# history (lib/state.sh, lib/cut.sh; ww3d/playbook#727).
# Run alone: bash .claude/hooks/tests/cases/cut-repeat.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# No network and no real clock.
# shellcheck disable=SC2016 # jq text, not shell
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

r="$fix/cut-repeat"; p="$r/proj"; st="$p/.agent/state"; mkdir -p "$st" "$r/match"
export CLAUDE_PROJECT_DIR="$p" TICKS_NOW="2026-11-25T20:00:00Z"
unset PLAYBOOK_CARRIER_TEXT_CMD
# shellcheck source=SCRIPTDIR/../../lib/state.sh
. "$hooks/lib/state.sh"
# shellcheck source=SCRIPTDIR/../../lib/cut.sh
. "$hooks/lib/cut.sh"
sid=0f0f0f0f-1111-4222-8333-444444444444; sf="$(state_unexamined_mark "$st" "$sid")"
said() { printf '{"type":"assistant","uuid":"%08d-aaaa-4bbb-8ccc-dddddddddddd","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2"; }
unexamined() { # transcript
  state_extract "$1" 1 "$(state_unexamined_from "$sf" "$1")" > "$r/cand.jsonl" && state_unexamined_new "$r/cand.jsonl" "$sf" "$1"
}

echo "== the report counts each unexamined sentence once =="
{ said 1 "Das Wetter ist klar. Der Wind steht still."; said 2 "Die Strasse ist nass."; } > "$r/t.jsonl"
expect "unexamined: the first report counts every sentence of the reading" 3 "$(unexamined "$r/t.jsonl")"
expect "  the same stretch read again (a save with open boxes, a compaction) counts none" 0 "$(unexamined "$r/t.jsonl")"
said 3 "Der Zug faehrt spaet." >> "$r/t.jsonl"
expect "  a reading that grew counts only its new lines" 1 "$(unexamined "$r/t.jsonl")"
expect "  the mark lies beside the cut lists and writes no state file" "1:0" \
  "$([ -f "$st/ticks/$sid/unexamined.json" ] && echo 1 || echo 0):$([ -f "$st/$sid.json" ] && echo 1 || echo 0)"
unexamined "$r/t.jsonl" > /dev/null
expect "  the mark names the uuid of its line, also after a reading with nothing new" "3 00000003-aaaa-4bbb-8ccc-dddddddddddd" \
  "$(jq -r '"\(.line) \(.uuid)"' "$sf" | tr -d '\r')"
cp "$r/t.jsonl" "$r/t2.jsonl"
expect "  another transcript (after rc revive) counts from its start" 4 "$(unexamined "$r/t2.jsonl")"
printf 'not json' > "$st/bad.json"
state_extract "$r/t.jsonl" 1 "$(state_unexamined_from "$st/bad.json" "$r/t.jsonl")" > "$r/cand.jsonl"
expect "  an unreadable mark counts the whole reading" 4 "$(state_unexamined_new "$r/cand.jsonl" "$st/bad.json" "$r/t.jsonl")"
expect "  a reading without the line (an older caller) counts all of it" 4 \
  "$(state_extract "$r/t.jsonl" 1 > "$r/cand.jsonl"; state_unexamined_new "$r/cand.jsonl" "$st/none.json" "$r/t.jsonl")"

echo "== the count of sentences =="
{ said 1 'Eins. Zwei!  Drei.\n\nVier.\t Fuenf  \n'; said 2 '  Sechs.  '; said 3 ' \n\t '; said 4 '. Sieben'; } > "$r/s.jsonl"
expect "unexamined: runs of space, tabs and lines split once, space alone and a leading mark add none" 8 \
  "$(state_extract "$r/s.jsonl" 1 | jq -s '[.[] | select(has("end"))][0].unexamined')"

echo "== the answer to an input is the last own text before the next input =="
{ printf '{"type":"user","uuid":"u1","message":{"content":"Wie spaet ist es"}}\n'; said 2 "Erster Teil."; said 3 "Zweiter Teil."
  printf '{"type":"user","uuid":"u4","message":{"content":"Und morgen"}}\n'; said 5 "Morgen frueh."; } > "$r/a.jsonl"
expect "answer: each input carries the last text before the next" "Zweiter Teil.|Morgen frueh." \
  "$(state_extract "$r/a.jsonl" 1 | jq -rs '[.[] | select(.art? == "human") | .answer] | join("|")' | tr -d '\r')"

echo "== keys only where they were computed =="
d="$(cutlist_dir "$sid")"; mkdir -p "$d"
jq -n --arg s "$sid" '{title: "Save list", gate: "warn", cut: 1, holder: $s, sections: [], boxes: [], journal: []}' \
  | ticks_write "$d/cut-1.json"
state_cut_keys "$d/cut-1.json" "$sid" "$r/none.jsonl"
expect "keys: without candidates the list has none" false "$(jq 'has("keys")' "$d/cut-1.json" | tr -d '\r')"
expect "  and the balance names none, not an empty set" false "$(cutlist_balance "$d/cut-1.md" | jq 'has("keys")' | tr -d '\r')"
printf '%s\n' '{"end":{"line":1,"uuid":"x"},"unexamined":0}' > "$r/empty.jsonl"
state_cut_keys "$d/cut-1.json" "$sid" "$r/empty.jsonl"
expect "  candidates without a sentence of the maintainer or a message give an empty set" "[]" \
  "$(cutlist_balance "$d/cut-1.md" | jq -c '.keys' | tr -d '\r')"

echo "== the keys of a long history do not pass the command line =="
# 2000 keys of about 80 characters, beyond the 32 KB of a Windows command line and the 128 KB of one Linux argument.
awk -v s="$sid" 'BEGIN { for (i = 1; i <= 2000; i++) printf "{\"art\":\"human\",\"l\":%d,\"ts\":\"2026-11-25T2000Z\",\"text\":\"Frage %d\",\"u\":\"%08d-aaaa-4bbb-8ccc-dddddddddddd\"}\n", i, i, i
  print "{\"end\":{\"line\":2000,\"uuid\":\"x\"},\"unexamined\":0}" }' > "$r/many.jsonl"
state_cut_keys "$d/cut-1.json" "$sid" "$r/many.jsonl"; rc=$?
expect "long history: the keys are written to the list" "0 2000" "$rc $(jq '.keys | length' "$d/cut-1.json" | tr -d '\r')"
cut_save "$sid" "$d/cut-1.md" "$st/cuts.jsonl" "$p" > /dev/null 2>&1; rc=$?
expect "  the report of the save carries them" "0 2000" "$rc $(tail -n 1 "$st/cuts.jsonl" | jq '.keys | length' | tr -d '\r')"
cp "$r/many.jsonl" "$r/match/cand.jsonl"
printf '# Restore\n\n## History without a carrier\n\n- [ ] L1 2026-11-25T2000Z promise: Ich baue es.\n' > "$r/restore.in"
rs_carriers=()
state_restore_list "$r/restore.in" "$st/$sid-restore.md" "$sid" compact "$sid" "$r/many.jsonl" "$r/match"; rc=$?
expect "  the restore after a compaction writes its list" "0 2000" \
  "$rc $(jq '.keys | length' "$(ticks_side "$state_cut")" | tr -d '\r')"

finish
