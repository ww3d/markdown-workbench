#!/usr/bin/env bash
# Hook suite section: save-compact-state.sh / restore-compact-state.sh, what a compaction can lose
# Run alone: bash .claude/hooks/tests/cases/compact-state-save-restore.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== save-compact-state.sh / restore-compact-state.sh: what a compaction can lose (ww3d/playbook#439) =="
# Whole lines equal to the first argument in the text of the second, without a process.
cs_cnt() { # line, text -> the number
  local n=0 l
  while IFS= read -r l || [ -n "$l" ]; do [ "$l" = "$1" ] && n=$((n + 1)); done <<<"$2"
  echo "$n"
}
# The same for a file; a missing file prints nothing.
cs_cnt_file() { # line, file
  [ -f "$2" ] || return 0
  cs_cnt "$1" "$(<"$2")"
}
# The first line of a text that starts with the prefix.
cs_first() { # prefix, text
  local l
  while IFS= read -r l; do [[ $l == "$1"* ]] && { printf '%s\n' "$l"; return 0; }; done <<<"$2"
}
# Lines of a text that start with one of the prefixes (the rest of the arguments), in order, each ending in |.
cs_pick() { # text, prefix...
  local t="$1" l p out=""; shift
  while IFS= read -r l; do for p in "$@"; do [[ $l == "$p"* ]] && { out+="$l|"; break; }; done; done <<<"$t"
  printf '%s' "$out"
}
for m in core.agents pr code; do : > "$cs_gate/cs1-read-main-$m"; done
: > "$cs_gate/cs1-read-agent-a1-docs"
out="$(cs_save cs1 "$fix/compact-state-part.jsonl" 2>&1)"; rc=$?
expect 'save: rc 0' 0 "$rc"; check_contains 'save: stdout is the instruction for the summary' 'Anweisung fuer die Zusammenfassung' "$out"
saved="$(cat "$cs_gate/cs1-compact-rules" 2>/dev/null)"
check_line 'save: the line count before the compaction' "lines=$(wc -l < "$fix/compact-state-part.jsonl" | tr -d ' ')" "$saved"
check_line 'save: AGENTS.md from core.agents' 'AGENTS.md' "$saved"
check_line 'save: a rule file from its trigger' '.agents/rules/pr.md' "$saved"
check_not_contains 'save: a sub-agent read is left out' 'docs.md' "$saved"
# The lock's own markers and the gapless-read state name no rule file (ww3d/playbook#487); a rule
# file read in parts still is one.
for m in compact.restore compact.crosscheck compact.restore.upto chat.upto chat; do : > "$cs_gate/cs25-read-main-$m"; done
cs_save cs25 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
saved="$(cat "$cs_gate/cs25-compact-rules" 2>/dev/null)"
check_not_contains 'save: no lock marker as a rule file' 'compact.' "$saved"
check_not_contains 'save: no .upto state as a rule file' 'upto' "$saved"
check_line 'save counter: the rule file itself stays' '.agents/rules/chat.md' "$saved"
# read-confirm.sh deletes the read markers on a compact start; the saved list stays.
printf '%s\n' '{"session_id":"cs1","hook_event_name":"SessionStart","source":"compact"}' \
  | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$cs_tmp" bash "$readconfirm" >/dev/null 2>&1
absent_file 'read-confirm.sh clears the read markers on compact' "$cs_gate/cs1-read-main-pr"
present_file 'the saved list survives that clear' "$cs_gate/cs1-compact-rules"

