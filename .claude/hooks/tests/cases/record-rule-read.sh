#!/usr/bin/env bash
# Hook suite section: record-rule-read.sh, the real read as the state of the gate
# Run alone: bash .claude/hooks/tests/cases/record-rule-read.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== record-rule-read.sh + require-rule-read.sh: the real read is the state =="
# A PostToolUse payload for Read, shaped like the one measured with Claude Code 2.1.293
# (tool_input.file_path, tool_response.file.{startLine,numLines,totalLines}, agent_id only inside a sub-agent).
# `gh issue create` maps to the carrier rule alone; the project root is this checkout, whose rule file exists.
carrier_event() { # session, transcript path as a JSON string, [agent_id] -> a PreToolUse payload of `gh issue create`
  local s; js "$1"; s="$REPLY"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"gh issue create --title x"}' "$s" "$2"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"agent_id":%s' "$REPLY"; fi
  printf '}\n'
}
gate_for() { # session, [agent_id] -> verdict of a carrier-triggering call
  local ev
  ev="$(carrier_event "$1" '"/nonexistent.jsonl"' "${2:-}")"
  rule_verdict "$ev"
}
rule_abs="$repo_root/.agents/rules/carrier.md"
# A missing transcript would fail open; the receipt source is exercised elsewhere, so give the gate an empty one.
gate_for_empty() { # session, [agent_id]
  local ev t
  js "$fix/empty.jsonl"; t="$REPLY"
  ev="$(carrier_event "$1" "$t" "${2:-}")"
  rule_verdict "$ev"
}
sid="read-a-$$"
expect 'before any read: the first action is refused' DENY "$(gate_for_empty "$sid")"
record "$(read_event "$sid" "$rule_abs")"
expect 'after a whole-file Read of the rule: allowed, no receipt line needed' ALLOW "$(gate_for_empty "$sid")"

sid="read-b-$$"
record "$(read_event "$sid" "$rule_abs" "" '{"offset":5,"limit":3}' '{"startLine":5,"numLines":3,"totalLines":40}')"
expect 'a partial range does not count' DENY "$(gate_for_empty "$sid")"
record "$(read_event "$sid" "$rule_abs" "" '{"offset":1,"limit":2000}' '{"startLine":1,"numLines":40,"totalLines":40}')"
expect 'an explicit range that covers the whole file counts' ALLOW "$(gate_for_empty "$sid")"

sid="read-c-$$"
record "$(read_event "$sid" "$repo_root/docs/overview.md")"
record "$(read_event "$sid" "$repo_root/.agents/rules/local/carrier.md")"
record "$(read_event "$sid" "$repo_root/.agents/rules/not-a-trigger.md")"
expect 'reading some other file does not count' DENY "$(gate_for_empty "$sid")"
bs_path="${rule_abs//\//\\}"
record "$(read_event "$sid" "$bs_path")"
expect 'a backslash path counts like a slash path' ALLOW "$(gate_for_empty "$sid")"

sid="read-d-$$"
record "$(read_event "$sid" "$rule_abs")"
rc_sid="$sid"
rc_event compact | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$gate_tmp" bash "$readconfirm" >/dev/null
expect 'a compaction ends the read state' DENY "$(gate_for_empty "$sid")"

