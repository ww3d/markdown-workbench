#!/usr/bin/env bash
# Hook suite section: the list of each cut (lib/cutlist.sh, ww3d/playbook#727) - a list per cut that stays, boxes
# that did not end come again, "abgelegt", the third hold, the balance, the repair, the holder and the summary's
# instruction.
# Run alone: bash .claude/hooks/tests/cases/cut-list.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# No network and no real clock: the clock is TICKS_NOW, the session's tool call a transcript file.
# shellcheck disable=SC2016 # jq text, not shell
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

c="$fix/cut-list"; mkdir -p "$c/proj"
export CLAUDE_PROJECT_DIR="$c/proj" TICKS_TRANSCRIPT="$c/transcript.jsonl" TICKS_NOW="2026-11-25T12:00:00Z"
: > "$TICKS_TRANSCRIPT"
# shellcheck source=SCRIPTDIR/../../lib/ticks.sh
. "$hooks/lib/ticks.sh"
tool_call() { ticks_tx_call "$1" "$TICKS_TRANSCRIPT"; }
close() { tool_call "tc-$RANDOM$RANDOM"; bash "$hooks/ticks.sh" close "$@" > "$c/out" 2>&1; echo $?; }
side() { ticks_side "$1"; }
mark() { grep -o "^- \[.\] $2 " "$1" | cut -c4; } # view, id -> its mark
spec() { # title, keys... -> a spec file on stdout's path
  local f="$c/spec-$RANDOM.json" t="$1"; shift
  jq -n --arg t "$t" '{title: $t, gate: "view", sections: [{title: "History without a carrier", text: "x"}],
    boxes: [$ARGS.positional[] | {key: ., title: "box \(.)", section: "History without a carrier", rule: "core", core: "kern \(.)", kind: "promise"}]}' \
    --args "$@" > "$f"
  printf '%s' "$f"
}
make_cut() { # session, source, spec, olds... -> the view
  local v s="$1" src="$2" sp="$3"; shift 3
  v="$(cutlist_reserve "$s")" && cutlist_build "$v" "$sp" "$s" "$src" "" 0 "$@" && printf '%s' "$v"
}

# --- a list per cut, the earlier one stays ---
v1="$(make_cut S save "$(spec one S:a S:b S:c S:d)")"
expect "the first cut writes cut-1" "cut-1.md" "${v1##*/}"
close K1 abgelegt "kein Auftrag" --list "$v1" > /dev/null
close K2 ungeprueft "nicht geprueft" --list "$v1" > /dev/null
v2="$(make_cut S compact "$(spec two S:e)" "$(side "$v1")")"
expect "the second cut writes cut-2" "cut-2.md" "${v2##*/}"
present_file "the list of the first cut stays" "$(side "$v1")"
keys="$(jq -r '[.boxes[].key] | sort | join(" ")' "$(side "$v2")" | tr -d '\r')"
expect "open and [u] boxes come again, a set-aside one does not" "S:b S:c S:d S:e" "$keys"
check_contains "a carried box shows it was passed on" "(weitergereicht, 1x)" "$(cat "$v2")"
expect "an unchecked box keeps its [u]" "u" "$(mark "$v2" "$(jq -r '.boxes[] | select(.key == "S:b") | .id' "$(side "$v2")" | tr -d '\r')")"
v3="$(make_cut S save "$(spec three)" "$(side "$v2")")"
check_contains "a box carried twice counts its hops" "(weitergereicht, 2x)" "$(cat "$v3")"
expect "the earlier list leaves the guard's registry" "" "$(grep -rl "cut-2.md" "$(ticks_registry)" 2>/dev/null)"
ticks_register "$v3"; ticks_register "$(ticks_canon "$v3")"
expect "one list under several spellings stands once in the registry" "1" "$(grep -rl "cut-3.md" "$(ticks_registry)" | wc -l | tr -d ' ')"

# --- abgelegt ---
v4="$(make_cut S save "$(spec four S:x S:y)")"
expect "abgelegt without a reason is refused" "2" "$(close K1 abgelegt "" --list "$v4")"
expect "abgelegt sets aside with a reason" "0" "$(close K1 abgelegt "nur ein Stand" --list "$v4")"
expect "the same reason for a second box is refused" "1" "$(close K2 abgelegt "nur ein Stand" --list "$v4")"
mkdir -p "$c/plain"; printf '{"title":"p","boxes":[{"key":"k","title":"t"}]}' > "$c/plain.json"
bash "$hooks/ticks.sh" open "$c/plain/list.md" "$c/plain.json" > /dev/null 2>&1
expect "abgelegt outside the list of a cut is refused" "1" "$(close K1 abgelegt "irgendwas" --list "$c/plain/list.md")"