out="$(cs_restore cs1 "$fix/compact-state.jsonl" 2>&1)"; rc=$?
expect 'restore: rc 0' 0 "$rc"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
msg="$(printf '%s' "$out" | jq -r '.systemMessage' 2>/dev/null)"
cs_file="$cs_gate/cs1-compact-restore.md"; body="$(cat "$cs_file" 2>/dev/null)"
check_contains 'restore: the visible line names the file' 'Compact state restored:' "$msg"
check_not_contains 'restore: nothing blocks' '"decision"' "$out"
if [ "${#ctx}" -gt 0 ] && [ "${#ctx}" -lt 2000 ]; then ok 'restore: the hint stays under 2,000 characters' "${#ctx}"
else bad 'restore: the hint stays under 2,000 characters' "${#ctx}" '1..1999'; fi
check_contains 'restore: the hint says to read the file in full' 'in full with the Read tool' "$ctx"
check_contains 'restore: the hint says how to read a file too large for one read' 'in parts with offset and limit' "$ctx"
check_contains 'restore: the hint carries the line count' "($(wc -l < "$cs_file" | tr -d ' ') lines)" "$ctx"
check_contains 'restore: the hint names the file' 'cs1-compact-restore.md' "$ctx"
absent_file 'restore: the save is used once' "$cs_gate/cs1-compact-rules"
check_not_contains 'restore: no carriage return in the output' $'\r' "$out"
check_line 'restore: the start order is the first input' '/dev-task org/repo#1 Startauftrag Albatros' "$body"
expect 'restore: the short sections come first, the step leads' '## Step' "$(cs_first '## ' "$body")"
check_contains 'restore: a message of another session, verbatim' 'Peer-Satz Pelikan.' "$body"
check_line 'restore: with its sender and time' '### ctrl-test-7 - 2026-01-02T03:04:05.000Z' "$body"
check_line 'restore: a typed input of the maintainer' 'Bitte pruefe Zebrafant und Quokkabaum genau.' "$body"
check_line 'restore: a queued input of the maintainer' 'Nachgereicht Kolibriwolke.' "$body"
seq_="$(cs_pick "$body" 'Nachgereicht Kolibriwolke' 'Bitte pruefe')"
expect 'restore: the maintainer newest first' 'Nachgereicht Kolibriwolke.|Bitte pruefe Zebrafant und Quokkabaum genau.|' "$seq_"
check_line 'restore: an own answer to the maintainer, verbatim' 'Antwort eins zu Zebrafant.' "$body"
check_not_contains 'restore: no answer to another session' 'Antwort an den Peer.' "$body"
check_not_contains 'restore: no answer to a task notification' 'Antwort auf die Notiz.' "$body"
check_not_contains 'restore: nothing before the previous compaction' 'Antwort vor der ersten' "$body"
check_line 'restore: the step is the last skill call' 'skill dev-task org/repo#1' "$body"
check_line 'restore: the todos of the last TodoWrite' '- [in_progress] Hooks bauen' "$body"
check_line 'restore: the rule list to reread' '- .agents/rules/pr.md' "$body"
check_not_contains 'restore: a ghp_ token is masked in the file' 'ghp_ABCDEF' "$body"
check_not_contains 'restore: an sk-ant- token is masked in the file' 'sk-ant-api03-abc' "$body"
check_not_contains 'restore: no token in the hint' 'ghp_ABCDEF' "$ctx"
check_contains 'restore: the mask is visible' 'ghp_[masked]' "$body"
check_contains 'loss: an input the summary lacks is named' 'Bitte pruefe Zebrafant' "$ctx"
check_not_contains 'loss: an input the summary carries is not' 'Kolibriwolke' "$ctx"

# The boundary not written yet and no save: the part runs to the end, the loss line says so.
out="$(cs_restore cs2 "$fix/compact-state-part.jsonl" 2>&1)"; rc=$?
body="$(cat "$cs_gate/cs2-compact-restore.md" 2>/dev/null)"
expect 'no save: rc 0' 0 "$rc"
check_line 'no save: the newest input is in the part' 'Nachgereicht Kolibriwolke.' "$body"
check_contains 'no save: the rule list says the save is missing' '_no save found' "$body"
check_contains 'no save: the loss line says the helper does the loss check (REQ-042)' 'the cross-check helper does the loss check' "$out"

# Todos from TaskCreate/TaskUpdate; a deleted task is left out.
cs_restore cs3 "$fix/compact-state-tasks.jsonl" >/dev/null 2>&1
body="$(cat "$cs_gate/cs3-compact-restore.md" 2>/dev/null)"
check_line 'tasks: a completed task' '- [completed] #1 Erste Aufgabe' "$body"
check_line 'tasks: an open task' '- [pending] #2 Zweite Aufgabe' "$body"
check_not_contains 'tasks: a deleted task is left out' 'Dritte Aufgabe' "$body"

