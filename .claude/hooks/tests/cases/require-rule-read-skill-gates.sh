#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, design round, state audit and chat-handoff
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-skill-gates.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-rule-read.sh: the start of a design round or a state audit owes audit.md (ww3d/playbook#526) =="
# Two ways in: the Skill tool call (PreToolUse) and the typed /ccweb-prompt (UserPromptExpansion, a marker).
au_dir="$gate_tmp/claude-rule-gate"
au_rule="$repo_root/.agents/rules/audit.md"
au_sha="$(git -C "$repo_root" hash-object -- "$au_rule")"
sk_event() { # session, skill name, [agent_id], [transcript]
  local s k; js "$1"; s="$REPLY"; js "$2"; k="$REPLY"; js "${4:-$fix/empty.jsonl}"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":%s,"args":"x"}' "$s" "$REPLY" "$k"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"agent_id":%s' "$REPLY"; fi
  printf '}\n'
}
upe_event() { # session, command_name
  local s n; js "$1"; s="$REPLY"; js "$2"; n="$REPLY"; js "/$2 x"
  printf '{"session_id":%s,"transcript_path":"/tmp/none.jsonl","cwd":"/tmp","permission_mode":"default","hook_event_name":"UserPromptExpansion","expansion_type":"slash_command","command_name":%s,"command_args":"x","command_source":"plugin","prompt":%s}\n' "$s" "$n" "$REPLY"
}
upe_run() { printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1; }
bash_event() { # session, command, [agent_id]
  local s c; js "$1"; s="$REPLY"; js "$2"; c="$REPLY"; js "$fix/empty.jsonl"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}' "$s" "$REPLY" "$c"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"agent_id":%s' "$REPLY"; fi
  printf '}\n'
}
receipt_line="+ audit.md   25.0.0  ${au_sha:0:7}   read (rule)"
receipt_transcript="$fix/audit-receipt.jsonl"
js "$receipt_line"; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$REPLY" > "$receipt_transcript"

# The Skill tool call of the two skills is gated like any other action.
sid="au-a-$$"
out="$(printf '%s' "$(sk_event "$sid" ccweb-prompt)" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'Skill ccweb-prompt, audit.md unread: denied, path named' '.agents/rules/audit.md' "$out"
check_contains '... and its blob SHA' "blob $au_sha" "$out"
# A prefixed name counts, any other skill does not.
expect 'Skill anthropic-skills:ccweb-prompt is denied' DENY "$(rule_verdict "$(sk_event "au-b-$$" anthropic-skills:ccweb-prompt)")"
expect 'Skill state-audit is denied'                   DENY "$(rule_verdict "$(sk_event "au-c-$$" state-audit)")"
expect 'Skill anthropic-skills:state-audit is denied'  DENY "$(rule_verdict "$(sk_event "au-d-$$" anthropic-skills:state-audit)")"
expect 'Skill dev-task passes'                         ALLOW "$(rule_verdict "$(sk_event "au-e-$$" dev-task)")"
expect 'Skill anthropic-skills:dev-task passes'        ALLOW "$(rule_verdict "$(sk_event "au-f-$$" anthropic-skills:dev-task)")"
expect 'a name that only ends alike passes'            ALLOW "$(rule_verdict "$(sk_event "au-g-$$" my-ccweb-prompt)")"
# A read of audit.md (marker or receipt line) lifts the gate.
sid="au-h-$$"
record "$(read_event "$sid" "$au_rule")"
expect 'Skill ccweb-prompt after the read marker passes' ALLOW "$(rule_verdict "$(sk_event "$sid" ccweb-prompt)")"
expect 'Skill ccweb-prompt with the receipt line passes'  ALLOW "$(rule_verdict "$(sk_event "au-i-$$" ccweb-prompt "" "$receipt_transcript")")"
# The typed start leaves a marker and hands over context, and blocks nothing.
sid="au-j-$$"
out="$(upe_run "$(upe_event "$sid" ccweb-prompt)")"
check_contains 'UserPromptExpansion ccweb-prompt hands over additionalContext' '"additionalContext":' "$out"
check_contains '... telling to read audit.md' '.agents/rules/audit.md' "$out"
check_not_contains '... and never blocks the expansion' '"decision"' "$out"
present_file '... and writes the marker' "$au_dir/${sid}-audit-owed"
sid="au-k-$$"
out="$(upe_run "$(upe_event "$sid" dev-task)")"
expect 'UserPromptExpansion dev-task: no output' '' "$out"
absent_file '... and no marker' "$au_dir/${sid}-audit-owed"
# command_name measured with Claude Code 2.1.316 (ww3d/playbook#526): `ccweb-prompt`, `testns:state-audit`.
for nm in anthropic-skills:ccweb-prompt anthropic-skills:state-audit /ccweb-prompt state-audit; do
  sid="au-l-$$-${nm//[:\/]/_}"
  upe_run "$(upe_event "$sid" "$nm")" >/dev/null
  present_file "UserPromptExpansion $nm writes the marker" "$au_dir/${sid}-audit-owed"
