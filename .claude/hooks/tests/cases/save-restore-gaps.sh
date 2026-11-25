#!/usr/bin/env bash
# Hook suite section: the gaps of save and restore (ww3d/playbook#672) - the state check of the references, the save
# window, the restore lock of /controller-mode, the compaction check, the read parts of a large restore file and the
# truth receipt after a restore.
# Run alone: bash .claude/hooks/tests/cases/save-restore-gaps.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# No network: gh is gh-double.sh over a world file, the channel a script over a JSON file.
# shellcheck disable=SC2016 # jq text and commands as text, not shell
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

g="$fix/gaps"; mkdir -p "$g/bin" "$g/proj/.agent/state" "$g/tmp/claude-rule-gate"
printf '#!/usr/bin/env bash\nexec bash "%s/tests/gh-double.sh" "$@"\n' "$hooks" > "$g/bin/gh"; chmod +x "$g/bin/gh"
printf '#!/usr/bin/env bash\n[ "$1" = status ] && jq -e --arg q "$2" ".[\\$q] // empty" "%s/channel.json" || exit 1\n' "$g" > "$g/channel.sh"
gate="$g/tmp/claude-rule-gate"
export GH_DOUBLE_WORLD="$g/world.json" TICKS_TIMEOUT=5 STATE_CACHE_DIR="$g/state-cache"
node() { # ref, type, state, body
  jq -nc --arg r "$1" --arg ty "$2" --arg st "$3" --arg b "$4" '{__typename: $ty, id: "I\($r)", state: $st, body: $b,
    url: ($r | capture("^(?<o>[^#]+)#(?<n>[0-9]+)$") | "https://github.com/\(.o)/\(if $ty == "PullRequest" then "pull" else "issues" end)/\(.n)"),
    author: {login: "alice"}, createdAt: "2026-11-20T08:00:00Z", updatedAt: "2026-11-20T11:30:00Z", title: "T",
    userContentEdits: {nodes: []}, comments: {nodes: []}, timelineItems: {nodes: []}}'
}
carrier_body='Text des Traegers. Bau weiter.

## Open points

- [ ] Draft o/r#3 offen, wartet auf Review
- [ ] PR #3 laeuft noch
- [ ] Frage 900 offen, wartet auf Antwort
- [ ] o/r#2 ist offen
- [x] o/r#3 gemergt'
new_world() {
  jq -n --argjson i1 "$(node 'o/r#1' Issue OPEN "$carrier_body")" --argjson i2 "$(node 'o/r#2' Issue OPEN 'zwei')" \
    --argjson i3 "$(node 'o/r#3' PullRequest MERGED 'drei')" \
    '{user: "bot", issues: {"o/r#1": $i1, "o/r#2": $i2, "o/r#3": $i3}, commits: {}, search: []}' > "$GH_DOUBLE_WORLD"
  rm -f "$GH_DOUBLE_WORLD".down "$GH_DOUBLE_WORLD".down-path "$GH_DOUBLE_WORLD".calls
  jq -n '{q900: {status: "beantwortet", erstelltAm: "2026-11-20T10:30:00Z", issue: "o/r#1",
            nachrichten: [{at: "2026-11-20T11:05:00Z", von: "Mensch", text: "ja"}]}}' > "$g/channel.json"
}
ss() { # session, args... -> out, rc
  local s="$1"; shift
  out="$(cd "$g/proj" && PATH="$g/bin:$PATH" TMPDIR="$g/tmp" CLAUDE_PROJECT_DIR="$g/proj" CLAUDE_CODE_SESSION_ID="$s" \
    PLAYBOOK_CARRIER_TEXT_CMD="bash $g/channel.sh" bash "$hooks/session-state.sh" "$@" 2>&1)"; rc=$?
}
wl() { cat "$g/proj/.agent/state/$1-save.md" 2>/dev/null; }
# The list of the cut the save list names: the tool ticks there, the save list is not updated (lib/cutlist.sh).
wlc_view() { sed -n 's/^List of this cut: \(.*\) - close its boxes there.*$/\1/p' "$g/proj/.agent/state/$1-save.md" | tr -d '\r'; }
wlc() { cat "$(wlc_view "$1")" 2>/dev/null; }
wlc_side() { local v; v="$(wlc_view "$1")"; printf '%s.json' "${v%.md}"; }