# The start order file outranks the first input.
printf 'Auftrag aus der Datei Seeadler.\n' > "$fix/cs-order.txt"
js "$fix/compact-state.jsonl"; printf '{"session_id":"cs4","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" PLAYBOOK_START_ORDER_FILE="$fix/cs-order.txt" bash "$restore_cs" >/dev/null 2>&1
body="$(cat "$cs_gate/cs4-compact-restore.md" 2>/dev/null)"
check_line 'start order: the file PLAYBOOK_START_ORDER_FILE names' 'Auftrag aus der Datei Seeadler.' "$body"
check_not_contains 'start order: then not the first input' 'Startauftrag Albatros' "$body"
js "$fix/compact-state.jsonl"
( cd "$fix" && printf '{"session_id":"cs7","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
    | TMPDIR="$cs_tmp" PLAYBOOK_START_ORDER_FILE="cs-order.txt" bash "$restore_cs" >/dev/null 2>&1 )
body="$(cat "$cs_gate/cs7-compact-restore.md" 2>/dev/null)"
check_line 'start order: a relative path is ignored' '/dev-task org/repo#1 Startauftrag Albatros' "$body"

# Fail-open: without jq, without a transcript, with a garbage payload.
use_csnojq
out="$(cs_restore cs5 "$fix/compact-state.jsonl" "$csnojq" 2>&1)"; rc=$?
expect 'without jq: rc 0' 0 "$rc"
check_contains 'without jq: the hint says so' 'jq is missing' "$out"
check_contains 'without jq: the rule list is still there' 'Rule files to reread' "$(cat "$cs_gate/cs5-compact-restore.md" 2>/dev/null)"
out="$(cs_restore cs6 "$fix/no-such-transcript.jsonl" 2>&1)"; rc=$?
expect 'missing transcript: rc 0' 0 "$rc"
check_contains 'missing transcript: the hint says so' 'the transcript was not found' "$out"
# jq present but failing on a readable transcript (a stand-in that exits 5): the cause is named, the rule list stays.
csjqfail="$fix/cs-jqfail"; mkdir -p "$csjqfail"
printf '#!/usr/bin/env bash\nexit 5\n' > "$csjqfail/jq"; chmod +x "$csjqfail/jq"
out="$(cs_restore cs19 "$fix/compact-state.jsonl" "$csjqfail:$PATH" 2>&1)"; rc=$?
expect 'jq failing: rc 0' 0 "$rc"
check_contains 'jq failing: the hint names the cause' 'jq could not read the transcript' "$out"
check_contains 'jq failing: the rule list is still there' 'Rule files to reread' "$(cat "$cs_gate/cs19-compact-restore.md" 2>/dev/null)"
out="$(printf 'not json at all' | TMPDIR="$cs_tmp" bash "$restore_cs" 2>&1)"; rc=$?
expect 'garbage payload: restore rc 0, no output' '0:' "$rc:$out"
out="$(printf 'not json at all' | TMPDIR="$cs_tmp" bash "$save_cs" 2>&1)"; rc=$?
expect 'garbage payload: save rc 0, no output' '0:' "$rc:$out"
out="$(cs_save cs8 "$fix/no-such-transcript.jsonl" 2>&1)"; rc=$?
expect 'save, missing transcript: rc 0' 0 "$rc"; check_contains 'save, missing transcript: the instruction still comes' 'Anweisung fuer die Zusammenfassung' "$out"
check_line 'save, missing transcript: the line count is 0' 'lines=0' "$(cat "$cs_gate/cs8-compact-rules" 2>/dev/null)"
: > "$fix/cs-not-a-dir"
js "$fix/compact-state.jsonl"
out="$(printf '{"session_id":"cs9","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$fix/cs-not-a-dir" bash "$restore_cs" 2>&1)"; rc=$?
expect 'restore, no folder to write to: rc 0, no output' '0:' "$rc:$out"
js "$fix/compact-state.jsonl"
out="$(printf '{"session_id":"cs9","transcript_path":%s,"cwd":"/"}\n' "$REPLY" \
  | TMPDIR="$fix/cs-not-a-dir" bash "$save_cs" 2>&1)"; rc=$?
expect 'save, no folder to write to: rc 0, no output' '0:' "$rc:$out"

