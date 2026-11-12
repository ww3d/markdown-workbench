#!/usr/bin/env bash
# Hook suite section: session-state.sh save (SICHERN, ww3d/playbook#487) and the summary instruction of
# save-compact-state.sh. The loss cases of the issue body ("Testfaelle fuer Frage 554") marked for part 1
# stand here by number.
# Run alone: bash .claude/hooks/tests/cases/session-state-save.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== session-state.sh save: what no carrier holds, the cursor, the check line (ww3d/playbook#487) =="
ss="$hooks/session-state.sh"
proj="$fix/ss-proj"; mkdir -p "$proj"
# The forge stand-in and the transcript lines come from the harness (use_forge, line, human, said, peer, agent).
use_forge "$fix/ss-forge"
save() { # args... -> output, global rc; session ss1 unless SS_SESSION
  out="$(cd "$proj" && PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
    CLAUDE_CODE_SESSION_ID="${SS_SESSION:-ss1}" bash "$ss" save "$@" 2>&1)"; rc=$?
}
list() { cat "$proj/.agent/state/${SS_SESSION:-ss1}-save.md" 2>/dev/null; }

tx="$fix/ss1.jsonl"; fresh
{
  human 'Bitte den Hook so bauen, dass er nichts sperrt.'
  said 'Ich baue den Hook heute ohne Sperre und melde mich danach.'                         # case 1
  agent toolu_a1 'Fund des Helfers: die Datei lib/zahl.sh rechnet mit falschem Grenzwert.'  # case 2
  peer ctrl-x 'Hast du die Liste der offenen Punkte fuer #12 schon fertig?'                 # cases 5, 25
  human 'Das war schon wieder falsch, du hast den Traeger nicht gelesen.'                    # cases 11, 40
  said 'Vorschlag: die Liste in zwei Teile schneiden.'                                      # case 12
  said 'Sobald der Lauf steht, sage ich Bescheid.'                                           # case 16
  said 'Erledigt, Testbefehl bash run-tests.sh --jobs 4 ist gruen.'                          # case 18
  said 'Wir nehmen die zweite Variante mit dem Cursor.'                                      # case 31
  said 'Ich raeume die alten Klone morgen auf.'                                             # case 35
  said 'Ich schicke die Liste an ctrl-x.'                                     # case 20 (second to last answer)
  said 'Die Arbeit laeuft.'
  said 'Soll ich den Teil 2 gleich mitbauen?'
  human 'nein'                                                                              # case 34
  human 'Warum sperrt der Hook ueberhaupt etwas?'                                            # cases 27, 41
} > "$tx"
body ww3d_playbook_1 '## Open points
- [ ] something carried'
save --carrier ww3d/playbook#1 --transcript "$tx"
expect 'save: boxes open, exit 3' 3 "$rc"
check_contains 'save: no cursor, it says it starts at line 1' 'no cursor: from line 1' "$out"
check_contains 'save: without the further channel it says so' 'further channel: not checked' "$out"
present_file 'case 33: the work list lies under .agent/state/ in the project' "$proj/.agent/state/ss1-save.md"
l="$(list)"
expect 'case 27: the unanswered question of the maintainer comes first' \
  '- [ ] L16 2026-11-12T1016Z open-question: Warum sperrt der Hook ueberhaupt etwas?' "$(head -n 1 <<< "$l")"
check_contains 'case 1: an own promise is a box' 'promise: Ich baue den Hook heute ohne Sperre' "$l"
check_contains 'case 2: a finding only in a helper result is a box' 'helper: Fund des Helfers' "$l"
check_contains 'case 5 and 25: a peer question is a box with its sender' 'message: ctrl-x: Hast du die Liste' "$l"
check_not_contains 'case 25: the sender is never unknown' 'unknown' "$l"
check_contains 'case 11 and 40: a reproach of the maintainer is a box' 'human: Das war schon wieder falsch' "$l"
check_contains 'case 12: a proposal without a verb of time is a box' 'promise: Vorschlag: die Liste' "$l"
check_contains 'case 16: an announcement is a box' 'Sobald der Lauf steht, sage ich Bescheid.' "$l"
check_contains 'case 18: a done claim is a box' 'done: Erledigt, Testbefehl' "$l"
check_contains 'case 31: a decision in the chat is a box' 'decision: Wir nehmen die zweite Variante' "$l"
check_contains 'case 35: a cleanup promise is a box' 'promise: Ich raeume die alten Klone' "$l"
check_contains 'case 20: the promise in the second to last answer is a box' 'promise: Ich schicke die Liste an ctrl-x.' "$l"
check_not_contains 'save: a plain status sentence is no box' 'Die Arbeit laeuft' "$l"
check_contains 'case 34: a short answer stands with the question before it' 'human: nein (auf: Soll ich den Teil 2 gleich mitbauen?)' "$l"
check_contains 'save: an own question to the maintainer is a box' 'question: Soll ich den Teil 2' "$l"
absent_file 'save: no state file while boxes are open' "$proj/.agent/state/ss1.json"