echo "== save: the state of every reference in the pairs and open boxes (ww3d/playbook#672) =="
new_world
tx="$g/s1.jsonl"; fresh
{ human 'Bau weiter.'; said 'Die Arbeit laeuft.'; } > "$tx"
ss s1 save --carrier 'o/r#1' --transcript "$tx" --session s1
expect 'stale: a box that contradicts its reference holds the save, exit 3' 3 "$rc"
check_contains 'stale: "offen" beside a merged pull request is a box' 'stale: Draft o/r#3 offen, wartet auf Review — o/r#3 ist MERGED (Stand 2026-11-20T11:30:00Z)' "$(wl s1)"
check_contains 'stale: "#N" belongs to the repo of its carrier' 'stale: PR #3 laeuft noch — o/r#3 ist MERGED' "$(wl s1)"
check_contains 'stale: "Frage N" waits on an answered question' 'stale: Frage 900 offen, wartet auf Antwort — q900 ist beantwortet (Stand 2026-11-20T11:05:00Z)' "$(wl s1)"
check_not_contains 'stale: an open issue that says open is no box' 'o/r#2 ist' "$(wl s1)"
check_not_contains 'stale: a ticked box is not checked' 'gemergt —' "$(wl s1)"
expect 'stale: one resolve_snapshot a save (one GraphQL call)' 1 "$(grep -c '^api graphql' "$GH_DOUBLE_WORLD.calls")"
# A stand box of the save list closes like the one of the restore file (ww3d/playbook#734): at a carrier of the save,
# once the stand check finds no contradiction there; the whole line is no core a reference could hold.
sb() { # box id, reference -> out, rc of a close in a tool call of its own
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_sb%s","name":"Bash"}]}}\n' "$RANDOM$RANDOM" >> "$g/sb-tool.jsonl"
  # The close one second after the list, not by the real clock: evidence of the list's own second does not count.
  local now; now="$(jq -r '.created | fromdate + 1 | todate' "$(wlc_side s1)")"
  out="$(cd "$g/proj" && PATH="$g/bin:$PATH" TMPDIR="$g/tmp" CLAUDE_PROJECT_DIR="$g/proj" TICKS_TRANSCRIPT="$g/sb-tool.jsonl" TICKS_NOW="$now" \
    PLAYBOOK_CARRIER_TEXT_CMD="bash $g/channel.sh" bash "$hooks/ticks.sh" close "$1" erledigt "$2" --list "$g/proj/.agent/state/s1-save.md" 2>&1)"; rc=$?
}
sbk="$(wl s1 | grep -F 'stale: Draft o/r#3 offen' | grep -o -E '^- \[ \] K[0-9]+' | cut -d' ' -f4)"
sb "$sbk" 'o/r#2'
expect 'stand box of the save list: a reference that is no carrier of the save is refused' 1 "$rc"
check_contains '  it names the carriers of the save' 'no carrier of the last save: o/r#1' "$out"
sb "$sbk" 'o/r#1'
expect 'stand box of the save list: refused while the contradiction stands at the carrier' 1 "$rc"
check_contains '  it names the contradiction' 'the contradiction stands at o/r#1' "$out"
jq '.issues["o/r#1"].body |= (sub("- \\[ \\] Draft o/r#3 offen, wartet auf Review\n"; "") | sub("- \\[ \\] PR #3 laeuft noch\n"; ""))' "$GH_DOUBLE_WORLD" > "$g/w.tmp" \
  && mv "$g/w.tmp" "$GH_DOUBLE_WORLD"; rm -rf "$STATE_CACHE_DIR"