# Without jq, the saved rule list and the start order file still reach the file.
: > "$cs_gate/cs10-read-main-pr"
cs_save cs10 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
js "$fix/compact-state.jsonl"
out="$(printf '{"session_id":"cs10","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" PATH="$csnojq" PLAYBOOK_START_ORDER_FILE="$fix/cs-order.txt" "$BASH" "$restore_cs" 2>&1)"
body="$(cat "$cs_gate/cs10-compact-restore.md" 2>/dev/null)"
check_line 'without jq: the saved rule list' '- .agents/rules/pr.md' "$body"
check_line 'without jq: the start order file' 'Auftrag aus der Datei Seeadler.' "$body"
check_contains 'without jq: its source' 'Source: the start order file' "$body"
body="$(cat "$cs_gate/cs5-compact-restore.md" 2>/dev/null)"
check_contains 'without jq, no order file: no source claimed' 'Source: none found' "$body"
check_contains 'without jq, no save: said so' '_no save found' "$body"
check_not_contains 'without jq: a short start order file is not cut' '[cut at' "$(cat "$cs_gate/cs10-compact-restore.md" 2>/dev/null)"
printf '%30000s\n' '' | tr ' ' a > "$fix/cs-order-long.txt"
js "$fix/compact-state.jsonl"; printf '{"session_id":"cs21","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" PATH="$csnojq" PLAYBOOK_START_ORDER_FILE="$fix/cs-order-long.txt" "$BASH" "$restore_cs" >/dev/null 2>&1
check_contains 'without jq: a long start order file is cut visibly' '[cut at 24000 bytes]' \
  "$(cat "$cs_gate/cs21-compact-restore.md" 2>/dev/null)"

# A save without rule reads is not a missing save.
cs_save cs11 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs11 "$fix/compact-state.jsonl" >/dev/null 2>&1
check_contains 'empty save: no rule file read, not "no save"' '_none: no rule file was read' "$(cat "$cs_gate/cs11-compact-restore.md" 2>/dev/null)"

# Only the rule files read before the compaction are listed (ww3d/playbook#487): chat.md and the local rules
# never read stay off the list, with and without jq; they are read at their point of use.
cs_save cs31 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs31 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
body="$(cat "$cs_gate/cs31-compact-restore.md" 2>/dev/null)"
for f in chat.md pr.md local/ci-silence.md local/naming.md; do
  check_not_contains "nothing read: $f is not listed" ".agents/rules/$f" "$body"
done
check_contains 'nothing read: the list says so' '_none: no rule file was read' "$body"
cs_save cs26 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs26 "$fix/compact-state.jsonl" "$csnojq" "$cs_proj" >/dev/null 2>&1
body="$(cat "$cs_gate/cs26-compact-restore.md" 2>/dev/null)"
check_not_contains 'without jq, nothing read: chat.md is not listed' '.agents/rules/chat.md' "$body"
check_not_contains 'without jq, nothing read: a local rule is not listed' '.agents/rules/local/naming.md' "$body"
# What was read before the compaction is listed, once; the unread neighbours stay off.
: > "$cs_gate/cs27-read-main-chat"; : > "$cs_gate/cs27-read-main-local-naming"
cs_save cs27 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
cs_restore cs27 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
body="$(cat "$cs_gate/cs27-compact-restore.md" 2>/dev/null)"
expect 'read: chat.md listed once' 1 "$(cs_cnt_file '- .agents/rules/chat.md' "$cs_gate/cs27-compact-restore.md")"
check_line 'read: the local rule read before is listed' '- .agents/rules/local/naming.md' "$body"
check_not_contains 'read: the unread local rule is not listed' '.agents/rules/local/ci-silence.md' "$body"
# Without a save no rule file is listed, and the missing save is said.
cs_restore cs28 "$fix/compact-state.jsonl" "$PATH" "$cs_proj" >/dev/null 2>&1
body="$(cat "$cs_gate/cs28-compact-restore.md" 2>/dev/null)"
check_not_contains 'no save: chat.md is not listed' '.agents/rules/chat.md' "$body"
check_contains 'no save: said so' '_no save found' "$body"
# Without CLAUDE_PROJECT_DIR the payload's cwd names the project: a read local rule is kept, being a file there.
: > "$cs_gate/cs29-read-main-local-ci-silence"
cs_save cs29 "$fix/compact-state-part.jsonl" >/dev/null 2>&1
js "$fix/compact-state.jsonl"; cs_t="$REPLY"; js "$cs_proj"
printf '{"session_id":"cs29","transcript_path":%s,"cwd":%s,"source":"compact"}\n' "$cs_t" "$REPLY" \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="" "$BASH" "$restore_cs" >/dev/null 2>&1
check_line 'read rule files: the cwd names the project' '- .agents/rules/local/ci-silence.md' \
  "$(cat "$cs_gate/cs29-compact-restore.md" 2>/dev/null)"

