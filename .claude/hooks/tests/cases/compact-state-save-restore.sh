#!/usr/bin/env bash
# Hook suite section: save-compact-state.sh / restore-compact-state.sh, EINLESEN after a compaction
# Run alone: bash .claude/hooks/tests/cases/compact-state-save-restore.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== save-compact-state.sh / restore-compact-state.sh: EINLESEN after a compaction (ww3d/playbook#487) =="
# Whole lines equal to the first argument in the text of the second, without a process.
cs_cnt() { # line, text -> the number
  local n=0 l
  while IFS= read -r l || [ -n "$l" ]; do [ "$l" = "$1" ] && n=$((n + 1)); done <<<"$2"
  echo "$n"
}
cs_heads() { grep '^## ' "$1" 2>/dev/null | tr -d '\r' | tr '\n' '|'; } # file -> its section headings, each ending in |
cs_eight='## Step and todos|## Rule files to reread|## History without a carrier|## Carriers changed since checked|'
cs_eight+="## The maintainer's sentences since the cursor|## Messages of other sessions since the cursor|"
cs_eight+='## Helper results since the cursor|## Tool additions|'

# --- save-compact-state.sh: the rule files read before the compaction ---
for m in core.agents pr code; do : > "$cs_gate/cs1-read-main-$m"; done
: > "$cs_gate/cs1-read-agent-a1-docs"
out="$(cs_save cs1 "$fix/compact-state-part.jsonl" 2>&1)"; rc=$?
expect 'save: rc 0' 0 "$rc"; check_contains 'save: stdout is the instruction for the summary' 'Anweisung fuer die Zusammenfassung' "$out"
saved="$(cat "$cs_gate/cs1-compact-rules" 2>/dev/null)"
check_line 'save: the line count before the compaction' "lines=$(wc -l < "$fix/compact-state-part.jsonl" | tr -d ' ')" "$saved"
check_line 'save: AGENTS.md from core.agents' 'AGENTS.md' "$saved"
check_line 'save: a rule file from its trigger' '.agents/rules/pr.md' "$saved"
check_not_contains 'save: a sub-agent read is left out' 'docs.md' "$saved"
# The lock's own marker and the gapless-read state name no rule file; a rule file read in parts still is one.
for m in compact.restore compact.restore.upto chat.upto chat; do : > "$cs_gate/cs25-read-main-$m"; done
cs_save cs25 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
saved="$(cat "$cs_gate/cs25-compact-rules" 2>/dev/null)"
check_not_contains 'save: no lock marker as a rule file' 'compact.' "$saved"
check_not_contains 'save: no .upto state as a rule file' 'upto' "$saved"
check_line 'save: a rule file read in parts stays' '.agents/rules/chat.md' "$saved"
# read-confirm.sh deletes the read markers on a compact start; the saved list stays.
printf '%s\n' '{"session_id":"cs1","hook_event_name":"SessionStart","source":"compact"}' \
  | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
absent_file 'read-confirm.sh clears the read markers on compact' "$cs_gate/cs1-read-main-pr"
present_file 'the saved list survives that clear' "$cs_gate/cs1-compact-rules"
# A skill reference no file matches keeps its marker name.
: > "$cs_gate/cs15-read-main-skill-nosuch-skill-ref"
cs_save cs15 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
check_contains 'save: an unresolved skill reference is kept' 'skill reference nosuch-skill-ref' "$(cat "$cs_gate/cs15-compact-rules" 2>/dev/null)"
out="$(cs_save cs8 "$fix/no-such-transcript.jsonl" 2>&1)"; rc=$?
expect 'save, missing transcript: rc 0' 0 "$rc"; check_contains 'save, missing transcript: the instruction still comes' 'Anweisung fuer die Zusammenfassung' "$out"
check_line 'save, missing transcript: the line count is 0' 'lines=0' "$(cat "$cs_gate/cs8-compact-rules" 2>/dev/null)"
out="$(printf 'not json at all' | TMPDIR="$cs_tmp" bash "$save_cs" 2>&1)"; rc=$?
expect 'garbage payload: save rc 0, no output' '0:' "$rc:$out"
: > "$fix/cs-not-a-dir"
js "$fix/compact-state.jsonl"
out="$(printf '{"session_id":"cs9x","transcript_path":%s,"cwd":"/"}\n' "$REPLY" | TMPDIR="$fix/cs-not-a-dir" bash "$save_cs" 2>&1)"; rc=$?
expect 'save, no folder to write to: rc 0, no output' '0:' "$rc:$out"