sb "$sbk" 'o/r#1'
expect 'stand box of the save list: the line fixed at the carrier, the box closes' 0 "$rc"
check_contains '  the box is ticked' "- [x] $sbk " "$(wlc s1)"
# The forge cannot answer the state: no box and no green, the check line says how many were not checked.
new_world; printf 'graphql' > "$GH_DOUBLE_WORLD.down-path"; echo '{}' > "$g/channel.json"
ss s2 save --carrier 'o/r#1' --transcript "$tx" --session s2
expect 'not checked: no box, exit 0' 0 "$rc"
check_contains 'not checked: the check line counts them' 'stale check: 3 not checked (' "$out"
check_contains 'not checked: it stands in the state file' 'stale check: 3 not checked' "$(cat "$g/proj/.agent/state/s2.json")"
# The number of a message in a thread names no issue; a reference beside it still counts.
jd() { bash -c ". '$hooks/lib/state.sh'; jq -n -r --arg t \"\$1\" \"\$state_stale_defs\"' \$t | judged(\"o/r\") | join(\" \")'" _ "$1"; }
expect 'stale: "Nachricht #10 und #11" names no issue' 'q1410' "$(jd 'Abnahme in q1410 Nachricht #10 und #11 (offen)')"
expect 'stale: "(Nachricht #2)" names no issue' '' "$(jd 'Rueckfrage beantwortet (Nachricht #2), Frage wieder offen')"
expect 'stale: "Nachfrage #2", "Verlauf #1" and "message #3" name none, "#7" does' 'o/r#7' \
  "$(jd 'Nachfrage #2: offen, Verlauf #1, message #3, #7 offen')"
# The pair file: a pair whose carrier line a pattern judges is left to the state check.
new_world
fresh
{ human 'Draft o/r#3 offen, wartet auf Review'; human 'Ich schreibe den Text des Traegers neu.'; } > "$g/s3.jsonl"
jq --arg b "$carrier_body
- [ ] Ich schreibe den Text des Traegers neu." '.issues["o/r#1"].body = $b' "$GH_DOUBLE_WORLD" > "$g/w" && mv "$g/w" "$GH_DOUBLE_WORLD"
ss s3 save --carrier 'o/r#1' --transcript "$g/s3.jsonl" --session s3
pf="$(cat "$g/proj/.agent/state/s3-pairs.md" 2>/dev/null)"
check_not_contains 'pairs: a pair with a status word is not in the pair file' 'wartet auf Review' "$pf"
check_contains 'pairs: a plain pair stays' 'Ich schreibe den Text des Traegers neu' "$pf"
# Many references with long names: more than a Windows command line holds, every one judged.
long='an-owner-with-a-rather-long-name/a-repository-with-a-long-name'
jq -n --arg o "$long" '{user: "bot", commits: {}, search: [], issues: ([range(1; 701)] | map({key: "\($o)#\(.)",
  value: {__typename: "PullRequest", id: "I\(.)", state: "MERGED", updatedAt: "2026-11-20T11:30:00Z", body: "x"}}) | from_entries)}' \
  > "$GH_DOUBLE_WORLD"; rm -f "$GH_DOUBLE_WORLD".calls
jq -n -c --arg o "$long" 'range(1; 701) | {l: 0, ts: "-", repo: "o/r", text: "Draft \($o)#\(.) offen"}' > "$g/many.jsonl"
mkdir -p "$g/many"; many="$(PATH="$g/bin:$PATH" bash -c ". '$hooks/lib/state.sh'; state_stale '$g/many.jsonl' '$g/many'" | grep -c .)"
expect 'stale: 700 long references (over 32 KB) give 700 boxes' 700 "$many"
expect 'stale: and no note' '' "$(cat "$g/many/stale.note")"