# REQ-028 / decision 8: a sentence of the maintainer without a carrier is a box; once the carrier holds it
# (and the rest), save ends with 0.
tx2="$fix/ss2.jsonl"; fresh
{ human 'Die Hooks muessen auch unter Linux ohne pwsh laufen, das ist Pflicht.'; said 'Die Arbeit laeuft.'; } > "$tx2"
body ww3d_playbook_2 '## Open points'
SS_SESSION=ss2 save --carrier ww3d/playbook#2 --transcript "$tx2"
expect 'held: the uncarried sentence keeps save at exit 3' 3 "$rc"
check_contains 'held: it stands as an open box' '- [ ] L1 2026-11-12T1001Z human: Die Hooks muessen auch unter Linux' "$(SS_SESSION=ss2 list)"
body ww3d_playbook_2 '## Open points
- [ ] Mensch: "Die Hooks muessen auch unter Linux ohne PWSH laufen - das ist Pflicht!"'
SS_SESSION=ss2 save --carrier ww3d/playbook#2 --transcript "$tx2"
expect 'held: carried in the body (case, umlauts and marks aside), save ends with 0' 0 "$rc"
check_contains 'held: the check line is printed' "checked: " "$out"
check_contains 'held: the check line names the cursor' "cursor: $tx2 L2 00000002-aaaa" "$out"
st="$(cat "$proj/.agent/state/ss2.json" 2>/dev/null)"
expect 'held: the state file keeps the cursor line' 2 "$(jq -r '.cursor.line' <<< "$st")"
expect 'held: the state file keeps the cursor uuid' 00000002-aaaa-4bbb-8ccc-dddddddddddd "$(jq -r '.cursor.uuid' <<< "$st")"
check_contains 'held: the state file keeps the check line' 'checked: ' "$(jq -r '.checkLine' <<< "$st")"
expect 'held: the state file names the carriers the restore asks the forge about' 'ww3d/playbook#2' "$(jq -r '.carriers | join(",")' <<< "$st" | tr -d '\r')"
check_contains 'held: the state file keeps checkedAt to the second, the start of what changed' \
  "$(jq -r '.checked' <<< "$st" | tr -d '\r' | cut -c1-10)T" "$(jq -r '.checkedAt' <<< "$st")"
expect 'held: checkedAt is an ISO time to the second' 1 \
  "$([[ $(jq -r '.checkedAt' <<< "$st" | tr -d '\r') =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && echo 1 || echo 0)"
absent_file 'held: save leaves no mark in the gate folder' "$cs_gate/ss2-cross-check-mark"

# The cursor: after the saved uuid; by line where the uuid is gone; from 1 where neither holds.
tx_n=2; { cat "$tx2"; human 'Neue Bitte nach der Sicherung: die Doku kuerzen.'; } > "$fix/ss2b.jsonl"
SS_SESSION=ss2 save --carrier ww3d/playbook#2 --transcript "$fix/ss2b.jsonl"
check_contains 'cursor: it starts after the saved uuid' 'cursor: after L2 (uuid 00000002-' "$out"
check_not_contains 'cursor: the saved range is not listed again' 'Linux' "$(SS_SESSION=ss2 list)"
check_contains 'case 26: what came after the cursor is listed' 'human: Neue Bitte nach der Sicherung' "$(SS_SESSION=ss2 list)"
sed 's/00000002-aaaa/0000000x-aaaa/' "$fix/ss2b.jsonl" > "$fix/ss2c.jsonl"
SS_SESSION=ss2 save --carrier ww3d/playbook#2 --transcript "$fix/ss2c.jsonl"
check_contains 'cursor: without its uuid it goes by the line number' 'uuid not found, after L2 by line number' "$out"
head -n 1 "$fix/ss2c.jsonl" > "$fix/ss2d.jsonl"
SS_SESSION=ss2 save --carrier ww3d/playbook#2 --transcript "$fix/ss2d.jsonl"
check_contains 'cursor: neither found, it starts at line 1 and says so' 'cursor not found in the transcript: from line 1' "$out"

# A ticked box with a proof stays ticked; one without a proof counts as open.
tx3="$fix/ss3.jsonl"; fresh; { said 'Ich trage den Fund nach.'; said 'Ich melde mich bei ctrl-x.'; } > "$tx3"
body ww3d_playbook_3 'nichts'
SS_SESSION=ss3 save --carrier ww3d/playbook#3 --transcript "$tx3"
expect 'tick: two boxes open first' 2 "$(SS_SESSION=ss3 list | grep -c '^- \[ \]')"
sed -i -e 's/^- \[ \] \(L1 .*\)$/- [x] \1 -> https:\/\/example.invalid\/1/' -e 's/^- \[ \] \(L2 .*\)$/- [x] \1/' "$proj/.agent/state/ss3-save.md"
SS_SESSION=ss3 save --carrier ww3d/playbook#3 --transcript "$tx3"
expect 'tick: one box open stays, exit 3' 3 "$rc"
check_contains 'tick: the box with a proof stays ticked' '- [x] L1 2026-11-12T1001Z promise: Ich trage den Fund nach. -> https://example.invalid/1' "$(SS_SESSION=ss3 list)"
check_contains 'tick: a tick without a proof counts as open' '- [ ] L2 2026-11-12T1002Z promise: Ich melde mich' "$(SS_SESSION=ss3 list)"
sed -i 's/^- \[ \] \(L2 .*\)$/- [x] \1 -> erledigt am Traeger/' "$proj/.agent/state/ss3-save.md"
SS_SESSION=ss3 save --carrier ww3d/playbook#3 --transcript "$tx3"
expect 'tick: every box ticked with a proof, exit 0' 0 "$rc"