echo "== require-rule-read.sh: a sub-agent has to read the file itself =="
sid="read-e-$$"
record "$(read_event "$sid" "$rule_abs")"
expect 'the main thread read it: the sub-agent still is refused' DENY "$(gate_for_empty "$sid" agent-1)"
record "$(read_event "$sid" "$rule_abs" agent-1)"
expect 'the sub-agent read it itself: it passes' ALLOW "$(gate_for_empty "$sid" agent-1)"
expect 'another sub-agent is not covered by it' DENY "$(gate_for_empty "$sid" agent-2)"
sid="read-f-$$"
record "$(read_event "$sid" "$rule_abs" agent-1)"
expect 'a read inside a sub-agent does not unlock the main thread' DENY "$(gate_for_empty "$sid")"
# The typed receipt stays a second source, read from the sub-agent's own transcript.
sa="$fix/sa"; mkdir -p "$sa/main/subagents"
cp "$fix/rule-no-receipt.jsonl" "$sa/main.jsonl"
cp "$fix/rule-receipt-text.jsonl" "$sa/main/subagents/agent-A1.jsonl"
sa_event() { # agent id
  js "$sa/main.jsonl"; carrier_event "$(next_sid)" "$REPLY" "$1"
}
expect 'a receipt in the sub-agent'"'"'s own transcript counts for it' ALLOW "$(rule_verdict "$(sa_event A1)")"
expect 'the same receipt does not count for the main thread' DENY "$(rule_verdict "$(sa_event "")")"

echo "== require-rule-read.sh: starting a sub-agent owes agents.md (ww3d/playbook#414) =="
for agent_tool in Agent Task Workflow; do
  chk_tool "$agent_tool start without a read of agents.md" DENY "$agent_tool" '{"prompt":"x"}'
done
agents_event() { # session
  local s; js "$1"; s="$REPLY"; js "$fix/empty.jsonl"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"x"}}\n' "$s" "$REPLY"
}
sid="read-agents-$$"
expect 'a sub-agent start before agents.md is read: refused' DENY "$(rule_verdict "$(agents_event "$sid")")"
record "$(read_event "$sid" "$repo_root/.agents/rules/agents.md")"
expect 'a sub-agent start after a whole-file Read of agents.md: allowed' ALLOW "$(rule_verdict "$(agents_event "$sid")")"

echo "== require-rule-read.sh: the denial names path and blob SHA, never the file =="
sid="deny-$$"
js "$fix/empty.jsonl"
deny_out="$(printf '%s' "$(carrier_event "$sid" "$REPLY")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread")"
want_sha="$(git hash-object "$rule_abs")"
check_contains 'the denial carries the path'     '.agents/rules/carrier.md' "$deny_out"
check_contains 'the denial carries the blob SHA' "$want_sha" "$deny_out"
body_line=""
while IFS= read -r rr_l; do
  if [[ $rr_l =~ ^[A-Za-z].{40,} ]]; then body_line="${rr_l:0:60}"; break; fi
done < "$rule_abs"
check_not_contains 'the denial holds no line of the file' "$body_line" "$deny_out"
js "$fix/empty.jsonl"
deny_out2="$(printf '%s' "$(carrier_event "$sid" "$REPLY")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread")"
check_not_contains 'a second denial still holds no file text (no stage 2)' 'BEGIN' "$deny_out2"
check_not_contains 'a second denial still holds no line of the file' "$body_line" "$deny_out2"

echo "== record-rule-read.sh: no process for a Read of any other file, fail-open on junk =="
for helper in jq grep git; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$(command -v "$helper")" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
: > "$calls"
printf '%s' "$(read_event "x-$$" "/work/src/Program.cs")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$recorder"
printf '%s' "$(read_event "x-$$" "$rule_abs")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$recorder"
if [ ! -s "$calls" ]; then ok 'no jq, grep or git start, for a rule read either' 'none'; else bad 'no process start' "$(tr '\n' ' ' < "$calls")" 'none'; fi
rm -f "$stub/jq" "$stub/grep" "$stub/git"
out="$(printf 'not json at all' | TMPDIR="$gate_tmp" bash "$recorder" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok 'a junk payload records nothing and exits 0' 'rc=0'; else bad 'a junk payload' "rc=$rc $out" 'rc=0'; fi