echo "== save: the save window drops the own sentences about the save (ww3d/playbook#672) =="
new_world
fresh
{
  human 'Sicher jetzt.'
  call toolu_s1 Bash '{"command":"bash .claude/hooks/session-state.sh save --session s4"}'
  result toolu_s1 'exit 3'
  said 'Die Sicherung meldet drei Kaesten.'
  said 'Ich hake die Kaesten jetzt ab.'
  said 'Danach sichere ich erneut.'
  said 'Das Skript laeuft noch einmal.'
  said 'Ich trage die Arbeitsliste nach.'
  said 'Die Check-Zeile kommt gleich.'
  said 'Gesichert ist es dann bald.'
  said 'Ich verdichte danach.'
  said 'Der Save ist fast durch.'
  said 'Den Hand-back schreibe ich danach.'
  said 'Ich hake den letzten Kasten ab.'
  said 'Die Sicherung laeuft erneut.'
  said 'Abgehakt ist alles bis auf einen.'
  said 'Das Skript gibt gleich Exit 0.'
  said 'Nach der Sicherung baue ich #1490 fertig.'
  said 'Sobald gesichert, schicke ich dir die Auswertung.'
  peer ctrl-x 'Wie weit ist die Sicherung?'
} > "$g/s4.jsonl"
ss s4 save --carrier 'o/r#1' --transcript "$g/s4.jsonl" --session s4
check_contains 'window: a promise with a reference stays a box' 'Nach der Sicherung baue ich #1490 fertig.' "$(wl s4)"
check_contains 'window: a promise to someone stays a box' 'Sobald gesichert, schicke ich dir die Auswertung.' "$(wl s4)"
check_contains 'window: a message in the window stays a box' 'Wie weit ist die Sicherung?' "$(wl s4)"
meta="$(wl s4 | grep -c -E 'Kaesten|sichere ich|Skript|Arbeitsliste|Check-Zeile|Gesichert ist|verdichte|Save ist|Hand-back|Kasten ab|laeuft erneut|Abgehakt')"
expect 'window: the 14 sentences about the save give at most one box' yes "$([ "$meta" -le 1 ] && echo yes || echo "$meta")"
# The same sentences outside a window: the maintainer's input closes it.
fresh
{ call toolu_s2 Bash '{"command":"bash .claude/hooks/session-state.sh save --session s5"}'; human 'Gut.'
  said 'Ich hake die Kaesten heute Abend ab.'; } > "$g/s5.jsonl"
ss s5 save --carrier 'o/r#1' --transcript "$g/s5.jsonl" --session s5
check_contains 'window: an input of the maintainer ends it' 'Ich hake die Kaesten heute Abend ab.' "$(wl s5)"

echo "== /controller-mode: no step before the restore of the predecessor (ww3d/playbook#672) =="
new_world
gate_out() { # session, tool, tool_input json, [agent_id] -> the gate's output
  local a=""; [ -z "${4:-}" ] || a=",\"agent_id\":\"$4\""
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s%s}' \
    "$1" "$g/s1.jsonl" "$2" "$3" "$a" | TMPDIR="$g/tmp" CLAUDE_PROJECT_DIR="$g/proj" bash "$ruleread" 2>&1
}
locked() { case "$(gate_out "$@")" in *'reads its predecessor first'*) printf LOCK ;; *) printf PASS ;; esac; }
gate_out c1 Skill '{"skill":"controller-mode"}' > /dev/null
present_file 'lock: the Skill call /controller-mode leaves the marker' "$gate/c1-restore-owed"
expect 'lock: a Bash call before the restore is refused' LOCK "$(locked c1 Bash '{"command":"gh pr list"}')"
expect 'lock: an edit before the restore is refused' LOCK "$(locked c1 Edit '{"file_path":"x"}')"
expect 'lock: a sub-agent is free' PASS "$(locked c1 Bash '{"command":"gh pr list"}' agent-1)"
expect 'lock: the restore itself passes' PASS "$(locked c1 Bash '{"command":"bash .claude/hooks/session-state.sh restore --none \"Erststart\""}')"
expect 'lock: a restore chained with another command is refused' LOCK "$(locked c1 Bash '{"command":"bash .claude/hooks/session-state.sh restore --none x; rm -rf y"}')"
check_contains 'lock: the refusal names both ways' 'restore --none \"<reason>\"' "$(gate_out c1 Bash '{"command":"ls"}')"
printf 'predecessor: ctrl-pb-59 · carrier: o/r#1\n' > "$g/proj/.agent/brief.md"
check_contains 'lock: a start order with the predecessor gives the finished command' 'restore --from o/r#1 --predecessor ctrl-pb-59' "$(gate_out c1 Bash '{"command":"ls"}')"
rm -f "$g/proj/.agent/brief.md"
expect 'lock: a session without /controller-mode is free' PASS "$(locked c9 Bash '{"command":"gh pr list"}')"
printf '{"session_id":"c2","hook_event_name":"UserPromptExpansion","command_name":"controller-mode"}' \
  | TMPDIR="$g/tmp" CLAUDE_PROJECT_DIR="$g/proj" bash "$ruleread" > /dev/null 2>&1