done
sid="au-m-$$"
upe_run "$(upe_event "$sid" other:dev-task)" >/dev/null
absent_file 'a prefixed dev-task writes no marker' "$au_dir/${sid}-audit-owed"
# the marker holds every call the gate sees, until audit.md is read
sid="au-n-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
out="$(printf '%s' "$(bash_event "$sid" 'rc ask "x"')" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'marker, audit.md unread: a plain Bash call is denied' '.agents/rules/audit.md' "$out"
check_contains '... the denial names the origin' 'UserPromptExpansion of ccweb-prompt' "$out"
expect 'a Skill call is held too' DENY "$(rule_verdict "$(sk_event "$sid" dev-task)")"
record "$(read_event "$sid" "$au_rule")"
expect 'after the read the same Bash call passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')")"
absent_file '... and the marker is gone' "$au_dir/${sid}-audit-owed"
# no audit.md in the repository, or its receipt line in the transcript: nothing blocks
sid="au-o-$$"
bare_repo="$fix/au-bare"; mkdir -p "$bare_repo/.agents/rules"; : > "$bare_repo/.agents/rules/carrier.md"
printf '%s' "$(upe_event "$sid" ccweb-prompt)" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$bare_repo" bash "$ruleread" >/dev/null 2>&1
expect 'marker, repository without audit.md: the call passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')" "$bare_repo")"
sid="au-p-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
ev="$(js "$sid"; sg_s="$REPLY"; js "$receipt_transcript"; printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rc ask x"}}' "$sg_s" "$REPLY")"
expect 'marker, receipt line of audit.md in the transcript: the call passes' ALLOW "$(rule_verdict "$ev")"
# fail-open
# a marker of another session holds this session's gated call no more than its plain call
sid="au-x-$$"
record "$(read_event "$sid" "$repo_root/.agents/rules/carrier.md")"
: > "$au_dir/foreign-session-audit-owed"
expect 'a marker of another session does not hold a gated call' ALLOW "$(rule_verdict "$(bash_event "$sid" 'gh issue create --title x')")"
rm -f "$au_dir/foreign-session-audit-owed"
# the typed state-audit holds like ccweb-prompt; the receipt line of audit.md lifts it for a Skill call too
sid="au-y-$$"
upe_run "$(upe_event "$sid" anthropic-skills:state-audit)" >/dev/null
out="$(printf '%s' "$(sk_event "$sid" dev-task)" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'typed state-audit: a Skill call of another name is held' 'UserPromptExpansion of state-audit' "$out"
expect 'typed state-audit: the receipt line lifts it for a Skill call' ALLOW "$(rule_verdict "$(sk_event "$sid" dev-task "" "$receipt_transcript")")"
# a name that only starts like the skill writes no marker
for nm in ccweb-prompt-old state-auditor; do
  sid="au-z-$$-$nm"
  out="$(upe_run "$(upe_event "$sid" "$nm")")"
  expect "UserPromptExpansion $nm: no marker, no output" 'absent:' "$([ -e "$au_dir/${sid}-audit-owed" ] && echo present || echo absent):$out"