# The haystack: linked issues one level deep, each body fetched once; the further channel.
tx4="$fix/ss4.jsonl"; fresh; { said 'Ich baue zuerst den Abgleich ueber alle verlinkten Issues und dann die Liste.'; said 'Ich schreibe den Kanal-Text.'; } > "$tx4"
body ww3d_playbook_4 'Siehe #5 und ww3d/other#6 und https://github.com/ww3d/playbook/issues/5'
body ww3d_playbook_5 'Ich baue zuerst den Abgleich ueber alle verlinkten Issues und dann die Liste. Siehe #7.'
body ww3d_other_6 'nichts'
body ww3d_playbook_7 'Ich schreibe den Kanal-Text.'
: > "$forge/calls.log"
SS_SESSION=ss4 save --carrier ww3d/playbook#4 --carrier ww3d/playbook#4 --transcript "$tx4"
check_not_contains 'haystack: a linked body carries a candidate' 'den Abgleich' "$(SS_SESSION=ss4 list)"
check_contains 'haystack: a link two levels deep is not followed' 'Kanal-Text' "$(SS_SESSION=ss4 list)"
expect 'haystack: each body is fetched once' 3 "$(sort -u "$forge/calls.log" | wc -l | tr -d ' ')"
expect 'haystack: a carrier named twice is fetched once, a link named twice too' 3 "$(wc -l < "$forge/calls.log" | tr -d ' ')"
chan="$fix/ss-chan.sh"
# shellcheck disable=SC2016 # the stub's own $1
printf '#!/usr/bin/env bash\n[ "$1" = text ] && echo "Ich schreibe den Kanal-Text."\n' > "$chan"
PLAYBOOK_CARRIER_TEXT_CMD="bash $chan" SS_SESSION=ss4 save --carrier ww3d/playbook#4 --transcript "$tx4"
expect 'channel: the further channel carries the rest, exit 0' 0 "$rc"
check_not_contains 'channel: with the command set, no not-checked line' 'further channel: not checked' "$out"
PLAYBOOK_CARRIER_TEXT_CMD="false" SS_SESSION=ss4b save --carrier ww3d/playbook#4 --transcript "$tx4"
check_contains 'channel: a failing command is named, not fatal' 'further channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD failed' "$out"
expect 'channel: a failing command keeps the exit of the boxes' 3 "$rc"
body ww3d_playbook_8 'Siehe #999'
SS_SESSION=ss4c save --carrier ww3d/playbook#8 --transcript "$tx4"
check_contains 'haystack: an unreadable linked issue is a line, not an error' 'linked not read: ww3d_playbook_999' "$out"
expect 'haystack: an unreadable linked issue keeps exit 3' 3 "$rc"

# Read errors: exit 2 and what was missing.
SS_SESSION=ss5 save --carrier ww3d/playbook#404 --transcript "$tx4"
expect 'error: an unreadable carrier is exit 2' 2 "$rc"
check_contains 'error: it names the carrier' 'carrier not readable: ww3d/playbook#404' "$out"
SS_SESSION=ss5 save --transcript "$fix/no-such.jsonl"
expect 'error: a missing transcript is exit 2' 2 "$rc"
check_contains 'error: it names the transcript' 'transcript not readable' "$out"
SS_SESSION=ss5 save --carrier 'not a carrier'
expect 'error: a malformed carrier is exit 2' 2 "$rc"
mkdir -p "$fix/ss-nojq"
out="$(cd "$proj" && PATH="$fix/ss-nojq" CLAUDE_PROJECT_DIR="$proj" CLAUDE_CODE_SESSION_ID=ss5 "$BASH" "$ss" save --transcript "$tx4" 2>&1)"; rc=$?
expect 'error: without jq exit 2' 2 "$rc"
check_contains 'error: it names jq' 'jq missing' "$out"

# Warnings on the open points of a named carrier, the exit unchanged.
long="$(printf 'x%.0s' $(seq 1 650))"
body ww3d_playbook_9 "## Open points
- [ ] $long
- [ ] Punkt A. Stand 2026-11-01: halb fertig
- [ ] Punkt B mit Zitat \"Stand der Dinge\"
- [x] Punkt C, Nachtrag erledigt
## Next"
SS_SESSION=ss6 save --carrier ww3d/playbook#9 --transcript "$tx2"
check_contains 'warn: an open point over 600 characters' 'open point over 600 characters' "$out"
check_contains 'warn: an open point that appends history' 'appends history: - [ ] Punkt A' "$out"
check_not_contains 'warn: history inside a quote is no finding' 'Punkt B' "$out"
check_not_contains 'warn: a ticked box is no finding' 'Punkt C' "$out"
expect 'warn: the warnings keep the exit' 3 "$rc"

# Side threads, local command output, the compaction summary, an async launch and a shell notice are no
# candidates; a message queued while a turn ran is; a message names its sender from the delivery line.
tx7="$fix/ss7.jsonl"; fresh
{
  js 'Ich baue im Seitenfaden etwas anderes.'; line "\"type\":\"assistant\",\"isSidechain\":true,\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":$REPLY}]}"
  human '<local-command-stdout>Ich mache gar nichts</local-command-stdout>'
  js 'This session is being continued from a previous conversation. Ich baue weiter.'; line "\"type\":\"user\",\"isCompactSummary\":true,\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  line '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_b","name":"Agent","input":{}}]}'
  line '"type":"user","toolUseResult":{"isAsync":true},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_b","content":"Async agent launched"}]}'
  js '<task-notification><summary>Background command "x" completed</summary></task-notification>'; line "\"type\":\"user\",\"origin\":{\"kind\":\"task-notification\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  js '<task-notification><summary>Agent "Pruefung" finished</summary><result>Der Helfer fand zwei tote Pfade.</result></task-notification>'; line "\"type\":\"user\",\"origin\":{\"kind\":\"task-notification\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  js $'[rc · from ctrl-y · msg_9 · working]\nBitte den Lauf neu starten.\n[rc-delivery: dlv_9]'
  line "\"type\":\"attachment\",\"attachment\":{\"type\":\"queued_command\",\"prompt\":$REPLY,\"origin\":{\"kind\":\"peer\",\"from\":\"unknown\"},\"isMeta\":true}"
  js $'Bitte pruefen.\n[rc-delivery: dlv_77]'; line "\"type\":\"user\",\"origin\":{\"kind\":\"human\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  js 'postbox: unread post for you.'; line "\"type\":\"user\",\"isMeta\":true,\"origin\":{\"kind\":\"peer\",\"from\":\"unknown\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  js $'This session is being continued from a previous conversation.\n[rc-delivery: dlv_5]'; line "\"type\":\"user\",\"isCompactSummary\":true,\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  line '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_f","name":"Agent","input":{}}]}'
  line '"type":"user","toolUseResult":"Error: hook blocked the call","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_f","is_error":true,"content":"Error: hook blocked the call"}]}'
  line '"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_g","name":"Agent","input":{}}]}'
  line '"type":"user","toolUseResult":"Helfer lief als Text","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_g","content":"Helfer lief als Text"}]}'
  line '"type":"api-request","params":{}'
  human 'Nach dem Fehlschlag: bitte die Zeilen zaehlen.'
  printf 'not json\n'
} > "$tx7"
SS_SESSION=ss7 save --transcript "$tx7"
l="$(SS_SESSION=ss7 list)"
check_not_contains 'skip: a side thread' 'Seitenfaden' "$l"
check_not_contains 'skip: local command output' 'gar nichts' "$l"
check_not_contains 'skip: the compaction summary' 'previous conversation' "$l"
check_not_contains 'skip: a compaction summary with an rc delivery tag is no message' 'dlv_5' "$l"
check_not_contains 'skip: the result of a failed helper call' 'hook blocked' "$l"
check_contains 'a failed helper call keeps the lines before it' 'message: ctrl-y: [rc' "$l"
check_contains 'a failed helper call keeps the line count after it' "L$(grep -n 'Nach dem Fehlschlag' "$tx7" | cut -d: -f1) " "$(grep 'Nach dem Fehlschlag' <<< "$l")"
check_not_contains 'skip: the launch of an async helper' 'Async agent launched' "$l"
check_not_contains 'skip: the notice of a shell command' 'Background command' "$l"
check_contains 'helper: the notification of a finished helper is a box' 'helper: <task-notification><summary>Agent' "$l"
check_contains 'message: a queued rc message names its sender' 'message: ctrl-y: [rc' "$l"
check_contains 'message: without a name, the delivery id' 'message: dlv_77: Bitte pruefen.' "$l"
check_contains 'message: without either, the first word' 'message: postbox: postbox: unread post' "$l"
check_contains 'save: no --carrier says the haystack is only the channel' 'no --carrier' "$out"