# An empty start order file falls back to the first input.
: > "$fix/cs-order-empty.txt"
js "$fix/compact-state.jsonl"; printf '{"session_id":"cs12","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
  | TMPDIR="$cs_tmp" PLAYBOOK_START_ORDER_FILE="$fix/cs-order-empty.txt" bash "$restore_cs" >/dev/null 2>&1
check_line 'start order: an empty file falls back to the first input' '/dev-task org/repo#1 Startauftrag Albatros' \
  "$(cat "$cs_gate/cs12-compact-restore.md" 2>/dev/null)"
# An unreadable start order file falls back too; where chmod leaves it readable (root, no POSIX modes) the case skips.
printf 'Gesperrter Auftrag Steinadler.\n' > "$fix/cs-order-locked.txt"; chmod 000 "$fix/cs-order-locked.txt"
if [ -r "$fix/cs-order-locked.txt" ]; then
  echo '  skip unreadable order file: chmod 000 leaves it readable here'
else
  js "$fix/compact-state.jsonl"; printf '{"session_id":"cs20","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
    | TMPDIR="$cs_tmp" PLAYBOOK_START_ORDER_FILE="$fix/cs-order-locked.txt" bash "$restore_cs" >/dev/null 2>&1
  body="$(cat "$cs_gate/cs20-compact-restore.md" 2>/dev/null)"
  check_line 'start order: an unreadable file falls back to the first input' '/dev-task org/repo#1 Startauftrag Albatros' "$body"
  check_contains 'start order: then the first input is the source' "Source: the maintainer's first input" "$body"
fi
chmod 644 "$fix/cs-order-locked.txt"
# Windows forms of the paths: a drive-letter order file, a transcript path with escaped backslashes.
if command -v cygpath >/dev/null 2>&1; then
  js "$(cygpath -w "$fix/compact-state.jsonl")"
  out="$(printf '{"session_id":"cs13","transcript_path":%s,"source":"compact"}\n' "$REPLY" \
    | TMPDIR="$cs_tmp" PLAYBOOK_START_ORDER_FILE="$(cygpath -m "$fix/cs-order.txt")" bash "$restore_cs" 2>/dev/null)"
  body="$(cat "$cs_gate/cs13-compact-restore.md" 2>/dev/null)"
  check_line 'windows: a C:/ order file counts' 'Auftrag aus der Datei Seeadler.' "$body"
  check_line 'windows: a backslash transcript path is read' 'Nachgereicht Kolibriwolke.' "$body"
  check_contains 'windows: the hint names the file in Windows form' "$(cygpath -w "$cs_gate/cs13-compact-restore.md")" \
    "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
else
  echo '  skip windows path forms: no cygpath here'
fi

# Every token shape is masked, in the save as in the restore. No boundary: every input lies in the part.
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
body="$(cat "$cs_gate/cs14-compact-restore.md" 2>/dev/null)"
for i in "${!cs_tokens[@]}"; do
  t="${cs_tokens[$i]}"
  check_not_contains "mask: ${t:0:6}... not in the save" "${t: -8}" "$saved"
  check_not_contains "mask: ${t:0:6}... not in the restore file" "${t: -8}" "$body"
  check_line "mask: ${t:0:6}... masked in the restore file" "Token ${cs_masked[$i]} hier." "$body"
done
# A skill reference no file matches keeps its marker name.
: > "$cs_gate/cs15-read-main-skill-nosuch-skill-ref"
cs_save cs15 "$cs_tf" >/dev/null 2>&1
check_contains 'save: an unresolved skill reference is kept' 'skill reference nosuch-skill-ref' "$(cat "$cs_gate/cs15-compact-rules" 2>/dev/null)"