done
# where the transcript cannot be read the call passes (fail-open) and the debt of audit.md stays
sid="au-w-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
ev="$(js "$sid"; printf '{"session_id":%s,"transcript_path":"/nonexistent.jsonl","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rc ask x"}}' "$REPLY")"
expect 'unreadable transcript: the call passes' ALLOW "$(rule_verdict "$ev")"
present_file '... and the marker stands' "$au_dir/${sid}-audit-owed"
expect '... so the next call with a readable transcript is still held' DENY "$(rule_verdict "$(bash_event "$sid" 'rc ask x')")"
# a repository without audit.md gets no hint
out="$(upe_event "au-v-$$" ccweb-prompt | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$bare_repo" bash "$ruleread" 2>&1)"
expect 'repository without audit.md: no hint' '' "$out"
sid="au-q-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
au_nojq="$fix/au-nojq"; mkdir -p "$au_nojq"
for helper in cat git grep tail awk date mkdir rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$(command -v bash)" "$(command -v "$helper")" > "$au_nojq/$helper"; chmod +x "$au_nojq/$helper"
done
out="$(printf '%s' "$(bash_event "$sid" 'rc ask "x"')" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$au_nojq" "$(command -v bash)" "$ruleread" 2>&1)"; rc=$?
expect 'no jq on PATH: pass, no crash' '0:' "$rc:$out"
out="$(printf '' | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>/dev/null)"; rc=$?
expect 'an empty payload: pass, no crash, no denial' '0:0' "$rc:$(has_text permissionDecision "$out" && echo 1 || echo 0)"
out="$(upe_event "au-r-$$" ccweb-prompt | TMPDIR="/dev/null/none" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>/dev/null)"; rc=$?
expect 'an unwritable marker directory: no crash, no promise of a block' '0:' "$rc:$out"
out="$(printf '%s' "$(bash_event "au-s-$$" 'rc ask "x"')" | TMPDIR="/dev/null/none" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>/dev/null)"; rc=$?
expect '... and a call under it passes' '0:' "$rc:$out"
# a sub-agent is judged by its own read
sid="au-t-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
expect 'sub-agent, nothing read: denied' DENY "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"' agent-1)")"
record "$(read_event "$sid" "$au_rule" agent-1)"
expect 'sub-agent after its own read: passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"' agent-1)")"
expect 'the main thread is still held (its own read is owed)' DENY "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')")"
present_file '... and the marker stands' "$au_dir/${sid}-audit-owed"

echo "== require-rule-read.sh: the skill chat-handoff owes session.md (follow-up to ww3d/playbook#526) =="
# The same two ways in as the audit block above, through the one table skill -> trigger.
ses_rule="$repo_root/.agents/rules/session.md"
ses_sha="$(git -C "$repo_root" hash-object -- "$ses_rule")"
ses_receipt_transcript="$fix/session-receipt.jsonl"
js "+ session.md   25.0.0  ${ses_sha:0:7}   read (rule)"; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$REPLY" > "$ses_receipt_transcript"
sid="se-a-$$"
out="$(printf '%s' "$(sk_event "$sid" chat-handoff)" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'Skill chat-handoff, session.md unread: denied, path named' '.agents/rules/session.md' "$out"
check_contains '... and its blob SHA' "blob $ses_sha" "$out"
expect 'Skill anthropic-skills:chat-handoff is denied' DENY "$(rule_verdict "$(sk_event "se-b-$$" anthropic-skills:chat-handoff)")"
expect 'Skill dev-task passes'                         ALLOW "$(rule_verdict "$(sk_event "se-c-$$" dev-task)")"
expect 'a name that only ends alike passes'            ALLOW "$(rule_verdict "$(sk_event "se-d-$$" my-chat-handoff)")"
sid="se-e-$$"
record "$(read_event "$sid" "$ses_rule")"
expect 'Skill chat-handoff after the read marker passes' ALLOW "$(rule_verdict "$(sk_event "$sid" chat-handoff)")"
expect 'Skill chat-handoff with the receipt line passes' ALLOW "$(rule_verdict "$(sk_event "se-f-$$" chat-handoff "" "$ses_receipt_transcript")")"
# The typed start leaves the marker of its own trigger and blocks nothing.
for nm in chat-handoff anthropic-skills:chat-handoff /chat-handoff; do
  sid="se-g-$$-${nm//[:\/]/_}"
  out="$(upe_run "$(upe_event "$sid" "$nm")")"
  check_contains "UserPromptExpansion $nm hands over additionalContext naming session.md" '.agents/rules/session.md' "$out"
  check_not_contains '... and never blocks the expansion' '"decision"' "$out"
  present_file '... and writes the session marker' "$au_dir/${sid}-session-owed"
  absent_file '... and no audit marker' "$au_dir/${sid}-audit-owed"