present_file 'lock: a typed /controller-mode leaves the marker' "$gate/c2-restore-owed"
ss c1 restore --from 'o/r#1' --predecessor ctrl-pb-59
expect 'lock: restore --from writes, exit 0' 0 "$rc"
absent_file 'lock: restore --from lifts it' "$gate/c1-restore-owed"
gate_out c3 Skill '{"skill":"controller-mode"}' > /dev/null
ss c3 restore --from 'https://github.com/o/r/issues/1'
expect 'lock: --from takes the issue URL' 0 "$rc"
absent_file 'lock: the URL form lifts it too' "$gate/c3-restore-owed"
ss c2 restore --none ''
expect 'lock: --none without a reason, exit 1' 1 "$rc"
present_file 'lock: an empty reason keeps it' "$gate/c2-restore-owed"
ss c2 restore --none 'Erststart, der Sitz ist neu'
expect 'lock: --none with its reason, exit 0' 0 "$rc"
absent_file 'lock: --none lifts it' "$gate/c2-restore-owed"
use_csnojq
gate_out c4 Skill '{"skill":"controller-mode"}' > /dev/null
out="$(cd "$g/proj" && PATH="$csnojq" TMPDIR="$g/tmp" CLAUDE_PROJECT_DIR="$g/proj" CLAUDE_CODE_SESSION_ID=c4 \
  "$BASH" "$hooks/session-state.sh" restore --none 'Erststart' 2>&1)"; rc=$?
expect 'lock: --none without jq fails, exit 2' 2 "$rc"
absent_file 'lock: --none without jq lifts it all the same' "$gate/c4-restore-owed"
expect 'lock: after it a call passes' PASS "$(locked c4 Bash '{"command":"ls"}')"
cut="$(grep '"session":"c2"' "$g/proj/.agent/state/cuts.jsonl" 2>/dev/null | tail -n 1)"
expect 'lock: --none stands in cuts.jsonl with its reason' 'no-predecessor|Erststart, der Sitz ist neu' \
  "$(printf '%s' "$cut" | jq -r '"\(.cut)|\(.reason)"' 2>/dev/null)"