# --- a changed carrier and a missing instruction keep one key per session: a new one after a closed one is a box ---
kspec() { # kind, key, event (time of the change, cut of the instruction) -> a spec file with one box of that kind
  local f="$c/kspec-$RANDOM.json"
  jq -n --arg k "$2" --arg kind "$1" --arg ev "$3" '{title: "k", gate: "view", sections: [{title: "Carriers changed since checked", text: "x"}],
    boxes: [{key: $k, title: "box \($k)", section: "Carriers changed since checked", rule: "core", core: "kern", kind: $kind}
      + (if $kind == "changed" then {changes: [{carrier: "o/r#1", kind: "changed", at: $ev}]} else {event: $ev} end)]}' > "$f"
  printf '%s' "$f"
}
k1="$(make_cut K compact "$(kspec changed K:changed:o/r#1 2026-11-25T10:00:00Z)")"
close K1 abgelegt "Aenderung schon gelesen" --list "$k1" > /dev/null
k2="$(make_cut K compact "$(kspec changed K:changed:o/r#1 2026-11-25T11:00:00Z)" "$(side "$k1")")"
expect "a new change at a carrier read before is a box again" "K:changed:o/r#1" "$(jq -r '[.boxes[].key] | join(" ")' "$(side "$k2")" | tr -d '\r')"
k3="$(make_cut I compact "$(kspec instruction I:instruction cut-a)")"
close K1 abgelegt "Anweisung kam beim zweiten Mal" --list "$k3" > /dev/null
k4="$(make_cut I compact "$(kspec instruction I:instruction cut-b)" "$(side "$k3")")"
expect "an instruction missing again after a closed one is a box again" "1" "$(jq '.boxes | length' "$(side "$k4")" | tr -d '\r')"
expect "  the closing of the change before does not close the new one" " " "$(mark "$k2" K1)"
expect "  the closing of the instruction before does not close the new one" " " "$(mark "$k4" K1)"
k5="$(make_cut J compact "$(kspec instruction J:instruction cut-a)")"
close K1 ungeprueft "kein Zugriff" --list "$k5" > /dev/null
k6="$(make_cut J compact "$(kspec instruction J:instruction cut-b)" "$(side "$k5")")"
expect "  an instruction left unchecked before is open again when it is missing again" " " "$(mark "$k6" K1)"
# The same event built anew (a second restore for the same stand) keeps its closing (ww3d/playbook#734).
k8="$(make_cut M compact "$(kspec changed M:changed:o/r#1 2026-11-25T10:00:00Z)")"
close K1 abgelegt "Aenderung gelesen" --list "$k8" > /dev/null
k9="$(make_cut M compact "$(kspec changed M:changed:o/r#1 2026-11-25T10:00:00Z)" "$(side "$k8")")"
expect "  the same change built anew stays closed" x "$(mark "$k9" K1)"
k10="$(make_cut N compact "$(kspec instruction N:instruction cut-a)")"
close K1 abgelegt "Anweisung nachgeholt" --list "$k10" > /dev/null
k11="$(make_cut N compact "$(kspec instruction N:instruction cut-a)" "$(side "$k10")")"
expect "  the same missing instruction built anew stays closed" x "$(mark "$k11" K1)"
k7="$(make_cut L compact "$(kspec changed L:changed:o/r#2 2026-11-25T10:00:00Z)")"
expect "  an open change is no sentence the carriers of the next cut are searched for" 0 \
  "$(cutlist_carried "$(side "$k7")" | grep -c . || true)"

# --- a carried box a carrier of the cut holds ends by the tool ---
v5="$(make_cut T save "$(spec five T:a T:b)")"
TICKS_NOW="2026-11-25T12:05:00Z"; v6="$(cutlist_reserve T)"; printf '{"T:a":"o/r#1"}' > "$c/held.json"
cutlist_build "$v6" "$(spec six)" T save "$c/held.json" 0 "$(side "$v5")"
expect "the carried box the carrier holds is done, the other passed on" "1 0 1" \
  "$(cutlist_balance "$v6" | jq -r '"\(.done) \(.released) \(.forwarded)"' | tr -d '\r')"
TICKS_NOW="2026-11-25T12:00:00Z"

# --- the balance ---
v7="$(make_cut U save "$(spec seven U:a U:b U:c U:d)")"
close K1 abgelegt "Grund eins" --list "$v7" > /dev/null
close K2 ungeprueft "offen" --list "$v7" > /dev/null
b="$(cutlist_balance "$v7")"
expect "the balance holds: open before = done + released + forwarded" "4 = 0 + 1 + 3 (open 2)" \
  "$(jq -r '"\(.openBefore) = \(.done) + \(.released) + \(.forwarded) (open \(.open))"' <<< "$b" | tr -d '\r')"

# --- the report names the key of each candidate of the maintainer, of an open question and of a message ---
# shellcheck source=SCRIPTDIR/../../lib/state.sh
. "$hooks/lib/state.sh"
{ printf '{"art":"human","u":"u1","s":0,"l":1,"text":"a"}\n{"art":"message","u":"u2","l":2,"text":"b"}\n'
  printf '{"art":"promise","u":"u3","l":3,"text":"c"}\n{"art":"open-question","l":4,"text":"frage x"}\n{"end":{}}\n'; } > "$c/cand.jsonl"
vq="$(make_cut Q save "$(spec q Q:u1:0)")"
state_cut_keys "$(side "$vq")" Q "$c/cand.jsonl"
expect "keys: the box and the carried ones of those kinds, no promise" "Q:L4 open-question: frage x|Q:u1:0|Q:u2" \
  "$(cutlist_balance "$vq" | jq -r '.keys | join("|")' | tr -d '\r')"

# --- a missing key is repaired ---
printf '["U:zz"]' > "$c/must.json"

jq -s '[.[0] | .boxes += [{id: "K9", key: "U:zz", title: "lost", rule: "core", core: "lost"}]]' "$(side "$v7")" > "$c/olds2.json"
cutlist_repair "$(side "$v7")" "$c/must.json" "$c/olds2.json"
expect "a key that must stand is added and counted" "1 1" \
  "$(jq -r '"\([.boxes[] | select(.key == "U:zz")] | length) \(.repaired)"' "$(side "$v7")" | tr -d '\r')"

# --- the third hold without progress passes the rest on ---
v8="$(make_cut W save "$(spec eight W:a W:b)")"
cutlist_hold "$v8"; r1=$?
cutlist_hold "$v8"; r2=$?
close K1 ungeprueft "Fortschritt" --list "$v8" > /dev/null
cutlist_hold "$v8"; r3=$?
cutlist_hold "$v8"; r4=$?
cutlist_hold "$v8"; r5=$?
expect "progress between holds starts the count again" "1 1 1 1 0" "$r1 $r2 $r3 $r4 $r5"
expect "the third hold sets every open box to [u] by the tool" "u 1" \
  "$(mark "$v8" K2) $(jq -r .byTool "$(side "$v8")" | tr -d '\r')"
check_contains "with the tool's reason" "weitergereicht vom Werkzeug nach 3 Halten" "$(cat "$v8")"

# --- the guard warns only at the holder's list ---
make_cut X save "$(spec nine X:a)" > /dev/null
check_not_contains "another session's list of a cut warns nothing" "ticks/X/cut-" "$(TICKS_SESSION=Y ticks_guard)"
# Only this list stays registered: the warning line ends at 200 characters, and the entries sort by a hash of the path.
reg="$(ticks_registry)"; mkdir -p "$c/reg-aside"
for f in "$reg"/*; do grep -q '/ticks/X/cut-' "$f" || mv "$f" "$c/reg-aside/"; done
check_contains "the holder's list warns with its count" "1 offene Punkte in .agent/state/ticks/X/cut-" "$(TICKS_SESSION=X ticks_guard)"
mv "$c/reg-aside/"* "$reg/" 2>/dev/null || true

# --- the summary's instruction names each open box of the newest list ---
jq -n '{title: "s", gate: "warn", boxes: [{key: "Z:u1:0", title: "h", core: "der Mensch fragt", kind: "human"},
  {key: "Z:u2", title: "m", core: "eine Nachricht", kind: "message"}, {key: "Z:u3", title: "x", core: "ein Helfer", kind: "helper"}]}' > "$c/z.json"
make_cut Z save "$c/z.json" > /dev/null
say="$(printf '{"session_id":"Z","transcript_path":"%s","trigger":"auto"}' "$TICKS_TRANSCRIPT" | bash "$hooks/save-compact-state.sh" 2>/dev/null)"
check_contains "a human box stands in the instruction" "- Z:u1:0 der Mensch fragt" "$say"
check_contains "a message box stands in the instruction" "- Z:u2 eine Nachricht" "$say"
check_contains "a helper box stands in the instruction" "- Z:u3 ein Helfer" "$say"
jq -n '{title: "s", gate: "warn", boxes: [range(0; 200) | {key: "Z:many-\(.)", title: "t", core: ("lang " * 30), kind: "promise"}]}' > "$c/z2.json"
make_cut Z save "$c/z2.json" "$(side "$(cutlist_latest Z)")" > /dev/null
say="$(printf '{"session_id":"Z","transcript_path":"%s","trigger":"auto"}' "$TICKS_TRANSCRIPT" | bash "$hooks/save-compact-state.sh" 2>/dev/null)"
expect "over the limit, the last line counts the rest" "1" "$(tail -n 1 <<< "$say" | grep -c '^(weitere [0-9]* offene Kaesten in ')"
expect "the instruction stays under 10,000 characters" "1" "$([ "${#say}" -lt 10000 ] && echo 1 || echo 0)"

finish