# Case 43: a promise and its revocation are both boxes.
tx8="$fix/ss8.jsonl"; fresh; { said 'Ich baue den Schalter morgen.'; said 'Den Schalter baue ich doch nicht.'; } > "$tx8"
SS_SESSION=ss8 save --transcript "$tx8"
check_contains 'case 43: the promise is a box' 'promise: Ich baue den Schalter morgen.' "$(SS_SESSION=ss8 list)"
check_contains 'case 43: its revocation is a box' 'revoke: Den Schalter baue ich doch nicht.' "$(SS_SESSION=ss8 list)"
# Case 39: a reproach with a promise in one turn: both boxes.
tx9="$fix/ss9.jsonl"; fresh; { human 'Du hast schon wieder nicht gefragt!'; said 'Ich frage ab jetzt vor jedem Push.'; } > "$tx9"
SS_SESSION=ss9 save --transcript "$tx9"
check_contains 'case 39: the reproach is a box' 'human: Du hast schon wieder nicht gefragt!' "$(SS_SESSION=ss9 list)"
check_contains 'case 39: the promise is a box' 'promise: Ich frage ab jetzt vor jedem Push.' "$(SS_SESSION=ss9 list)"
# Case 42: a claim about a carrier is checked against that carrier.
tx10="$fix/ss10.jsonl"; fresh; { said 'Ich habe den Kasten in #11 geschlossen.'; } > "$tx10"
body ww3d_playbook_11 '- [ ] offen'
SS_SESSION=ss10 save --carrier ww3d/playbook#11 --transcript "$tx10"
check_contains 'case 42: the claim the carrier does not hold is a box' 'done: Ich habe den Kasten in #11 geschlossen.' "$(SS_SESSION=ss10 list)"
body ww3d_playbook_11 '- [x] Ich habe den Kasten in #11 geschlossen.'
SS_SESSION=ss10 save --carrier ww3d/playbook#11 --transcript "$tx10"
expect 'case 42: the carrier holds it, exit 0' 0 "$rc"

# A tick holds only for the whole text of its box: two promises on one line are two boxes, and an arrow
# inside the text is no proof.
tx12="$fix/ss12.jsonl"; fresh
{ said 'Ich baue den Zaehler morgen. Ich teste den Zaehler heute.'; said 'Ich mappe a -> b im Hook morgen.'; } > "$tx12"
SS_SESSION=ss12 save --transcript "$tx12"
expect 'tick: three boxes open first' 3 "$(SS_SESSION=ss12 list | grep -c '^- \[ \]')"
sed -i -e 's/^- \[ \] \(.*Ich baue den Zaehler morgen\.\)$/- [x] \1 -> https:\/\/example.invalid\/2/' \
  -e 's/^- \[ \] \(.*Ich mappe a -> b im Hook morgen\.\)$/- [x] \1/' "$proj/.agent/state/ss12-save.md"
SS_SESSION=ss12 save --transcript "$tx12"
l="$(SS_SESSION=ss12 list)"
expect 'tick: a second promise on the same line stays open, exit 3' 3 "$rc"
check_contains 'tick: the ticked promise stays ticked' '- [x] L1 2026-11-12T1001Z promise: Ich baue den Zaehler morgen. -> https' "$l"
check_contains 'tick: the other promise of that line is still a box' '- [ ] L1 2026-11-12T1001Z promise: Ich teste den Zaehler heute.' "$l"
check_contains 'tick: an arrow inside the box text is no proof' '- [ ] L2 2026-11-12T1002Z promise: Ich mappe a -> b' "$l"

# The cursor goes by line number when the saved uuid is empty.
tx13="$fix/ss13.jsonl"; fresh; { said 'Die Arbeit laeuft.'; said 'Die Arbeit laeuft weiter.'; human 'Bitte danach die Doku kuerzen.'; } > "$tx13"
jq -n --arg t "$tx13" '{cursor: {transcript: $t, line: 2, uuid: ""}}' > "$proj/.agent/state/ss13.json"
SS_SESSION=ss13 save --transcript "$tx13"
check_contains 'cursor: an empty saved uuid goes by the line number' 'uuid not found, after L2 by line number' "$out"
check_contains 'cursor: the line after it is listed' 'human: Bitte danach die Doku kuerzen.' "$(SS_SESSION=ss13 list)"