echo "== restore after a compaction: did the instruction for the summary arrive (ww3d/playbook#672) =="
new_world
cl='checked: 2026-11-21T1000Z · cursor: x.jsonl L2 u2'
st() { jq -n --arg c "$cl" '{checkLine: $c}' > "$cs_proj/.agent/state/$1.json"; }
mkdir -p "$cs_proj/.agent/state"
fresh; { human 'Weiter.'; boundary; summary "Zusammenfassung. Check-Zeile: $cl. Schritt: Bau."; } > "$g/k-ok.jsonl"
fresh; { human 'Weiter.'; boundary; summary 'Zusammenfassung ohne die Zeile.'; } > "$g/k-miss.jsonl"
fresh; { human 'Weiter.'; boundary; } > "$g/k-none.jsonl"
hist() { cs_sect 'History without a carrier' "$(cs_rfile "$1")"; }
st k1; cs_restore k1 "$g/k-ok.jsonl" > /dev/null 2>&1
check_contains 'compaction: no marker instructed=1 is a box' '- [ ] compaction instruction did not arrive (save-compact-state.sh did not finish' "$(hist k1)"
st k2; printf 'lines=3\ninstructed=1\n' > "$cs_gate/k2-compact-rules"; cs_restore k2 "$g/k-miss.jsonl" > /dev/null 2>&1
check_contains 'compaction: the check line missing in the summary is a box' 'the check line of the last save is not in the summary' "$(hist k2)"
st k3; printf 'lines=3\ninstructed=1\n' > "$cs_gate/k3-compact-rules"; cs_restore k3 "$g/k-ok.jsonl" > /dev/null 2>&1
check_not_contains 'compaction: marker and check line there, no box' 'compaction instruction' "$(hist k3)"
st k4; printf 'lines=3\ninstructed=1\n' > "$cs_gate/k4-compact-rules"; cs_restore k4 "$g/k-none.jsonl" > /dev/null 2>&1
check_contains 'compaction: no summary in the transcript is a line' 'compaction check: not checkable (no summary in the transcript' "$(hist k4)"
check_not_contains 'compaction: no summary, no box' 'compaction instruction' "$(hist k4)"
# An earlier compaction's summary before the save's cursor (L4) is not the summary of this one.
fresh; { human 'Weiter.'; boundary; summary "Alt. Check-Zeile: $cl."; said 'Gesichert.'; human 'Weiter.'; } > "$g/k-old.jsonl"
{ cat "$g/k-old.jsonl"; boundary; summary 'Neu, ohne die Zeile.'; } > "$g/k-oldmiss.jsonl"
fresh; { human 'Weiter.'; boundary; summary 'Alt.'; said 'Gesichert.'; human 'Weiter.'; boundary
  summary "Neu. Check-Zeile: $cl."; } > "$g/k-oldok.jsonl"
stc() { jq -n --arg c "$cl" '{checkLine: $c, cursor: {line: 4}}' > "$cs_proj/.agent/state/$1.json"
  printf 'lines=3\ninstructed=1\n' > "$cs_gate/$1-compact-rules"; }
stc k5; cs_restore k5 "$g/k-old.jsonl" > /dev/null 2>&1
check_contains 'compaction: only a summary before the cursor is not checkable' 'compaction check: not checkable' "$(hist k5)"
check_not_contains 'compaction: a summary before the cursor makes no box' 'compaction instruction' "$(hist k5)"
stc k6; cs_restore k6 "$g/k-oldmiss.jsonl" > /dev/null 2>&1
check_contains 'compaction: the new summary without the line is a box, the old one with it aside' \
  'the check line of the last save is not in the summary' "$(hist k6)"
stc k7; cs_restore k7 "$g/k-oldok.jsonl" > /dev/null 2>&1
check_not_contains 'compaction: the new summary with the line after an old one, no box' 'compaction instruction' "$(hist k7)"

echo "== restore: the read parts of a file above 25,000 tokens (ww3d/playbook#672) =="
# Four inputs of 300 lines: one argument stays under the 32 KB of a Windows command line.
big="$(printf 'Satz Nummer %s ueber den Stand der Arbeit, lang genug fuer viele Zeilen.\n' $(seq 1 300))"
fresh; { human 'Kurz.'; } > "$g/p-small.jsonl"
fresh; { human "$big"; human "$big"; said 'Ich melde den Stand Kranichzug.'; human "$big"; human "$big"; } > "$g/p-big.jsonl"
printf 'instructed=1\n' > "$cs_gate/p1-compact-rules"; out="$(cs_restore p1 "$g/p-small.jsonl" 2>&1)"
check_not_contains 'parts: under 25,000 tokens no part hint' 'in these parts' "$out"
printf 'instructed=1\n' > "$cs_gate/p2-compact-rules"; out="$(cs_restore p2 "$g/p-big.jsonl" 2>&1)"
f="$(cs_rfile p2)"; total="$(wc -l < "$f" | tr -d ' ')"
parts="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -o 'offset=[0-9]* limit=[0-9]*')"
gapless="$(printf '%s\n' "$parts" | awk -v t="$total" '{ split($1, o, "="); split($2, l, "="); if (o[2] != next_) bad = 1; next_ = o[2] + l[2] }
  BEGIN { next_ = 1 } END { print (bad || next_ - 1 != t) ? "gap" : "gapless" }')"