# --- restore without a save state: from line 1, eight sections, the hint, the lock ---
out="$(cs_restore cs1 "$fix/compact-state.jsonl" 2>&1)"; rc=$?
expect 'restore: rc 0' 0 "$rc"
f="$(cs_rfile cs1)"; body="$(cat "$f" 2>/dev/null)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
msg="$(printf '%s' "$out" | jq -r '.systemMessage' 2>/dev/null)"
expect 'restore: eight sections in their order' "$cs_eight" "$(cs_heads "$f")"
n="$(wc -l < "$f" | tr -d ' ')"; k="$(grep -c '^- \[ \]' "$f")"
check_contains 'restore: the visible line names file, lines and open boxes' "Restore written: " "$msg"
check_contains 'restore: the visible line counts lines and open boxes' "($n lines, $k open boxes)" "$msg"
check_contains 'restore: the hint says to read the file in full' 'in full with the Read tool' "$ctx"
check_contains 'restore: the hint says how to read a file too large for one read' 'in parts with offset and limit' "$ctx"
check_contains 'restore: the hint names the file under .agent/state' 'cs1-restore.md' "$ctx"
check_not_contains 'restore: nothing blocks' '"decision"' "$out"
check_not_contains 'restore: no carriage return in the output' $'\r' "$out"
absent_file 'restore: the saved rule list is used once' "$cs_gate/cs1-compact-rules"
lock="$(cat "$cs_gate/cs1-compact-lock" 2>/dev/null)"
check_contains 'restore: the lock needs the restore file' 'need=compact.restore ' "$lock"
check_contains 'restore: the lock needs chat.md' 'need=chat ' "$lock"
expect 'restore: the lock has two needs' 2 "$(grep -c '^need=' "$cs_gate/cs1-compact-lock" 2>/dev/null)"
check_line 'restore: the lock ends at the transcript end' "to=$(wc -l < "$fix/compact-state.jsonl" | tr -d ' ')" "$lock"
check_line 'restore: the step is the last own text before the compaction' 'Step: Antwort drei.' "$body"
check_line 'restore: the skill line is the last skill call' 'Skill: skill dev-task org/repo#1' "$body"
check_line 'restore: the todos of the last TodoWrite' '- [in_progress] Hooks bauen' "$body"
check_line 'restore: a rule file read before is listed' '- .agents/rules/pr.md' "$body"
check_not_contains 'restore: a rule path that is no file in the project is left out' 'AGENTS.md' "$body"
check_contains 'restore: no save state reads from line 1' 'Since the cursor: no cursor: from line 1.' "$body"
check_contains 'restore: without carriers every candidate is a box' 'No carrier named at the last save (or no save)' "$body"
check_contains 'restore: without checkedAt the carriers are not checked' 'Not checked: no save with exit 0 in this session (no checkedAt).' "$body"
check_line 'restore: without the variable the further channel is not checked' 'further channel: not checked' "$body"
check_line 'restore: without the variable the tool additions are not checked' 'tool additions: not checked' "$body"
check_line "restore: the maintainer's sentence whole" 'Bitte pruefe Zebrafant und Quokkabaum genau.' \
  "$(cs_sect "The maintainer's sentences since the cursor" "$f")"
check_not_contains 'restore: no section for own answers' '## Own' "$body"
check_not_contains 'restore: no section for the start order' 'Start order' "$body"
check_not_contains 'restore: a ghp_ token is masked in the file' 'ghp_ABCDEF' "$body"
check_not_contains 'restore: an sk-ant- token is masked in the file' 'sk-ant-api03-abc' "$body"
check_contains 'restore: the mask is visible' 'ghp_[masked]' "$body"

# Todos from TaskCreate/TaskUpdate; a deleted task is left out.
cs_restore cs3 "$fix/compact-state-tasks.jsonl" >/dev/null 2>&1
body="$(cat "$(cs_rfile cs3)" 2>/dev/null)"
check_line 'tasks: a completed task' '- [completed] #1 Erste Aufgabe' "$body"
check_line 'tasks: an open task' '- [pending] #2 Zweite Aufgabe' "$body"
check_not_contains 'tasks: a deleted task is left out' 'Dritte Aufgabe' "$body"
# The work step is the newest own text of the transcript: the main thread's boundary comes only after the hook, a
# boundary in the transcript belongs to an earlier compaction. A read receipt is no step.
cs_restore cs4 "$fix/compact-state-open-step.jsonl" >/dev/null 2>&1
check_line 'step: the newest own text' 'Step: Ich zaehle jetzt die Labels plan/* je Repo nach und melde den Stand.' \
  "$(cs_sect 'Step and todos' "$(cs_rfile cs4)")"
check_not_contains 'step: no line for an open own sentence' 'Open own sentence' "$(cat "$(cs_rfile cs4)" 2>/dev/null)"
cs_restore cs5 "$fix/compact-state-open-step-proven.jsonl" >/dev/null 2>&1
check_line 'step: a later own text wins' 'Step: Ich habe die Labels gezaehlt.' "$(cs_sect 'Step and todos' "$(cs_rfile cs5)")"
fresh
{ said 'Ich baue den Export Seidenreiher weiter.'; said '+ .agents/rules/pr.md 26.0.0 0c8c559 read (rule)'; } > "$fix/cs-receipt.jsonl"
cs_restore cs45 "$fix/cs-receipt.jsonl" >/dev/null 2>&1
check_line 'step: a read receipt as the newest text is skipped, the text before it is the step' \
  'Step: Ich baue den Export Seidenreiher weiter.' "$(cs_sect 'Step and todos' "$(cs_rfile cs45)")"