# The last compaction boundary of the main thread: nothing before it is read again, with or without a cursor.
tx15="$fix/ss15.jsonl"; fresh
{ human 'Bitte vor der Verdichtung den Bericht schicken.'; boundary
  for ((i = 1; i <= 20; i++)); do said "Schritt $i laeuft."; done; human 'Bitte nach der Verdichtung die Tabelle pruefen.'; } > "$tx15"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: without a cursor it starts after the last boundary and says so' 'no cursor: after the compaction boundary L2' "$out"
check_not_contains 'boundary: what stands before it is not listed again' 'vor der Verdichtung' "$(SS_SESSION=ss15 list)"
check_contains 'boundary: what follows it is listed' 'human: Bitte nach der Verdichtung die Tabelle pruefen.' "$(SS_SESSION=ss15 list)"
jq -n --arg t "$tx15" '{cursor: {transcript: $t, line: 1, uuid: ""}}' > "$proj/.agent/state/ss15.json"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: a cursor before it gives way to the boundary' 'cursor: after the compaction boundary L2' "$out"
jq -n --arg t "$tx15" '{cursor: {transcript: $t, line: 5, uuid: ""}}' > "$proj/.agent/state/ss15.json"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: a cursor after it holds' 'uuid not found, after L5 by line number' "$out"
rm -f "$proj/.agent/state/ss15.json"
fresh; { human 'Bitte den alten Stand behalten.'; line '"type":"system","subtype":"compact_boundary","isSidechain":true'
  for ((i = 1; i <= 20; i++)); do said "Schritt $i laeuft."; done; } > "$fix/ss16.jsonl"
SS_SESSION=ss16 save --transcript "$fix/ss16.jsonl"
check_contains "boundary: a helper's boundary does not count" 'no cursor: from line 1' "$out"
fresh; { human 'Bitte den letzten Stand behalten.'; boundary; said 'Die Verdichtung laeuft gerade.'; } > "$fix/ss17.jsonl"
SS_SESSION=ss17 save --transcript "$fix/ss17.jsonl"
check_contains 'boundary: one in the last 20 lines does not count' 'no cursor: from line 1' "$out"
# The restore of that compaction still has an open box: a second compaction came before it was worked off.
ss_rf="$proj/.agent/state/ss15-restore.md"
printf '# Restore\n\n## History without a carrier\n\nSince the cursor: no cursor: from line 1.\n\n- [ ] L1 human: x\n' > "$ss_rf"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: an open box in the last restore keeps its start' 'no cursor: from line 1' "$out"
check_contains 'boundary: what that restore held is listed again' 'vor der Verdichtung' "$(SS_SESSION=ss15 list)"
printf '# Restore\n\n## History without a carrier\n\nSince the cursor: no cursor: after the compaction boundary L2.\n\n- [ ] L3 human: x\n' > "$ss_rf"
jq -n --arg t "$tx15" '{cursor: {transcript: $t, line: 5, uuid: ""}}' > "$proj/.agent/state/ss15.json"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains "boundary: a later cursor goes back to the line after that restore's boundary" 'cursor: from L3, where the last restore began (1 open boxes)' "$out"
# A third compaction before that restore was worked off: the start it carried holds, not line 1.
printf '# Restore\n\n## History without a carrier\n\nSince the cursor: cursor: from L3, where the last restore began (1 open boxes).\n\n- [ ] L3 human: x\n' > "$ss_rf"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: a third compaction keeps the start that restore carried' 'cursor: from L3, where the last restore began' "$out"
rm -f "$proj/.agent/state/ss15.json"
printf '# Restore\n\n## History without a carrier\n\nSince the cursor: no cursor: from line 1.\n\n- [x] L1 human: x -> #1\n' > "$ss_rf"
SS_SESSION=ss15 save --transcript "$tx15"
check_contains 'boundary: a restore worked off lets the boundary count' 'no cursor: after the compaction boundary L2' "$out"
rm -f "$ss_rf"

# A slash command of the maintainer with arguments is an input.
tx14="$fix/ss14.jsonl"; fresh
human '<command-name>/dev-task</command-name><command-args>ww3d/x#1 bitte ohne Hook</command-args>' > "$tx14"
SS_SESSION=ss14 save --transcript "$tx14"
check_contains 'slash: a command with arguments is a box of the maintainer' 'human: /dev-task ww3d/x#1 bitte ohne Hook' "$(SS_SESSION=ss14 list)"

# A long candidate is held with at least half of its 6-word shingles: 12 words, 7 shingles, 4 suffice.
tx15="$fix/ss15.jsonl"; fresh; human 'Eins zwei drei vier fuenf sechs sieben acht neun zehn elf zwoelf' > "$tx15"
body ww3d_playbook_15 'Eins zwei drei vier fuenf sechs sieben acht neun'
SS_SESSION=ss15 save --carrier ww3d/playbook#15 --transcript "$tx15"
expect 'match: four of seven shingles hold a 12-word sentence, exit 0' 0 "$rc"
body ww3d_playbook_15 'Eins zwei drei vier fuenf sechs sieben acht'
SS_SESSION=ss15b save --carrier ww3d/playbook#15 --transcript "$tx15"
expect 'match: three of seven shingles do not, exit 3' 3 "$rc"