expect 'parts: over 25,000 tokens the parts close up from line 1 to the last line' gapless "$gapless"
over="$(printf '%s\n' "$parts" | while read -r o l; do sed -n "${o#offset=},$(( ${o#offset=} + ${l#limit=} - 1 ))p" "$f" \
  | LC_ALL=C awk '{ c += length($0) + 8 } END { if (c > 27000) print "over" }'; done)"
expect 'parts: each part under 15,000 tokens' '' "$over"
expect 'parts: more than one part' yes "$([ "$(printf '%s\n' "$parts" | grep -c .)" -ge 2 ] && echo yes || echo no)"
while read -r o l; do lk_read p2 "$f" "${o#offset=} ${l#limit=} $total" "$cs_proj"; done <<< "$parts"
present_file 'parts: reading the named parts lifts the read duty' "$cs_gate/p2-read-main-compact.restore"
# Between 25,000 tokens and 60 KB: too large for one read already, so it gets parts too.
fresh; { human "$big"; said 'Ich melde den Stand Kranichzug.'; human "$big"; } > "$g/p-mid.jsonl"
printf 'instructed=1\n' > "$cs_gate/p3-compact-rules"; out="$(cs_restore p3 "$g/p-mid.jsonl" 2>&1)"
mid="$(wc -c < "$(cs_rfile p3)" | tr -d ' ')"
expect 'parts: the mid file lies under 60 KB' yes "$([ "$mid" -lt 61440 ] && echo yes || echo "$mid")"
check_contains 'parts: over 25,000 tokens and under 60 KB it gets parts' 'in these parts' "$out"

echo "== restore: the open boxes of the carriers against the state of their references (ww3d/playbook#672) =="
new_world
fresh; { human 'Weiter.'; said 'Gut.'; } > "$g/r.jsonl"
rst() { # session, transcript
  jq -n '{cursor: {line: 1, uuid: "x"}, checked: "2026-11-21T0900Z", checkedAt: "2026-11-21T09:00:00Z", carriers: ["o/r#1"]}' \
    > "$cs_proj/.agent/state/$1.json"
  printf 'instructed=1\n' > "$cs_gate/$1-compact-rules"
  cs_restore "$1" "$2" "$g/bin:$PATH" > /dev/null 2>&1
}
changed() { cs_sect 'Carriers changed since checked' "$(cs_rfile "$1")"; }
PLAYBOOK_CARRIER_TEXT_CMD="bash $g/channel.sh" rst t1 "$g/r.jsonl"
check_contains 'receipt: a box "offen" beside a merged pull request' '- [ ] stale: Draft o/r#3 offen, wartet auf Review — o/r#3 ist MERGED' "$(changed t1)"
check_not_contains 'receipt: a matching state is no box' 'o/r#2 ist offen —' "$(changed t1)"
printf 'graphql' > "$GH_DOUBLE_WORLD.down-path"; echo '{}' > "$g/channel.json"
PLAYBOOK_CARRIER_TEXT_CMD="bash $g/channel.sh" rst t2 "$g/r.jsonl"
check_contains 'receipt: the forge down is "not checked"' 'stale check: 3 not checked (' "$(changed t2)"
check_not_contains 'receipt: the forge down gives no stale box' '- [ ] stale:' "$(changed t2)"

finish
