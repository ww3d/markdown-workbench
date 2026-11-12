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
forge="$fix/ss-forge"; mkdir -p "$forge"
# The forge stand-in: `gh api repos/<o>/<r>/issues/<n> --jq ...` prints <forge>/<o>_<r>_<n>.md, logs the call,
# and fails for a number without a file.
mkdir -p "$fix/ss-bin"
cat > "$fix/ss-bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$SS_FORGE/calls.log"
k="${2#repos/}"; k="${k/\/issues\//_}"; k="${k//\//_}"
[ -r "$SS_FORGE/$k.md" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
cat "$SS_FORGE/$k.md"
EOF
chmod +x "$fix/ss-bin/gh"
body() { printf '%s\n' "$2" > "$forge/$1.md"; } # key owner_repo_N, text

# Transcript lines, one per call; the uuid counts up.
tx_n=0
line() { # json without uuid and timestamp -> one line with both
  tx_n=$((tx_n + 1))
  printf '{"uuid":"%08d-aaaa-4bbb-8ccc-dddddddddddd","timestamp":"2026-11-12T10:%02d:00.000Z",%s}\n' \
    "$tx_n" "$((tx_n % 60))" "$1"
}
fresh() { tx_n=0; } # a new transcript starts at line 1
human() { js "$1"; line "\"type\":\"user\",\"origin\":{\"kind\":\"human\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"; }
said() { js "$1"; line "\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":$REPLY}]}"; }
peer() { # name, body
  local n b; js "$1"; n="$REPLY"; js "$2"; b="$REPLY"
  js "Another Claude session sent a message: $2"
  line "\"type\":\"user\",\"isMeta\":true,\"origin\":{\"kind\":\"peer\",\"from\":\"unknown\",\"name\":$n,\"body\":$b},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
}
agent() { # id, result text
  local r; js "$2"; r="$REPLY"
  line "\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"$1\",\"name\":\"Agent\",\"input\":{}}]}"
  line "\"type\":\"user\",\"toolUseResult\":{\"status\":\"completed\"},\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$1\",\"content\":[{\"type\":\"text\",\"text\":$r}]}]}"
}
save() { # args... -> output, global rc; session ss1 unless SS_SESSION
  out="$(cd "$proj" && PATH="$fix/ss-bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
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
expect 'save: the mark for the cross-check after the compaction stands behind the saved line' '2 pre' "$(cat "$cs_gate/ss2-cross-check-mark" 2>/dev/null)"

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
out="$(cd "$fix/ss-elsewhere" && env -u CLAUDE_PROJECT_DIR PATH="$fix/ss-bin:$PATH" TMPDIR="$cs_tmp" \
  CLAUDE_CODE_SESSION_ID=ss17 bash "$ss" save --transcript "$tx17" 2>&1)"; rc=$?
present_file 'root: the work list lies in the project of the transcript' "$proj17/.agent/state/ss17-save.md"
absent_file 'root: not in the folder save ran in' "$fix/ss-elsewhere/.agent/state/ss17-save.md"

# A hanging fetch or channel ends at its time limit: a timeout stand-in that answers 124.
mkdir -p "$fix/ss-tobin"; printf '#!/usr/bin/env bash\nexit 124\n' > "$fix/ss-tobin/timeout"; chmod +x "$fix/ss-tobin/timeout"
out="$(cd "$proj" && PATH="$fix/ss-tobin:$fix/ss-bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  PLAYBOOK_CARRIER_TEXT_CMD="true" CLAUDE_CODE_SESSION_ID=ss18 bash "$ss" save --transcript "$tx15" 2>&1)"; rc=$?
check_contains 'timeout: the channel is named as timed out' 'PLAYBOOK_CARRIER_TEXT_CMD timed out' "$out"
out="$(cd "$proj" && PATH="$fix/ss-tobin:$fix/ss-bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
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
cr_save() { out="$(cd "$proj" && PATH="$fix/ss-crbin:$fix/ss-bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
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