fresh; { said 'OLD STEP'; boundary; summary 'Summary.'; said 'NEW STEP'; } > "$fix/cs-oldbound.jsonl"
cs_restore cs49 "$fix/cs-oldbound.jsonl" >/dev/null 2>&1
st="$(cs_sect 'Step and todos' "$(cs_rfile cs49)")"
check_line 'step: a text after an earlier boundary is the step' 'Step: NEW STEP' "$st"
check_not_contains 'step: the text before an earlier boundary is not the step' 'OLD STEP' "$st"
fresh; { human 'Nur eine Frage Laubfrosch.'; boundary; } > "$fix/cs-notext.jsonl"
cs_restore cs46 "$fix/cs-notext.jsonl" >/dev/null 2>&1
check_line 'step: without an own text none is found' 'Step: none found' "$(cs_sect 'Step and todos' "$(cs_rfile cs46)")"
# The edges: a slash command after the skill call is the skill line; meta and sidechain lines are no input.
cs_restore cs17 "$fix/compact-state-edges.jsonl" >/dev/null 2>&1
f="$(cs_rfile cs17)"; body="$(cat "$f" 2>/dev/null)"
check_line 'edges: a slash command after the skill call is the skill line' 'Skill: /review org/repo#3' "$(cs_sect 'Step and todos' "$f")"
check_not_contains 'edges: a meta line is no input' 'Lemurlicht' "$body"
check_not_contains 'edges: a sidechain input is left out' 'Marderhund' "$body"
check_contains 'edges: a <cross-session-message> is a message' 'Peer ohne Absender Tukan.' \
  "$(cs_sect 'Messages of other sessions since the cursor' "$f")"
# Built-in slash commands are neither the step nor an input.
cs_restore cs22 "$fix/compact-state-filtered.jsonl" >/dev/null 2>&1
check_line 'filtered: the skill call before /compact stays the skill line' 'Skill: skill dev-task org/repo#4' \
  "$(cs_sect 'Step and todos' "$(cs_rfile cs22)")"

# --- the rule files to reread ---
# Only files there in the project: AGENTS.md and code.md read before stay off a project without them.
cs_save cs11 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs11 "$fix/compact-state.jsonl" >/dev/null 2>&1
check_contains 'rules: a save without rule reads is not a missing save' '_none: no rule file was read' "$(cat "$(cs_rfile cs11)" 2>/dev/null)"
cs_restore cs28 "$fix/compact-state.jsonl" >/dev/null 2>&1
check_contains 'rules: no save is said' '_no save found' "$(cat "$(cs_rfile cs28)" 2>/dev/null)"
: > "$cs_gate/cs27-read-main-chat"; : > "$cs_gate/cs27-read-main-local-naming"; : > "$cs_gate/cs27-read-main-core.agents"
cs_save cs27 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs27 "$fix/compact-state.jsonl" >/dev/null 2>&1
body="$(cat "$(cs_rfile cs27)" 2>/dev/null)"
expect 'rules: a file read before is listed once' 1 "$(cs_cnt '- .agents/rules/chat.md' "$body")"
check_line 'rules: the local rule read before is listed' '- .agents/rules/local/naming.md' "$body"
check_not_contains 'rules: the unread local rule is not listed' 'local/ci-silence.md' "$body"
check_not_contains 'rules: a read file missing in the project is not listed' 'AGENTS.md' "$body"
# Ten rule files read before the compaction are listed once; the next compaction without new reads
# asks for none again.
r10="$fix/cs-r10"; mkdir -p "$r10/.agents/rules"
for i in 1 2 3 4 5 6 7 8 9 10; do : > "$r10/.agents/rules/r$i.md"; : > "$cs_gate/cs9-read-main-r$i"; done
cs_save cs9 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs9 "$fix/compact-state.jsonl" "$PATH" "$r10" >/dev/null 2>&1
expect 'ten rule files: each listed once' 10 "$(grep -c '^- \.agents/rules/r[0-9]*\.md$' "$(cs_rfile cs9 "$r10")" 2>/dev/null)"
printf '%s\n' '{"session_id":"cs9","hook_event_name":"SessionStart","source":"compact"}' \
  | CLAUDE_PROJECT_DIR="$r10" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
cs_save cs9 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs9 "$fix/compact-state.jsonl" "$PATH" "$r10" >/dev/null 2>&1
check_contains 'ten rule files: the next compaction asks for none again' '_none: no rule file was read' "$(cat "$(cs_rfile cs9 "$r10")" 2>/dev/null)"
expect 'ten rule files: the lock still needs only the restore file' 1 "$(grep -c '^need=' "$cs_gate/cs9-compact-lock" 2>/dev/null)"

# --- from the cursor of the last save ---
tc="$fix/cs-cursor.jsonl"; fresh
{
  human 'Vor dem Cursor Albatrosfeder.'
  peer ctrl-a 'Vor dem Cursor Seehundbank.'
  agent toolu_v1 'Vor dem Cursor Helfer Kranichzug.'
  said 'Gesichert.'                                                                    # L5, the cursor
  human 'Nach dem Cursor bitte den Zebrafant pruefen.'
  summary 'This session is being continued from a previous conversation that ran out of context. Otterbau.'
  human 'This session is being continued from a previous conversation that ran out of context. Biberdamm.'
  human '<system-reminder>Erinnerung Lurchteich.</system-reminder>'
  js '<task-notification><summary>Background command "lauf" completed</summary></task-notification>'
  line "\"type\":\"user\",\"origin\":{\"kind\":\"task-notification\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  peer ctrl-b 'Peer-Satz Pelikan kurz vor der Verdichtung.'                           # L11
  agent toolu_n1 'Befund nach dem Cursor: der Grenzwert Fuchsbau ist falsch.'         # L12, L13
  said 'Ich baue den Grenzwert Fuchsbau neu.'                                          # L14
  boundary
  summary 'Summary: Fuchsbau. Pending Tasks: - Grenzwert Fuchsbau neu bauen'
  notice 'Hintergrund-Ergebnis Dachsfaehrte nach der Verdichtung.'                   # L17
} > "$tc"
cs_state "$cs_proj" cs30 5 2026-11-12T1005Z 2026-11-12T10:05:00Z
tool="$fix/cs-tool.sh"
# shellcheck disable=SC2016 # the stand-in tool script holds $1 and $2 as text for its own run
printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in' \
  '  extra) printf "Zusatz Lachsfang\n  eingerueckt bleibt eingerueckt\n" ;;' \
  '  changed) printf "Kanal: Antwort Seidenreiher seit %s\n" "$2" ;;' 'esac' > "$tool"