# A control character in an input keeps the output valid JSON.
cs_cf="$fix/compact-state-ctrl.jsonl"
{ printf '%s\n' '{"type":"user","message":{"role":"user","content":"Farbe \u001b[31mrot\u001b[0m und \u0007 Glocke Kranichzug."},"origin":{"kind":"human"}}'
  printf '%s\n' '{"type":"system","subtype":"compact_boundary"}'
  printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary: nichts."}}'; } > "$cs_cf"
out="$(cs_restore cs16 "$cs_cf" 2>&1)"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then ok 'control characters: the output is valid JSON' valid
else bad 'control characters: the output is valid JSON' invalid valid; fi
check_contains 'control characters: the input still named' 'Kranichzug' "$out"

# The edges of the part.
cs_save cs17 "$fix/compact-state-edges-part.jsonl" >/dev/null 2>&1
out="$(cs_restore cs17 "$fix/compact-state-edges.jsonl" 2>&1)"
body="$(cat "$cs_gate/cs17-compact-restore.md" 2>/dev/null)"
check_line 'edges: an answer to a turn begun before the previous compaction' 'Fortsetzung Gnuherde nach der Verdichtung.' "$body"
check_contains 'edges: a <cross-session-message> is a peer message' 'Peer ohne Absender Tukan.' "$body"
check_line 'edges: a peer without a sender is named by its first word, never unknown' '### Peer' "$body"
check_not_contains 'edges: a meta line is no input' 'Lemurlicht' "$body"
check_not_contains 'edges: a sidechain input is left out' 'Marderhund' "$body"
expect 'edges: a queued repeat of a typed input once' 1 "$(cs_cnt 'Doppelt gesagt Wombatfell.' "$body")"
check_line 'edges: a slash command after the skill call is the step' '/review org/repo#3' "$(printf '%s\n' "$body" | sed -n '/^## Step$/,/^## /p')"
check_contains 'edges: nothing lost when the summary carries every input' 'every input of the maintainer' "$out"

# Many lost inputs keep the hint short; answers above their budget are counted, not dropped silently.
out="$(cs_restore cs18 "$fix/compact-state-many.jsonl" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if [ "${#ctx}" -gt 0 ] && [ "${#ctx}" -lt 2000 ]; then ok 'many lost inputs: the hint stays under 2,000 characters' "${#ctx}"
else bad 'many lost inputs: the hint stays under 2,000 characters' "${#ctx}" '1..1999'; fi
check_contains 'many lost inputs: they are counted' 'Missing from the summary (70)' "$ctx"
body="$(cat "$cs_gate/cs18-compact-restore.md" 2>/dev/null)"
check_contains 'budget: older answers are counted' 'older entries left out' "$body"
check_contains 'budget: the newest answer stays' 'Antwort 40 ' "$body"
check_not_contains 'budget: the oldest answer goes' 'Antwort 1 x' "$body"
check_contains 'many lost inputs: the file counts them too' 'Missing from the summary (70, newest first)' "$body"
check_line 'many lost inputs: all 70 fit the loss budget, the oldest is listed' \
  '- "Verlorene Eingabe Nummer 1 mit Wortlaut Flamingo1 und Ibisfeder1."' "$body"

# Built-in slash commands are neither the step nor an input.
cs_restore cs22 "$fix/compact-state-filtered.jsonl" >/dev/null 2>&1
body="$(cat "$cs_gate/cs22-compact-restore.md" 2>/dev/null)"
check_line 'filtered: the skill call before /compact stays the step' 'skill dev-task org/repo#4' \
  "$(printf '%s\n' "$body" | sed -n '/^## Step$/,/^## /p')"
check_not_contains 'filtered: /compact is no input' 'Fokus Pinguin' "$body"
check_not_contains 'filtered: /model is no input' '/model opus' "$body"

# An input without a word of five characters is never named lost; the file lists the lost one.
out="$(cs_restore cs23 "$fix/compact-state-short.jsonl" 2>&1)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
check_contains 'loss: an input with key words the summary lacks is named' 'Missing from the summary (1)' "$ctx"
check_not_contains 'loss: an input without key words is not' 'Ja gut so' "$ctx"
check_line 'loss: the file lists the lost input' '- "Bitte Steinbock pruefen."' "$(cat "$cs_gate/cs23-compact-restore.md" 2>/dev/null)"

# Two compactions after the save: the save is from an older one, the part lies between the two boundaries.
cs_save cs24 "$fix/compact-state-twice-part.jsonl" >/dev/null 2>&1
cs_restore cs24 "$fix/compact-state-twice.jsonl" >/dev/null 2>&1
inputs_="$(sed -n '/^## The maintainer/,/^## Own/p' "$cs_gate/cs24-compact-restore.md" 2>/dev/null)"
check_line 'two boundaries after the save: the input between them' 'Zwischen den Grenzen Fischotter.' "$inputs_"
check_not_contains 'two boundaries after the save: not the input before the save' 'Dachsbau' "$inputs_"

finish