echo "== record-rule-read.sh: a skill reference file is recorded like a rule file =="
marker_dir="$gate_tmp/claude-rule-gate"
skill_ref="$repo_root/.claude/skills/pr-poll-review/reference/gates.md"
n_markers() { find "$marker_dir" -type f -name '*-read-*' 2>/dev/null | wc -l | tr -d ' '; }
sid="ref-a-$$"
record "$(read_event "$sid" "$skill_ref")"
present_file 'a whole-file Read leaves the marker named for skill and file' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
sid="ref-b-$$"
record "$(read_event "$sid" "$skill_ref" "" '{"offset":5,"limit":3}' '{"startLine":5,"numLines":3,"totalLines":40}')"
absent_file 'a partial range leaves no marker' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
record "$(read_event "$sid" "$skill_ref" "" '{"offset":1,"limit":2000}' '{"startLine":1,"numLines":40,"totalLines":40}')"
present_file 'a range covering the whole file leaves it' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
sid="ref-c-$$"
record "$(read_event "$sid" "$skill_ref" agent-7)"
present_file 'a read inside a sub-agent is named for the sub-agent' "$marker_dir/${sid}-read-agent-7-skill-pr-poll-review-gates"
before="$(n_markers)"
sid="ref-d-$$"
for odd in "$repo_root/.claude/skills/pr poll/reference/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/sub/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/../gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/data.json" \
           "$repo_root/.claude/skills/pr-poll-review/reference/a b.md" \
           "$repo_root/docs/reference/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/SKILL.md"; do
  record "$(read_event "$sid" "$odd")"
done
record "$(read_event "bad/session id" "$skill_ref")"
record "$(read_event "$sid" "$skill_ref" "bad agent")"
expect 'odd paths, names and ids record nothing' "$before" "$(n_markers)"

echo "== record-rule-read.sh: the core files of the receipt are recorded too (ww3d/playbook#366) =="
sid="core-a-$$"
record "$(read_event "$sid" "$repo_root/AGENTS.md")"
present_file 'AGENTS.md at the root leaves core.agents' "$marker_dir/${sid}-read-main-core.agents"
record "$(read_event "$sid" "$repo_root/CLAUDE.md")"
present_file 'CLAUDE.md at the root leaves core.claude' "$marker_dir/${sid}-read-main-core.claude"
record "$(read_event "$sid" "$repo_root/audit/state-2026-02-02T0000Z.md")"
present_file 'an audit leaves core.audit with its stamp' "$marker_dir/${sid}-read-main-core.audit.2026-02-02T0000Z"
record "$(read_event "$sid" "$repo_root/audit/ist-stand-2026-01-01T0000Z.md")"
present_file 'an audit under the old name counts until 26.0.0' "$marker_dir/${sid}-read-main-core.audit.2026-01-01T0000Z"
# The new place docs/audit/ first; audit/ above is read until playbook 26.0.0, the first MAJOR after the move.
record "$(read_event "$sid" "$repo_root/docs/audit/state-2026-04-04T0000Z.md")"
present_file 'an audit under docs/audit/ leaves core.audit with its stamp' "$marker_dir/${sid}-read-main-core.audit.2026-04-04T0000Z"
record "$(read_event "$sid" "$repo_root/docs/audit/ist-stand-2026-05-05T0000Z.md")"
present_file 'an old-named audit under docs/audit/ counts too' "$marker_dir/${sid}-read-main-core.audit.2026-05-05T0000Z"
record "$(read_event "$sid" "$repo_root/AGENTS.md" agent-9)"
present_file 'a sub-agent read is named for the sub-agent' "$marker_dir/${sid}-read-agent-9-core.agents"
sid="core-b-$$"
before="$(n_markers)"
record "$(read_event "$sid" "$repo_root/AGENTS.md" "" '{"offset":5,"limit":3}' '{"startLine":5,"numLines":3,"totalLines":40}')"
for odd in "$repo_root/docs/AGENTS.md" "$repo_root/templates/root/CLAUDE.md" "$repo_root/audit/notes.md" \
           "$repo_root/docs/audit/notes.md" "$repo_root/docs/docs/audit/state-2026-02-02T0000Z.md" "/elsewhere/AGENTS.md"; do
  record "$(read_event "$sid" "$odd")"