out="$(PLAYBOOK_CARRIER_TEXT_CMD="bash $tool" cs_restore cs30 "$tc" 2>&1)"; rc=$?
expect 'cursor: rc 0' 0 "$rc"
f="$(cs_rfile cs30)"; body="$(cat "$f" 2>/dev/null)"
expect 'cursor: eight sections in their order' "$cs_eight" "$(cs_heads "$f")"
check_contains 'cursor: the history starts behind the cursor' 'Since the cursor: cursor: after L5 (uuid 00000005-aaaa-4bbb-8ccc-dddddddddddd).' "$body"
for w in Albatrosfeder Seehundbank Kranichzug; do check_not_contains "cursor: nothing before it ($w)" "$w" "$body"; done
hs="$(cs_sect "The maintainer's sentences since the cursor" "$f")"
check_line "cursor: the maintainer's sentence with line and time" '### L6 2026-11-12T1006Z' "$hs"
check_line "cursor: the maintainer's sentence whole" 'Nach dem Cursor bitte den Zebrafant pruefen.' "$hs"
for w in Otterbau Biberdamm Lurchteich 'Background command'; do
  check_not_contains "summary and system text: no maintainer sentence ($w)" "$w" "$hs"
  check_not_contains "summary and system text: no box ($w)" "$w" "$(cs_sect 'History without a carrier' "$f")"
done
ms="$(cs_sect 'Messages of other sessions since the cursor' "$f")"
check_line 'cursor: a message minutes before the compaction, with its sender' '### L11 2026-11-12T1011Z ctrl-b' "$ms"
check_line 'cursor: the message whole' 'Peer-Satz Pelikan kurz vor der Verdichtung.' "$ms"
hr="$(cs_sect 'Helper results since the cursor' "$f")"
check_line 'cursor: a helper result whole' 'Befund nach dem Cursor: der Grenzwert Fuchsbau ist falsch.' "$hr"
check_contains 'cursor: a background helper result after the compaction' 'Hintergrund-Ergebnis Dachsfaehrte nach der Verdichtung.' "$hr"
check_line 'cursor: an own promise the summary only carries stands as a box' \
  '- [ ] L14 2026-11-12T1014Z promise: Ich baue den Grenzwert Fuchsbau neu.' "$(cs_sect 'History without a carrier' "$f")"