done
# the marker holds every call the gate sees, until session.md is read
sid="se-h-$$"
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
out="$(printf '%s' "$(bash_event "$sid" 'rc ask "x"')" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'session marker, session.md unread: a plain Bash call is denied' '.agents/rules/session.md' "$out"
check_contains '... the denial names the origin' 'UserPromptExpansion of chat-handoff' "$out"
record "$(read_event "$sid" "$ses_rule")"
expect 'after the read the same Bash call passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')")"
absent_file '... and the marker is gone' "$au_dir/${sid}-session-owed"
# both markers: one call owes both, and each read lifts only its own
sid="se-i-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
record "$(read_event "$sid" "$au_rule")"
out="$(printf '%s' "$(bash_event "$sid" 'rc ask "x"')" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'both markers, only audit.md read: session.md is still owed' '.agents/rules/session.md' "$out"
check_contains '... with its own origin' 'UserPromptExpansion of chat-handoff' "$out"
record "$(read_event "$sid" "$ses_rule")"
expect '... after the second read the call passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')")"
sid="se-j-$$"
upe_run "$(upe_event "$sid" ccweb-prompt)" >/dev/null
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
record "$(read_event "$sid" "$ses_rule")"
out="$(printf '%s' "$(bash_event "$sid" 'rc ask "x"')" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
check_contains 'both markers, only session.md read: audit.md is still owed' '.agents/rules/audit.md' "$out"
check_contains '... with its own origin' 'UserPromptExpansion of ccweb-prompt' "$out"
for nm in chat-handoff-x my-chat-handoff; do
  sid="se-p-$$-$nm"
  out="$(upe_run "$(upe_event "$sid" "$nm")")"
  expect "UserPromptExpansion $nm: no marker, no output" 'absent:' "$([ -e "$au_dir/${sid}-session-owed" ] && echo present || echo absent):$out"
done
sid="se-q-$$"
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
expect 'session marker: a Skill call of another name is held' DENY "$(rule_verdict "$(sk_event "$sid" dev-task)")"
expect '... and the receipt line of session.md lifts it for a Skill call' ALLOW "$(rule_verdict "$(sk_event "$sid" dev-task "" "$ses_receipt_transcript")")"
sid="se-r-$$"
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
ev="$(js "$sid"; sg_s="$REPLY"; js "$ses_receipt_transcript"; printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rc ask x"}}' "$sg_s" "$REPLY")"
expect 'session marker, receipt line of session.md in the transcript: the call passes' ALLOW "$(rule_verdict "$ev")"
# no session.md in the repository: nothing is gated, no hint; a foreign session's marker has no effect
sid="se-k-$$"
upe_event "$sid" chat-handoff | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$bare_repo" bash "$ruleread" >/dev/null 2>&1
present_file 'repository without session.md: the marker is written' "$au_dir/${sid}-session-owed"
expect 'session marker, repository without session.md: the call passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')" "$bare_repo")"
expect 'repository without session.md: no hint' '' "$(upe_event "se-l-$$" chat-handoff | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$bare_repo" bash "$ruleread" 2>&1)"
sid="se-m-$$"
record "$(read_event "$sid" "$repo_root/.agents/rules/carrier.md")"
: > "$au_dir/foreign-session-session-owed"
expect "a foreign session's session marker does not hold a gated call" ALLOW "$(rule_verdict "$(bash_event "$sid" 'gh issue create --title x')")"
rm -f "$au_dir/foreign-session-session-owed"
# a sub-agent is judged by its own read; it does not lift the main thread's marker
sid="se-n-$$"
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
expect 'sub-agent, nothing read: denied' DENY "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"' agent-1)")"
record "$(read_event "$sid" "$ses_rule" agent-1)"
expect 'sub-agent after its own read: passes' ALLOW "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"' agent-1)")"
expect 'the main thread is still held (its own read is owed)' DENY "$(rule_verdict "$(bash_event "$sid" 'rc ask "x"')")"
present_file '... and the marker stands' "$au_dir/${sid}-session-owed"
# a hook that cannot read the transcript passes and leaves the debt of session.md standing
sid="se-o-$$"
upe_run "$(upe_event "$sid" chat-handoff)" >/dev/null
ev="$(js "$sid"; printf '{"session_id":%s,"transcript_path":"/nonexistent.jsonl","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rc ask x"}}' "$REPLY")"
expect 'unreadable transcript: the call passes' ALLOW "$(rule_verdict "$ev")"
present_file '... and the session marker stands' "$au_dir/${sid}-session-owed"

finish