# A line of a shape no branch expects is skipped, the lines after it still count.
tx16="$fix/ss16.jsonl"; fresh
{
  printf '{"uuid":"00000001-aaaa-4bbb-8ccc-dddddddddddd","timestamp":1731400000,"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}\n'
  tx_n=1; human 'Nach der seltsamen Zeile: bitte weiter.'
} > "$tx16"
SS_SESSION=ss16 save --transcript "$tx16"
expect 'odd line: save still lists, exit 3' 3 "$rc"
check_contains 'odd line: the human line after it is a box' 'L2 2026-11-12T1002Z human: Nach der seltsamen Zeile' "$(SS_SESSION=ss16 list)"

# Without CLAUDE_PROJECT_DIR the project is the cwd the transcript names, not the folder save runs in.
proj17="$fix/ss-proj17"; mkdir -p "$proj17" "$fix/ss-elsewhere"
tx17="$fix/ss17.jsonl"; fresh; js "$proj17"
{ line "\"type\":\"user\",\"cwd\":$REPLY,\"origin\":{\"kind\":\"human\"},\"message\":{\"role\":\"user\",\"content\":\"Bitte sichern.\"}"; } > "$tx17"
out="$(cd "$fix/ss-elsewhere" && env -u CLAUDE_PROJECT_DIR PATH="$forge_bin:$PATH" TMPDIR="$cs_tmp" \
  CLAUDE_CODE_SESSION_ID=ss17 bash "$ss" save --transcript "$tx17" 2>&1)"; rc=$?
present_file 'root: the work list lies in the project of the transcript' "$proj17/.agent/state/ss17-save.md"
absent_file 'root: not in the folder save ran in' "$fix/ss-elsewhere/.agent/state/ss17-save.md"

# A hanging fetch or channel ends at its time limit: a timeout stand-in that answers 124.
mkdir -p "$fix/ss-tobin"; printf '#!/usr/bin/env bash\nexit 124\n' > "$fix/ss-tobin/timeout"; chmod +x "$fix/ss-tobin/timeout"
out="$(cd "$proj" && PATH="$fix/ss-tobin:$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  PLAYBOOK_CARRIER_TEXT_CMD="true" CLAUDE_CODE_SESSION_ID=ss18 bash "$ss" save --transcript "$tx15" 2>&1)"; rc=$?
check_contains 'timeout: the channel is named as timed out' 'PLAYBOOK_CARRIER_TEXT_CMD timed out' "$out"
out="$(cd "$proj" && PATH="$fix/ss-tobin:$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  CLAUDE_CODE_SESSION_ID=ss18 bash "$ss" save --carrier ww3d/playbook#15 --transcript "$tx15" 2>&1)"; rc=$?
expect 'timeout: a carrier fetch that timed out is exit 2' 2 "$rc"
check_contains 'timeout: it says the fetch timed out' 'gh timed out' "$out"

# A jq that ends its lines with CR LF (jq for Windows) still matches and keeps ticks.
mkdir -p "$fix/ss-crbin"; real_jq="$(command -v jq)"
{ printf '#!/usr/bin/env bash\nset -o pipefail\n"%s" "$@" | ' "$real_jq"; printf '%s\n' "awk '{ printf \"%s\\r\\n\", \$0 }'"; } > "$fix/ss-crbin/jq"
chmod +x "$fix/ss-crbin/jq"
expect 'crlf: the stand-in ends its lines with CR LF' 'a\r\n' "$(echo '"a"' | "$fix/ss-crbin/jq" -r . | od -An -c | tr -d ' \n')"
tx19="$fix/ss19.jsonl"; fresh; { human 'Bitte ohne Sperre bauen.'; said 'Ich baue den Schalter morgen.'; } > "$tx19"
body ww3d_playbook_19 'Bitte ohne Sperre bauen.'
cr_save() { out="$(cd "$proj" && PATH="$fix/ss-crbin:$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  CLAUDE_CODE_SESSION_ID=ss19 bash "$ss" save --carrier ww3d/playbook#19 --transcript "$tx19" 2>&1)"; rc=$?; }
cr_save
check_not_contains 'crlf: a short sentence the carrier holds is no box' 'Bitte ohne Sperre' "$(SS_SESSION=ss19 list)"
sed -i 's/^- \[ \] \(.*Ich baue den Schalter morgen\.\)$/- [x] \1 -> https:\/\/example.invalid\/3/' "$proj/.agent/state/ss19-save.md"
cr_save
expect 'crlf: the ticked box stays ticked, exit 0' 0 "$rc"

# The command the rules name runs directly: git keeps it executable.
expect 'mode: session-state.sh is executable in git' 100755 "$(git -C "$hooks" ls-files -s session-state.sh | cut -c1-6)"

# Recall over the marked fixture (REQ-029 of the spec): every marked line is a box; the value goes to the PR body.
mtx="$fix/ss-marked.jsonl"; marked=0; fresh
{
  while IFS='|' read -r who text; do
    case "$who" in H) human "$text" ;; A|a) said "$text" ;; esac
  done < "$here/session-state-marked.txt"
} > "$mtx"
SS_SESSION=ssm save --transcript "$mtx"
l="$(SS_SESSION=ssm list)"; found=0; noise=0
while IFS='|' read -r who text; do
  case "$who" in
    H|A) marked=$((marked + 1)); [[ $l == *"$text"* ]] && found=$((found + 1)) ;;
    a) [[ $l == *"$text"* ]] && noise=$((noise + 1)) ;;
  esac
done < "$here/session-state-marked.txt"
echo "  recall: $found of $marked marked lines listed; $noise unmarked lines listed"
if [ $((found * 100)) -ge $((marked * 90)) ]; then ok 'recall: at least 90 percent of the marked lines are boxes' "$found/$marked"
else bad 'recall: at least 90 percent of the marked lines are boxes' "$found/$marked" '>= 90 percent'; fi