done
expect 'a partial read, a nested or foreign file records nothing' "$before" "$(n_markers)"
# Windows: root and path differ only in case or drive-letter spelling; the core file still counts.
sid="core-c-$$"
win_record() { printf '%s' "$2" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$1" bash "$recorder"; }
win_record '/c/Users/Me/repo' "$(read_event "$sid" 'C:\Users\Me\repo\CLAUDE.md')"
present_file 'Git Bash root, Windows path: CLAUDE.md counts' "$marker_dir/${sid}-read-main-core.claude"
win_record 'C:\Users\Me\repo' "$(read_event "$sid" 'c:\users\me\repo\AGENTS.md')"
present_file 'a path in other case: AGENTS.md counts' "$marker_dir/${sid}-read-main-core.agents"
win_record 'C:\Users\Me\repo' "$(read_event "$sid" 'C:\Users\Me\repo\audit\STATE-2026-03-03T0000Z.md')"
present_file 'an audit name in capitals keeps its stamp' "$marker_dir/${sid}-read-main-core.audit.2026-03-03T0000Z"
# Another Git Bash mount than a drive (/tmp stands for a folder under the Windows user): no cygpath on the hot path,
# so such a path never meets the Windows spelling of the root - the read counts nothing (lib/pathform.sh).
sid="core-m-$$"
win_record 'C:\Users\Me\AppData\Local\Temp\repo' "$(read_event "$sid" '/tmp/repo/CLAUDE.md')"
win_record '/tmp/repo' "$(read_event "$sid" 'C:\Users\Me\AppData\Local\Temp\repo\AGENTS.md')"
absent_file 'a /tmp path and a Windows root never meet: CLAUDE.md' "$marker_dir/${sid}-read-main-core.claude"
absent_file 'a Windows path and a /tmp root never meet: AGENTS.md' "$marker_dir/${sid}-read-main-core.agents"
# A Windows root and the Git Bash spelling of a path below it: the audit name compares without case.
sid="core-w-$$"
win_record 'C:\Users\Me\repo' "$(read_event "$sid" '/c/Users/Me/repo/audit/STATE-2026-03-03T0000Z.md')"
present_file 'a Windows root, a Git Bash path: the audit counts' "$marker_dir/${sid}-read-main-core.audit.2026-03-03T0000Z"
# lib/pathform.sh itself: a sibling folder is not below the root, a trailing slash on the root does not count, a
# glob character in the root is text.
# shellcheck disable=SC2016 # the program is for the bash it starts, its $ names are that shell's
pu() { bash -c '. "$1"; if path_under "$2" "$3"; then printf "under %s" "$pf_rel"; else printf "not under"; fi' _ \
  "$hooks/lib/pathform.sh" "$1" "$2"; }
expect 'a sibling with the root as prefix is not below it' 'not under'        "$(pu /w/repo /w/repo-other/CLAUDE.md)"
expect 'a trailing slash on the root'                     'under CLAUDE.md'  "$(pu /w/repo/ /w/repo/CLAUDE.md)"
expect 'a glob character in the root is text'             'not under'        "$(pu '/w/r*' /w/rx/y)"
expect 'a Windows root, a Git Bash path, case-blind'      'under audit/x.md' "$(pu 'C:\Users\Me\repo' /c/users/me/repo/audit/x.md)"
# Without lib/pathform.sh no path can be judged: the read counts nothing.
rec_nolib="$fix/rec-nolib"; mkdir -p "$rec_nolib/lib"; cp "$recorder" "$rec_nolib/"; cp "$hooks/lib/stdin.sh" "$rec_nolib/lib/"
sid="core-n-$$"
win_record_nolib() { printf '%s' "$2" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$1" bash "$rec_nolib/record-rule-read.sh"; }
win_record_nolib 'C:\Users\Me\repo' "$(read_event "$sid" 'C:\Users\Me\repo\CLAUDE.md')"
absent_file 'without lib/pathform.sh the read counts nothing' "$marker_dir/${sid}-read-main-core.claude"
# B1: an audit read from line 1 counts once it covers the short form - the metadata block and the
# first "## " section, up to the line before the second "## " heading.
b1_root="$fix/b1-root"; mkdir -p "$b1_root/audit"
printf '# Audit\n\n- **Commit:** x\n\n## Summary\n\n- one\n- two\n\n## Worklist\n\nrest\nrest\n' > "$b1_root/audit/state-2026-04-04T0000Z.md"
b1() { printf '%s' "$(read_event "$1" "$b1_root/audit/state-2026-04-04T0000Z.md" "" '{"offset":1,"limit":'"$2"'}' '{"startLine":1,"numLines":'"$2"',"totalLines":13}')" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$b1_root" bash "$recorder"; }
b1 "b1-a-$$" 9
present_file 'an audit read covering the short form counts' "$marker_dir/b1-a-$$-read-main-core.audit.2026-04-04T0000Z"
b1 "b1-b-$$" 7
absent_file 'an audit read that stops inside the short form does not' "$marker_dir/b1-b-$$-read-main-core.audit.2026-04-04T0000Z"
present_file 'a relevant Read leaves the sign that the record runs' "$marker_dir/b1-b-$$-recorder.on"
printf '%s' "$(read_event "b1-c-$$" "$b1_root/audit/state-2026-04-04T0000Z.md" "" '{"offset":2,"limit":12}' '{"startLine":2,"numLines":12,"totalLines":13}')" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$b1_root" bash "$recorder"
absent_file 'an audit read that starts after line 1 does not count' "$marker_dir/b1-c-$$-read-main-core.audit.2026-04-04T0000Z"
printf '# Audit\n```\n## not a heading\n```\n## Summary\n- one\n## Worklist\nrest\n' > "$b1_root/audit/state-2026-05-05T0000Z.md"
printf '%s' "$(read_event "b1-d-$$" "$b1_root/audit/state-2026-05-05T0000Z.md" "" '{"offset":1,"limit":5}' '{"startLine":1,"numLines":5,"totalLines":8}')" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$b1_root" bash "$recorder"
absent_file 'a heading inside a code fence does not end the short form' "$marker_dir/b1-d-$$-read-main-core.audit.2026-05-05T0000Z"
printf '%s' "$(read_event "b1-e-$$" "/work/src/Program.cs")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$b1_root" bash "$recorder"
present_file 'any Read leaves the sign that the record runs' "$marker_dir/b1-e-$$-recorder.on"
# ww3d/playbook#533: the short form ends at its last non-blank line, not at the blank line before the
# next heading; a short read leaves the line reached and the end, a counting read removes them.
b1_marker="core.audit.2026-04-04T0000Z"
b1 "b1-g-$$" 7
absent_file 'one line less than the last non-blank line does not count' "$marker_dir/b1-g-$$-read-main-$b1_marker"
expect 'a short read leaves the line reached and the end of the short form' "7 8" "$(cat "$marker_dir/b1-g-$$-read-main-$b1_marker.short" 2>/dev/null)"
b1 "b1-g-$$" 6
expect 'a later, shorter read does not lower the line reached' "7 8" "$(cat "$marker_dir/b1-g-$$-read-main-$b1_marker.short" 2>/dev/null)"
b1 "b1-g-$$" 8
present_file 'the read that reaches the end counts after a short one' "$marker_dir/b1-g-$$-read-main-$b1_marker"
absent_file 'and removes the line-reached file' "$marker_dir/b1-g-$$-read-main-$b1_marker.short"
b1 "b1-f-$$" 8
present_file 'a read exactly through the last non-blank line of the short form counts' "$marker_dir/b1-f-$$-read-main-$b1_marker"
absent_file 'a counting read leaves no line-reached file' "$marker_dir/b1-f-$$-read-main-$b1_marker.short"
b1_file="$b1_root/audit/state-2026-06-06T0000Z.md"
b1x() { # session, limit, total lines
  printf '%s' "$(read_event "$1" "$b1_file" "" '{"offset":1,"limit":'"$2"'}' '{"startLine":1,"numLines":'"$2"',"totalLines":'"$3"'}')" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$b1_root" bash "$recorder"
}
printf '# Audit\n\n## Summary\n\n- one\n\n\n\n## Worklist\nrest\n' > "$b1_file"
b1x "b1-h-$$" 4 10
absent_file 'a short form followed by several blank lines: stopping before its last line does not count' "$marker_dir/b1-h-$$-read-main-core.audit.2026-06-06T0000Z"
b1x "b1-h-$$" 5 10
present_file 'a short form followed by several blank lines: its last non-blank line counts' "$marker_dir/b1-h-$$-read-main-core.audit.2026-06-06T0000Z"
printf '# Audit\n```\n## not a heading\n```\n## Summary\n- one\n\n## Worklist\nrest\n' > "$b1_file"
b1x "b1-i-$$" 5 9
absent_file 'a heading in a code fence: a read to the line before the real heading is still short' "$marker_dir/b1-i-$$-read-main-core.audit.2026-06-06T0000Z"
b1x "b1-i-$$" 6 9
present_file 'a heading in a code fence: the last non-blank line before the real one counts' "$marker_dir/b1-i-$$-read-main-core.audit.2026-06-06T0000Z"
printf '# Audit\n\n## Summary\n- one\n' > "$b1_file"
b1x "b1-j-$$" 3 4
absent_file 'a file without a second heading: a read short of the whole file does not count' "$marker_dir/b1-j-$$-read-main-core.audit.2026-06-06T0000Z"
b1x "b1-j-$$" 4 4
present_file 'a file without a second heading: the whole file counts' "$marker_dir/b1-j-$$-read-main-core.audit.2026-06-06T0000Z"

# Without CLAUDE_PROJECT_DIR the root is not known: a core file records nothing, a rule file still does.
sid="core-d-$$"
before="$(n_markers)"
printf '%s' "$(read_event "$sid" "$repo_root/CLAUDE.md")" | TMPDIR="$gate_tmp" env -u CLAUDE_PROJECT_DIR bash "$recorder"
expect 'no CLAUDE_PROJECT_DIR: a core file records nothing' "$before" "$(n_markers)"

echo "== record-rule-read.sh: only a file inside the project counts =="
sid="bind-$$"
record "$(read_event "$sid" "/elsewhere/.agents/rules/pr.md")"
absent_file 'a rule file of another checkout leaves no marker' "$marker_dir/${sid}-read-main-pr"
record "$(read_event "$sid" "$repo_root/../elsewhere/.agents/rules/pr.md")"
absent_file 'a path climbing out through .. leaves no marker' "$marker_dir/${sid}-read-main-pr"
record "$(read_event "$sid" "$repo_root/.agents/rules/pr.md")"
present_file 'the same rule file inside the project leaves it' "$marker_dir/${sid}-read-main-pr"
sid="bind-cwd-$$"
rr_ev="$(read_event "$sid" "$repo_root/.agents/rules/pr.md")"; js "$repo_root"
printf '%s%s%s' "${rr_ev%%'"cwd":"/nonexistent"'*}" "\"cwd\":$REPLY" "${rr_ev#*'"cwd":"/nonexistent"'}" \
  | TMPDIR="$gate_tmp" env -u CLAUDE_PROJECT_DIR bash "$recorder"
present_file 'without CLAUDE_PROJECT_DIR the payload cwd is the root' "$marker_dir/${sid}-read-main-pr"
sid="bind-cwd2-$$"
printf '%s' "$(read_event "$sid" "$repo_root/.agents/rules/pr.md")" | TMPDIR="$gate_tmp" env -u CLAUDE_PROJECT_DIR bash "$recorder"
absent_file 'without CLAUDE_PROJECT_DIR a cwd elsewhere refuses it' "$marker_dir/${sid}-read-main-pr"

finish