cc="$(cs_sect 'Carriers changed since checked' "$f")"
check_line 'cursor: a save without carriers is said' 'Not checked: the last save named no carrier.' "$cc"
check_line 'further channel: its heading names the check time' 'Further channel (PLAYBOOK_CARRIER_TEXT_CMD changed 2026-11-12T1005Z):' "$cc"
check_line 'further channel: its output in the section' 'Kanal: Antwort Seidenreiher seit 2026-11-12T1005Z' "$cc"
ta="$(cs_sect 'Tool additions' "$f")"
check_line 'tool additions: the output verbatim' 'Zusatz Lachsfang' "$ta"
check_line 'tool additions: indentation kept' '  eingerueckt bleibt eingerueckt' "$ta"
# The background result after the compaction is a candidate of the next save.
use_forge "$fix/cs-forge"
(cd "$cs_proj" && PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" \
  CLAUDE_CODE_SESSION_ID=cs30 bash "$hooks/session-state.sh" save --transcript "$tc" >/dev/null 2>&1)
check_contains 'background helper result: a box of the next save' 'Dachsfaehrte' "$(cat "$cs_proj/.agent/state/cs30-save.md" 2>/dev/null)"

# Each run writes the file anew; no older version stays.
cs_state "$cs_proj" cs31 5 2026-11-12T1005Z 2026-11-12T10:05:00Z
cs_restore cs31 "$tc" >/dev/null 2>&1
fresh; { human 'Zweiter Lauf Kormoranfeder.'; } > "$fix/cs-second.jsonl"
rm -f "$cs_proj/.agent/state/cs31.json"
cs_restore cs31 "$fix/cs-second.jsonl" >/dev/null 2>&1
body="$(cat "$(cs_rfile cs31)" 2>/dev/null)"
check_contains 'second run: the new content' 'Zweiter Lauf Kormoranfeder.' "$body"
check_not_contains 'second run: nothing of the first' 'Pelikan' "$body"
expect 'second run: one restore file only' "$(cs_rfile cs31)" "$(echo "$cs_proj"/.agent/state/cs31*restore*)"

# Fourteen messages and ten helper results since the cursor, each whole: no cap, nothing left out.
long="$(printf '%2500s' '' | tr ' ' w)"
t14="$fix/cs-14-10.jsonl"; fresh
{
  said 'Gesichert.'
  for i in $(seq 1 14); do peer "ctrl-p$i" "Nachricht $i Anfang $long Ende $i."; done
  for i in $(seq 1 10); do agent "toolu_h$i" "Helfer $i Anfang $long Ende $i."; done
  boundary
} > "$t14"
cs_state "$cs_proj" cs32 1 2026-11-12T1001Z 2026-11-12T10:01:00Z
cs_restore cs32 "$t14" >/dev/null 2>&1
f="$(cs_rfile cs32)"
ms="$(cs_sect 'Messages of other sessions since the cursor' "$f")"; hr="$(cs_sect 'Helper results since the cursor' "$f")"
expect '14 messages: each an entry' 14 "$(grep -c '^### L' <<<"$ms")"
expect '10 helper results: each an entry' 10 "$(grep -c '^### L' <<<"$hr")"
n=0; for i in $(seq 1 14); do has_line "Nachricht $i Anfang $long Ende $i." "$ms" && n=$((n + 1)); done
expect '14 messages: each word for word, uncut' 14 "$n"
n=0; for i in $(seq 1 10); do has_line "Helfer $i Anfang $long Ende $i." "$hr" && n=$((n + 1)); done
expect '10 helper results: each word for word, uncut' 10 "$n"
check_not_contains 'no entry left out' 'left out' "$(cat "$f" 2>/dev/null)"

# The tool additions: a failing command and one over the time limit are said; the rest of the file stays.
printf '#!/usr/bin/env bash\nexit 7\n' > "$fix/cs-tool-fail.sh"
PLAYBOOK_CARRIER_TEXT_CMD="bash $fix/cs-tool-fail.sh" cs_restore cs33 "$tc" >/dev/null 2>&1
check_contains 'tool additions: a failure is said' 'tool additions: not checked (PLAYBOOK_CARRIER_TEXT_CMD extra failed, exit 7)' \
  "$(cs_sect 'Tool additions' "$(cs_rfile cs33)")"
# A timeout stand-in answers 124 for the tool's extra call, as the real one does at its limit.
cs_to="$fix/cs-timeout"; mkdir -p "$cs_to"
printf '#!/usr/bin/env bash\ncase " $* " in *" extra "*) exit 124 ;; esac\nexec "%s" "$@"\n' "$(command -v timeout)" > "$cs_to/timeout"
chmod +x "$cs_to/timeout"
PLAYBOOK_CARRIER_TEXT_CMD="bash $tool" cs_restore cs34 "$tc" "$cs_to:$PATH" >/dev/null 2>&1
f="$(cs_rfile cs34)"
check_contains 'tool additions: the time limit is said' 'tool additions: not checked (PLAYBOOK_CARRIER_TEXT_CMD extra timed out after 60 s)' \
  "$(cs_sect 'Tool additions' "$f")"
check_contains 'tool additions: the time limit keeps the rest' 'Peer-Satz Pelikan' "$(cat "$f" 2>/dev/null)"

# --- fail-open ---
use_csnojq
: > "$cs_gate/cs35-read-main-pr"; cs_save cs35 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
out="$(cs_restore cs35 "$fix/compact-state.jsonl" "$csnojq" 2>&1)"; rc=$?
f="$(cs_rfile cs35)"
expect 'without jq: rc 0' 0 "$rc"
check_contains 'without jq: the hint says so' 'jq is missing' "$out"
expect 'without jq: still eight sections' "$cs_eight" "$(cs_heads "$f")"
check_line 'without jq: the saved rule list' '- .agents/rules/pr.md' "$(cat "$f" 2>/dev/null)"
present_file 'without jq: the lock stands' "$cs_gate/cs35-compact-lock"
out="$(cs_restore cs6 "$fix/no-such-transcript.jsonl" 2>&1)"; rc=$?
expect 'missing transcript: rc 0' 0 "$rc"
check_contains 'missing transcript: the hint says so' 'the transcript was not found' "$out"
csjqfail="$fix/cs-jqfail"; mkdir -p "$csjqfail"
printf '#!/usr/bin/env bash\nexit 5\n' > "$csjqfail/jq"; chmod +x "$csjqfail/jq"
out="$(cs_restore cs19 "$fix/compact-state.jsonl" "$csjqfail:$PATH" 2>&1)"; rc=$?
expect 'jq failing: rc 0' 0 "$rc"
check_contains 'jq failing: the hint names the cause' 'jq could not read the transcript' "$out"
check_contains 'jq failing: the rule list is still there' 'Rule files to reread' "$(cat "$(cs_rfile cs19)" 2>/dev/null)"
out="$(printf 'not json at all' | TMPDIR="$cs_tmp" bash "$restore_cs" 2>&1)"; rc=$?
expect 'garbage payload: restore rc 0, no output' '0:' "$rc:$out"
js "$fix/compact-state.jsonl"
out="$(printf '{"session_id":"cs36","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$fix/cs-not-a-dir" CLAUDE_PROJECT_DIR="$cs_proj" bash "$restore_cs" 2>&1)"; rc=$?
expect 'restore, no folder to write to: rc 0, no output' '0:' "$rc:$out"
out="$(restore_event cs37 "$fix/compact-state.jsonl" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="" "$BASH" "$restore_cs" 2>&1)"; rc=$?
expect 'no project root: rc 0, no output' '0:' "$rc:$out"
absent_file 'no project root: no lock' "$cs_gate/cs37-compact-lock"
# Without CLAUDE_PROJECT_DIR the payload's cwd names the project.
js "$fix/compact-state.jsonl"; t="$REPLY"; js "$cs_proj"
printf '{"session_id":"cs29","transcript_path":%s,"cwd":%s,"source":"compact"}\n' "$t" "$REPLY" \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="" "$BASH" "$restore_cs" >/dev/null 2>&1
present_file 'the cwd names the project' "$(cs_rfile cs29)"
# A control character in an input keeps the output valid JSON.
cs_cf="$fix/compact-state-ctrl.jsonl"
{ printf '%s\n' '{"type":"user","message":{"role":"user","content":"Farbe \u001b[31mrot\u001b[0m und \u0007 Glocke Kranichzug."},"origin":{"kind":"human"}}'
  printf '%s\n' '{"type":"system","subtype":"compact_boundary"}'; } > "$cs_cf"
out="$(cs_restore cs16 "$cs_cf" 2>&1)"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then ok 'control characters: the output is valid JSON' valid
else bad 'control characters: the output is valid JSON' invalid valid; fi
check_contains 'control characters: the input still in the file' 'Kranichzug' "$(cat "$(cs_rfile cs16)" 2>/dev/null)"
# Windows forms of the paths: a transcript path with escaped backslashes; the hint names the file in Windows form.
if command -v cygpath >/dev/null 2>&1; then
  js "$(cygpath -w "$fix/compact-state.jsonl")"
  out="$(printf '{"session_id":"cs13","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
    | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" bash "$restore_cs" 2>/dev/null)"
  check_line 'windows: a backslash transcript path is read' 'Bitte pruefe Zebrafant und Quokkabaum genau.' "$(cat "$(cs_rfile cs13)" 2>/dev/null)"
  check_contains 'windows: the hint names the file in Windows form' "$(cygpath -w "$(cs_rfile cs13)")" \
    "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then ok 'windows: the output is valid JSON' valid
  else bad 'windows: the output is valid JSON' invalid valid; fi
else
  echo '  skip windows path forms: no cygpath here'
fi

# Every token shape is masked, in the save as in the restore.
cs_tokens=(ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 github_pat_ABCDEFGHIJKLMNOPQRSTUVWX_0123
  sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123 sk-abcdefghijklmnopqrstuvwxyz0123 xoxb-1234567890-abcdefghij
  AKIAABCDEFGHIJKLMNOP glpat-abcdefghijklmnopqrstu 'Bearer abcdefghijklmnopqrstuvwxyz.0123')
cs_masked=('ghp_[masked]' 'github_pat_[masked]' 'sk-ant-[masked]' 'sk-[masked]' 'xoxb-[masked]'
  'AKIA[masked]' 'glpat-[masked]' 'Bearer [masked]')
cs_tf="$fix/compact-state-tokens.jsonl"
for t in "${cs_tokens[@]}"; do
  js "Token $t hier."; printf '{"type":"user","message":{"role":"user","content":%s},"origin":{"kind":"human"}}\n' "$REPLY"
done > "$cs_tf"
for t in "${cs_tokens[@]}"; do : > "$cs_gate/cs14-read-main-local-$t"; done
cs_save cs14 "$cs_tf" >/dev/null 2>&1
saved="$(cat "$cs_gate/cs14-compact-rules" 2>/dev/null)"
cs_restore cs14 "$cs_tf" >/dev/null 2>&1
body="$(cat "$(cs_rfile cs14)" 2>/dev/null)"
for i in "${!cs_tokens[@]}"; do
  t="${cs_tokens[$i]}"
  check_not_contains "mask: ${t:0:6}... not in the save" "${t: -8}" "$saved"
  check_not_contains "mask: ${t:0:6}... not in the restore file" "${t: -8}" "$body"
  check_line "mask: ${t:0:6}... masked in the restore file" "Token ${cs_masked[$i]} hier." "$body"
done

# --- a helper's compaction: no file, no lock, the main thread's reads stay ---
hx() { rm -f "$cs_gate/$1-compaction-owner"; } # session -> a fresh owner log
owner() { tail -n 1 "$cs_gate/$1-compaction-owner" 2>/dev/null | cut -d' ' -f1-2; }
t1="$fix/cs-h1.jsonl"; fresh
{ human 'Pruef das bitte mit einem Helfer.'; call toolu_f1 Agent '{"description":"Pruefung","prompt":"x"}'; } > "$t1"
hx cs40; out="$(cs_restore cs40 "$t1" 2>&1)"; rc=$?
expect 'helper, a foreground call waits: rc 0, no output' '0:' "$rc:$out"
absent_file 'helper, a foreground call waits: no restore file' "$(cs_rfile cs40)"
absent_file 'helper, a foreground call waits: no lock' "$cs_gate/cs40-compact-lock"
expect 'helper, a foreground call waits: the owner log says why' 'helper signals=1' "$(owner cs40)"
: > "$cs_gate/cs40-read-main-pr"
printf '{"session_id":"cs40","transcript_path":"%s","hook_event_name":"SessionStart","source":"compact"}\n' "$t1" \
  | CLAUDE_PROJECT_DIR="$cs_proj" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
present_file "helper: read-confirm.sh keeps the main thread's reads" "$cs_gate/cs40-read-main-pr"
out="$(save_event cs40 "$t1" "$cs_proj" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" bash "$save_cs" 2>&1)"; rc=$?
expect 'helper: save-compact-state.sh says nothing' '0:' "$rc:$out"
absent_file 'helper: save-compact-state.sh saves no rule list' "$cs_gate/cs40-compact-rules"
fresh
{ human 'Starte den Helfer im Hintergrund.'; call toolu_b1 Agent '{"description":"Pruefung","prompt":"x","run_in_background":true}'; } > "$fix/cs-h1bg.jsonl"
hx cs41; cs_restore cs41 "$fix/cs-h1bg.jsonl" >/dev/null 2>&1
present_file 'main, a background call does not wait: the restore file' "$(cs_rfile cs41)"
expect 'main, a background call does not wait: the owner log' 'main signals=' "$(owner cs41)"
# Signal 2: a boundary in a sub-agent's file; its time comes from the line, relative to now.
t2="$fix/cs-h2.jsonl"; fresh; { human 'Weiter.'; said 'Ich arbeite weiter am Export.'; } > "$t2"
mkdir -p "$fix/cs-h2/subagents"
sub_boundary() { # seconds ago -> the sub-agent file's newest line is a boundary of that age
  printf '{"type":"system","subtype":"compact_boundary","timestamp":"%s"}\n' \
    "$(date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%S.000Z)" > "$fix/cs-h2/subagents/agent-a1.jsonl"
}
pc_save() { # session, [model of the payload] -> PreCompact through save-compact-state.sh, its output in global out
  local m=""
  [ -z "${2:-}" ] || m=",\"model\":\"$2\""
  out="$(save_event "$1" "$t2" "$cs_proj" | sed "s/}\$/$m}/" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$cs_proj" bash "$save_cs" 2>&1)"
}
# On SessionStart a helper's boundary stands before the hook: alone it marks the helper within 10 s.
sub_boundary 1; hx cs42; : > "$cs_gate/cs42-read-main-pr"
out="$(cs_restore cs42 "$t2" "$PATH" "$cs_proj" claude-opus-5-5 2>&1)"; rc=$?
expect 'start, a helper boundary 1 s before, same model: rc 0, no output' '0:' "$rc:$out"
absent_file 'start, a helper boundary 1 s before, same model: no restore file' "$(cs_rfile cs42)"
absent_file 'start, a helper boundary 1 s before, same model: no lock' "$cs_gate/cs42-compact-lock"
expect 'start, a helper boundary 1 s before, same model: the owner log' 'helper signals=2' "$(owner cs42)"
restore_event cs42 "$t2" claude-opus-5-5 | CLAUDE_PROJECT_DIR="$cs_proj" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
present_file 'start, a helper boundary 1 s before, same model: the read marks stay' "$cs_gate/cs42-read-main-pr"
# The main thread's own compaction: its boundary comes only after the hook, no sub-agent boundary stands.
rm -f "$fix/cs-h2/subagents/agent-a1.jsonl"; hx cs43; : > "$cs_gate/cs43-read-main-pr"
cs_restore cs43 "$t2" "$PATH" "$cs_proj" claude-opus-5-5 >/dev/null 2>&1
present_file 'start, no helper boundary: the restore file' "$(cs_rfile cs43)"
present_file 'start, no helper boundary: the lock' "$cs_gate/cs43-compact-lock"
expect 'start, no helper boundary: the owner log' 'main signals=' "$(owner cs43)"
restore_event cs43 "$t2" claude-opus-5-5 | CLAUDE_PROJECT_DIR="$cs_proj" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
absent_file 'start, no helper boundary: the read marks go' "$cs_gate/cs43-read-main-pr"
# A helper boundary 15 s old on SessionStart is outside the 10 s: the main thread's compaction.
sub_boundary 15; hx ch5
cs_restore ch5 "$t2" "$PATH" "$cs_proj" claude-opus-5-5 >/dev/null 2>&1
present_file 'start, a helper boundary 15 s old: the restore file' "$(cs_rfile ch5)"
present_file 'start, a helper boundary 15 s old: the lock' "$cs_gate/ch5-compact-lock"
expect 'start, a helper boundary 15 s old: the owner log' 'main signals=' "$(owner ch5)"
# PreCompact keeps 60 s and needs signals 2 and 3 together.
sub_boundary 30; hx ch6; pc_save ch6 claude-sonnet-5
expect 'precompact, boundary 30 s old and another model: says nothing' '' "$out"
absent_file 'precompact, boundary 30 s old and another model: no rule list' "$cs_gate/ch6-compact-rules"
check_contains 'precompact, boundary 30 s old and another model: both named' 'helper signals=2 3' "$(tail -n 1 "$cs_gate/ch6-compaction-owner" 2>/dev/null)"
hx ch7; pc_save ch7 claude-opus-5-5
present_file 'precompact, boundary 30 s old and the same model: the rule list' "$cs_gate/ch7-compact-rules"
expect 'precompact, boundary 30 s old and the same model: the owner log' 'main signals=2' "$(owner ch7)"
sub_boundary 90; hx ch8; pc_save ch8 claude-sonnet-5
present_file 'precompact, boundary 90 s old and another model: the rule list' "$cs_gate/ch8-compact-rules"
expect 'precompact, boundary 90 s old and another model: the owner log' 'main signals=3' "$(owner ch8)"
# The window edges: 10 s on SessionStart, 60 s on PreCompact, 2 s either side (1 s is the clock's own step).
sub_boundary 8; hx ch9; cs_restore ch9 "$t2" "$PATH" "$cs_proj" claude-opus-5-5 >/dev/null 2>&1
expect 'start, a helper boundary 8 s old: helper' 'helper signals=2' "$(owner ch9)"
absent_file 'start, a helper boundary 8 s old: no restore file' "$(cs_rfile ch9)"
sub_boundary 12; hx ch10; cs_restore ch10 "$t2" "$PATH" "$cs_proj" claude-opus-5-5 >/dev/null 2>&1
expect 'start, a helper boundary 12 s old: main' 'main signals=' "$(owner ch10)"
present_file 'start, a helper boundary 12 s old: the restore file' "$(cs_rfile ch10)"
sub_boundary 58; hx ch11; pc_save ch11 claude-sonnet-5
expect 'precompact, boundary 58 s old and another model: helper' 'helper signals=2' "$(owner ch11)"
sub_boundary 62; hx ch12; pc_save ch12 claude-sonnet-5
expect 'precompact, boundary 62 s old and another model: main' 'main signals=3' "$(owner ch12)"
# Signal 1 for a waiting Task call, not only Agent.
t3="$fix/cs-h3.jsonl"; fresh
{ human 'Pruef das bitte.'; call toolu_t1 Task '{"description":"Pruefung","prompt":"x"}'; } > "$t3"
hx ch13; out="$(cs_restore ch13 "$t3" 2>&1)"
expect 'helper, a foreground Task call waits: the owner log' 'helper signals=1' "$(owner ch13)"
absent_file 'helper, a foreground Task call waits: no restore file' "$(cs_rfile ch13)"
expect 'helper, a foreground Task call waits: no output' '' "$out"