echo "== session-state.sh save: ten points only in the chat, the pair file (ww3d/playbook#487) =="
# Ten points that stand only in the chat - a finding, an own promise and a reproach among them: each is a box,
# and save ends with 0 only once each stands at the carrier or is ticked with a proof.
tx20="$fix/ss20.jsonl"; fresh
{
  human 'Das ist schon wieder falsch, du liest die Traeger nicht.'
  agent toolu_c1 'Befund: der Zaehler in lib/zahl.sh zaehlt jede Zeile doppelt.'
  said 'Der Pfad in run-tests.sh ist behoben und gepusht.'
  said 'Ich baue den Zaehler morgen neu.'
  said 'Wir nehmen die Variante mit dem Cursor.'
  peer ctrl-z 'Bitte den Lauf vor dem Merge wiederholen.'
  human 'Halt, bitte nicht mergen bevor der Lauf gruen ist.'
  said 'Den Schalter fuer die Sperre baue ich doch nicht.'
  notice 'Der Helfer fand drei tote Links im Handbuch.'
  said 'Soll ich die Liste der Faelle kuerzen?'
} > "$tx20"
body ww3d_playbook_20 '## Open points'
SS_SESSION=ss20 save --carrier ww3d/playbook#20 --transcript "$tx20"
expect 'ten chat points: save ends with 3' 3 "$rc"
expect 'ten chat points: each is a box' 10 "$(SS_SESSION=ss20 list | grep -c '^- \[ \]')"
l="$(SS_SESSION=ss20 list)"
check_contains 'ten chat points: the reproach of the maintainer is a box' 'human: Das ist schon wieder falsch' "$l"
check_contains 'ten chat points: the finding of a helper is a box' 'helper: Befund: der Zaehler' "$l"
check_contains 'ten chat points: the own promise is a box' 'promise: Ich baue den Zaehler morgen neu.' "$l"
expect 'ten chat points: no pair while no carrier holds one' 0 "$(wc -l < "$proj/.agent/state/ss20-pairs.md" | tr -d ' ')"
# Five go to the carrier, five are ticked with a proof.
body ww3d_playbook_20 '## Open points
- [ ] Mensch: Das ist schon wieder falsch, du liest die Traeger nicht.
- [ ] Befund: der Zaehler in lib/zahl.sh zaehlt jede Zeile doppelt.
- [ ] Ich baue den Zaehler morgen neu.
- [ ] ctrl-z: Bitte den Lauf vor dem Merge wiederholen.
- [ ] Halt, bitte nicht mergen bevor der Lauf gruen ist.'
SS_SESSION=ss20 save --carrier ww3d/playbook#20 --transcript "$tx20"
expect 'ten chat points: five carried, five still open, exit 3' 3 "$rc"
expect 'ten chat points: five boxes left' 5 "$(SS_SESSION=ss20 list | grep -c '^- \[ \]')"
sed -i 's/^- \[ \] \(.*\)$/- [x] \1 -> https:\/\/example.invalid\/20/' "$proj/.agent/state/ss20-save.md"
SS_SESSION=ss20 save --carrier ww3d/playbook#20 --transcript "$tx20"
expect 'ten chat points: every point carried or ticked with a proof, exit 0' 0 "$rc"
# The pair file: a line per carried candidate, with the carrier line that holds it.
pairs="$(cat "$proj/.agent/state/ss20-pairs.md" 2>/dev/null)"
expect 'pairs: one line per carried candidate' 5 "$(grep -c ' => ww3d/playbook#20: ' <<< "$pairs")"
check_line 'pairs: line, kind, candidate, carrier and the carrier line' \
  'L5 promise: Ich baue den Zaehler morgen neu. => ww3d/playbook#20: - [ ] Ich baue den Zaehler morgen neu.' "$pairs"
check_contains 'pairs: a message pairs with its sender' 'message: ctrl-z: Bitte den Lauf vor dem Merge wiederholen. => ww3d/playbook#20: ' "$pairs"
check_not_contains 'pairs: a ticked box is no pair' 'Variante mit dem Cursor' "$pairs"
# Rebuilt each run: a candidate the carrier no longer holds leaves the pair file; no older copy stays behind.
body ww3d_playbook_20 '## Open points
- [ ] Mensch: Das ist schon wieder falsch, du liest die Traeger nicht.
- [ ] Befund: der Zaehler in lib/zahl.sh zaehlt jede Zeile doppelt.
- [ ] ctrl-z: Bitte den Lauf vor dem Merge wiederholen.
- [ ] Halt, bitte nicht mergen bevor der Lauf gruen ist.'
rm -f "$proj/.agent/state/ss20.json"
SS_SESSION=ss20 save --carrier ww3d/playbook#20 --transcript "$tx20"
pairs="$(cat "$proj/.agent/state/ss20-pairs.md" 2>/dev/null)"
expect 'rebuilt: four pairs after the carrier dropped one' 4 "$(grep -c ' => ' <<< "$pairs")"
check_not_contains 'rebuilt: the dropped pair is gone' 'Ich baue den Zaehler morgen neu. =>' "$pairs"
check_contains 'rebuilt: the dropped candidate is a box again' '- [ ] L5 2026-11-12T1005Z promise: Ich baue den Zaehler morgen neu.' "$(SS_SESSION=ss20 list)"
expect 'rebuilt: no older copy of the files under .agent/state/' 'ss20-pairs.md ss20-save.md' \
  "$(cd "$proj/.agent/state" && echo ss20*)"
# A pair line keeps each side to 400 characters.
long_s="Der lange Satz $(printf 'wort%.0s ' $(seq 1 120))endet hier."
tx21="$fix/ss21.jsonl"; fresh; human "$long_s" > "$tx21"
body ww3d_playbook_21 "$long_s"
SS_SESSION=ss21 save --carrier ww3d/playbook#21 --transcript "$tx21"
pl="$(head -n 1 "$proj/.agent/state/ss21-pairs.md" 2>/dev/null)"
cand="${pl%% => *}"; cand="${cand#L1 human: }"; spot="${pl#* => ww3d/playbook#21: }"
expect 'pairs: a long candidate is cut to 400 characters' 400 "${#cand}"
expect 'pairs: a long carrier line is cut to 400 characters' 400 "${#spot}"

# Gaps of state, rebuilt from the four types of the instance's report (ww3d/playbook#487): a plan line with an old
# state, an own comment with a wrong attribution, a promise without a delivery proof, a halt only in the chat.
# Ten cases; each stands afterwards as a pair (the pair helper judges it) or as a box, none drops out.
tx22="$fix/ss22.jsonl"; fresh
ss22=(
  'Stand: der Abgleich der Traeger ist fertig, die Liste fehlt noch.'
  'Stand: Teil 1 ist gemergt, Teil 2 laeuft im Web.'
  'Stand: die Doku ist eingetragen, der Index fehlt noch.'
  'Der Mensch hat die Variante b fuer den Export entschieden.'
  'Entschieden hat ctrl-x: der Cursor bleibt bei der uuid.'
  'Ich melde den Stand an ctrl-x sobald der Lauf gruen ist.'
  'Ich trage den Beleg in PR 31 nach, sobald der Lauf steht.'
  'Wir schicken die Liste heute an den Controller.'
  'Halt, den Merge von PR 30 bitte stoppen.'
  'Stopp, kein Push auf main bis morgen frueh.'
)
{ for i in 0 1 2 3 4 5 6 7; do said "${ss22[$i]}"; done; human "${ss22[8]}"; human "${ss22[9]}"; } > "$tx22"
body ww3d_playbook_22 "## Plan
- [ ] ${ss22[0]}
- [ ] ${ss22[1]}
- [ ] ${ss22[2]}
## Kommentar
${ss22[3]} ${ss22[4]}
## Zusagen
- ${ss22[5]}
- ${ss22[6]}
- ${ss22[7]}"
SS_SESSION=ss22 save --carrier ww3d/playbook#22 --transcript "$tx22"
pairs="$(cat "$proj/.agent/state/ss22-pairs.md" 2>/dev/null)"; l="$(SS_SESSION=ss22 list)"
for i in "${!ss22[@]}"; do
  if [ "$i" -lt 8 ]; then check_contains "state gaps: case $((i + 1)) stands as a pair" "${ss22[$i]} => ww3d/playbook#22: " "$pairs"
  else check_contains "state gaps: case $((i + 1)), a halt only in the chat, stands as a box" "- [ ] L$((i + 1)) " "$(grep -F "${ss22[$i]}" <<< "$l")"; fi
done
expect 'state gaps: eight pairs and two boxes, none drops out' '8 2' \
  "$(grep -c ' => ' <<< "$pairs") $(grep -c '^- \[ \]' <<< "$l")"

echo "== save-compact-state.sh: the instruction for the summary (ww3d/playbook#487) =="
sc() { save_event "$1" "$2" "$proj" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" bash "$save_cs" 2>&1; }
out="$(sc ss1 "$tx")"; rc=$?
expect 'summary: exit 0' 0 "$rc"
check_contains 'summary: it asks to keep open questions and promises verbatim' 'Behalte woertlich jede offene Frage' "$out"
check_contains 'summary: without a save it says so' 'keine Sicherung' "$out"
check_contains 'summary: it names the work list with its path' "$proj/.agent/state/ss1-save.md" "$out"
check_contains 'summary: the open question of the work list stands verbatim' 'open-question: Warum sperrt der Hook' "$out"
check_contains 'summary: an open promise stands verbatim' 'promise: Ich baue den Hook heute' "$out"
check_not_contains 'summary: a message box is not repeated' 'message: ctrl-x' "$out"
out="$(sc ss2 "$tx2")"
check_contains 'summary: it names the check line of the last save' "checked: " "$out"
check_contains 'summary: the check line carries the cursor' "cursor: " "$out"
for _ in $(seq 1 60); do printf -- '- [ ] L1 2026-11-12T1001Z promise: %s\n' "$(printf 'y%.0s' $(seq 1 300))"; done > "$proj/.agent/state/ss11-save.md"
out="$(sc ss11 "$tx")"
if [ ${#out} -lt 10000 ]; then ok 'summary: it stays under 10,000 characters' "${#out}"; else bad 'summary: under 10,000 characters' "${#out}" '< 10000'; fi
check_contains 'summary: a cut list says more stand in the file' 'weitere offene Kaesten' "$out"

out="$(sc ss2 "$tx2")"
check_contains 'summary: it names the next save call with transcript and session id' \
  "session-state.sh save --transcript '$tx2' --session ss2" "$out"
# The tool and the hook both ask for a save at the mark: the second save of a run without a new line since
# the cursor finds nothing.
tx48="$fix/ss48.jsonl"; fresh; human 'Bitte die Marke fuer beide Ausloeser pruefen und dann weiter.' > "$tx48"
SS_SESSION=ss48 save --transcript "$tx48"
expect 'twice: the first save lists the sentence of the human, exit 3' 3 "$rc"
SS_SESSION=ss48 list | sed 's/^- \[ \] \(.*\)$/- [x] \1 -> ww3d\/playbook#48/' > "$fix/ss48-ticked.md"
cp "$fix/ss48-ticked.md" "$proj/.agent/state/ss48-save.md"
SS_SESSION=ss48 save --transcript "$tx48"
expect 'twice: with the box ticked, exit 0' 0 "$rc"
SS_SESSION=ss48 save --transcript "$tx48"
expect 'twice: a second save without a new line since the cursor ends with 0' 0 "$rc"
expect 'twice: it writes no box' 0 "$(SS_SESSION=ss48 list | grep -c '^- \[')"
# A run that keeps no transcript (hl without persistence): the save fails and names the transcript.
SS_SESSION=ss49 save --transcript "$fix/ss49-missing.jsonl"
expect 'no transcript: exit 2' 2 "$rc"
check_contains 'no transcript: the output names it' "$fix/ss49-missing.jsonl" "$out"

finish