# Senders without a name in the origin: from the delivery head, else from the first word.
fresh
{
  js '[rc · from Fischadler · msg_01AbC9 · 2026-11-12T1001Z] Bitte den Export Rotmilan pruefen.'
  line "\"type\":\"user\",\"origin\":{\"kind\":\"peer\",\"from\":\"unknown\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
  js 'Seeadler: Der Export Rotmilan ist durch.'
  line "\"type\":\"user\",\"origin\":{\"kind\":\"peer\",\"from\":\"unknown\"},\"message\":{\"role\":\"user\",\"content\":$REPLY}"
} > "$fix/cs-senders.jsonl"
cs_restore cs50 "$fix/cs-senders.jsonl" >/dev/null 2>&1
ms="$(cs_sect 'Messages of other sessions since the cursor' "$(cs_rfile cs50)")"
check_line 'sender: read from the delivery head with its id' '### L1 2026-11-12T1001Z Fischadler' "$ms"
check_line 'sender: without a head, the first word' '### L2 2026-11-12T1002Z Seeadler' "$ms"

# Boxes count only in the history and the changed carriers: "- [ ]" lines quoted in a helper result are text.
fresh
{ said 'Ich melde den Stand Kormoranflug am Abend.'; agent toolu_q1 $'Befund:\n- [ ] x\n- [ ] x'; } > "$fix/cs-quoted.jsonl"
out="$(cs_restore cs51 "$fix/cs-quoted.jsonl" 2>&1)"
f="$(cs_rfile cs51)"
real="$({ cs_sect 'History without a carrier' "$f"; cs_sect 'Carriers changed since checked' "$f"; } | grep -c '^- \[ \]')"
check_contains 'quoted boxes: the helper result keeps them as text' '- [ ] x' "$(cs_sect 'Helper results since the cursor' "$f")"
check_contains 'quoted boxes: the hint counts only the real boxes' "lines, $real open boxes)" "$out"
expect 'quoted boxes: two real boxes, the promise and the helper result, none for the quoted lines' 2 "$real"
expect 'quoted boxes: no quoted line as a box in the history' 0 "$(cs_sect 'History without a carrier' "$f" | grep -cxF -- '- [ ] x')"
# SessionStart with another model and an old boundary: signal 3 alone stays the main thread's.
printf '{"type":"system","subtype":"compact_boundary","timestamp":"2026-01-01T00:00:00.000Z"}\n' > "$fix/cs-h2/subagents/agent-a1.jsonl"
hx cs44; cs_restore cs44 "$t2" "$PATH" "$cs_proj" claude-sonnet-5 >/dev/null 2>&1
present_file 'main, signal 3 alone (an old sub-agent boundary): the restore file' "$(cs_rfile cs44)"
expect 'main, signal 3 alone: the owner log' 'main signals=3' "$(owner cs44)"

# The start order of the session (.agent/brief.md) stands in the list to read again after a compaction.
bp="$fix/cs-brief-proj"; mkdir -p "$bp/.agent" "$bp/.agents/rules"; printf 'Auftrag\n' > "$bp/.agent/brief.md"
fresh; human 'Bitte weiter.' > "$fix/cs-brief.jsonl"
cs_restore csb "$fix/cs-brief.jsonl" "$PATH" "$bp" >/dev/null 2>&1
rr="$(cs_sect 'Rule files to reread' "$(cs_rfile csb "$bp")")"
check_line 'brief: the start order is in the reread list' '- .agent/brief.md' "$rr"
check_contains 'brief: the list says to read it again now' 'The start order (.agent/brief.md)' "$rr"
check_contains 'brief: without a save the note of the missing save stays' 'no save found: the PreCompact hook did not run' "$rr"
cs_restore csn "$fix/cs-brief.jsonl" >/dev/null 2>&1
check_not_contains 'brief: no start order file, no line' 'brief.md' "$(cs_sect 'Rule files to reread' "$(cs_rfile csn)")"

finish
