#!/usr/bin/env bash
# Hook suite section: require-live-state.sh, the live state at the tracking issue follows the session's own act
# Run alone: bash .claude/hooks/tests/cases/require-live-state.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-live-state.sh: the state label follows the session's own act (ww3d/playbook#577) =="
live="$hooks/require-live-state.sh"
ls_dir="$fix/live-state"; mkdir -p "$ls_dir"
export TMPDIR="$ls_dir/gate"; mkdir -p "$TMPDIR"
# The project: the playbook's table and session kinds, a working folder whose origin is example/repo.
ls_proj="$ls_dir/proj"; mkdir -p "$ls_proj/.agents"
cp "$repo_root/.agents/state-labels.json" "$repo_root/.agents/session-kinds.json" "$ls_proj/.agents/"
git -C "$ls_proj" init -q 2>/dev/null; git -C "$ls_proj" remote add origin https://github.com/Example/Repo.git 2>/dev/null
# The same project with the status rows struck: the label part must run unchanged.
ls_nostatus="$ls_dir/nostatus"; mkdir -p "$ls_nostatus/.agents"
cp "$repo_root/.agents/session-kinds.json" "$ls_nostatus/.agents/"
jq '.rows |= map(select(.part != "status"))' "$repo_root/.agents/state-labels.json" > "$ls_nostatus/.agents/state-labels.json"
# A gh stand-in: counts its calls, prints the issue body of $LS_BODY, fails with LS_GH_FAIL=1.
ls_bin="$ls_dir/bin"; mkdir -p "$ls_bin"
ls_calls="$ls_dir/gh-calls.log"
cat > "$ls_bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LS_CALLS"
[ "${LS_GH_FAIL:-0}" = 1 ] && exit 1
case "$*" in *repos/*/pulls/*|*repos/*/pulls\?*) printf '%s\n' "${LS_PRBODY-Refs #12}" ;; *) printf '%s\n' "${LS_BODY:-## Order}" ;; esac
GH
chmod +x "$ls_bin/gh"
export LS_CALLS="$ls_calls" PATH="$ls_bin:$PATH"

n_sid=0
ls_new() { n_sid=$((n_sid + 1)); sid="live-$$-$n_sid"; proj="$ls_proj"; } # a fresh session
ls_hook() { CLAUDE_PROJECT_DIR="$proj" bash "$live" "$@" 2>/dev/null; }
ls_bash() { # command, [stdout of the call] -> recorded
  local c o; js "$1"; c="$REPLY"; js "${2:-}"; o="$REPLY"
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s},"tool_response":{"stdout":%s,"stderr":""}}' \
    "$sid" "$proj" "$c" "$o" | ls_hook --record
}
ls_mcp() { # tool, tool_input json, [tool_response json] -> recorded
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"mcp__github__%s","tool_input":%s,"tool_response":%s}' \
    "$sid" "$proj" "$1" "$2" "${3:-null}" | ls_hook --record
}
ls_prompt() { local p; js "$1"; p="$REPLY"; printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":%s}' "$sid" "$proj" "$p" | ls_hook --record; }
ls_stop() { # [stop_hook_active] -> globals out, verdict BLOCK | WARN | ALLOW | ERR
  out="$(printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$sid" "${1:-false}" | ls_hook)"
  if   has_text '"decision":"block"' "$out"; then verdict=BLOCK
  elif has_text 'systemMessage' "$out"; then verdict=WARN
  elif [ -z "$out" ]; then verdict=ALLOW; else verdict=ERR; fi
}
ls_expect() { ls_stop "${3:-false}"; expect "$1" "$2" "$verdict"; }
ls_gh_calls() { if [ -s "$ls_calls" ]; then wc -l < "$ls_calls" | tr -d '[:space:]'; else echo 0; fi; }

echo "-- each event, Bash and connector form, blocks until its label stands"
while IFS='|' read -r label want cmd outp; do
  ls_new; ls_bash "$cmd" "$outp"; ls_expect "event $label" BLOCK
  check_contains "event $label: reason names the label" "\`$want\`" "$out"
done <<'CASES'
draft gh api|state:dev|gh api repos/example/repo/pulls -f head=feat/12-x -f base=main -f title=t -F draft=true --jq .number|57
draft gh pr create|state:dev|gh pr create --draft --title t --body "Refs #12"|https://github.com/example/repo/pull/57
ready gh pr ready|state:review|gh pr ready 57|
approve gh pr review|state:gate|gh pr review 57 --approve|
approve gh api reviews|state:gate|gh api repos/example/repo/pulls/57/reviews -f event=APPROVE -f commit_id=abc|
approve verdict line|state:gate|gh api repos/example/repo/pulls/57/reviews -f event=COMMENT -f body="Review-Verdict: approve abc1234"|
merge gh pr merge|state:release|gh pr merge 57 --squash|
merge gh api|state:release|gh api -X PUT repos/example/repo/pulls/57/merge -f merge_method=squash|
CASES
while IFS='|' read -r label want tool input resp; do
  ls_new; ls_mcp "$tool" "$input" "$resp"; ls_expect "event $label" BLOCK
  check_contains "event $label: reason names the label" "\`$want\`" "$out"
done <<'CASES'
draft connector|state:dev|create_pull_request|{"owner":"example","repo":"repo","head":"feat/12-x","base":"main","title":"t","body":"Refs #12","draft":true}|{"number":57}
ready connector|state:review|update_pull_request|{"owner":"example","repo":"repo","pullNumber":57,"draft":false}|
approve connector|state:gate|pull_request_review_write|{"owner":"example","repo":"repo","pullNumber":57,"method":"create","event":"APPROVE"}|
merge connector|state:release|merge_pull_request|{"owner":"example","repo":"repo","pullNumber":57}|
CASES

ls_new; printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"PowerShell","tool_input":{"command":"gh pr ready 57"},"tool_response":{"stdout":""}}' "$sid" "$proj" | ls_hook --record
ls_expect 'event via the PowerShell tool' BLOCK
echo "-- no event, no block"
ls_new; ls_bash 'gh api repos/example/repo/pulls/57 --jq .head.sha'; ls_expect 'a read records nothing' ALLOW
ls_new; ls_mcp update_pull_request '{"owner":"example","repo":"repo","pullNumber":57,"title":"x"}'; ls_expect 'a title edit is no event' ALLOW
ls_new; ls_bash 'gh api repos/example/repo/pulls/57/reviews -f event=COMMENT -f body=nits'; ls_expect 'a comment review is no approve' ALLOW
ls_new; ls_mcp pull_request_review_write '{"owner":"example","repo":"repo","pullNumber":57,"method":"create","event":"REQUEST_CHANGES"}'; ls_expect 'a change request is no approve' ALLOW

echo "-- a read, a quoted text or a failed call is no write"
while IFS='|' read -r label cmd; do
  ls_new; ls_bash "$cmd"; ls_expect "no event: $label" ALLOW
done <<'CASES'
gh named in a commit message|git commit -m "docs: say gh pr merge 57 needs the gate"
gh named in a JSON test input|printf '{"tool_input":{"command":"gh pr review 57 --approve"}}' | bash hook.sh
gh named in an echo|echo then run gh pr ready 57
merge check is a GET|gh api repos/example/repo/pulls/57/merge
auto-merge merges nothing yet|gh pr merge 57 --auto --squash
reviews read with a verdict grep|gh api repos/example/repo/pulls/57/reviews --jq '.[].body' | grep 'Review-Verdict: approve'
CASES
ls_new; ls_bash 'gh pr ready 57'; ls_bash 'gh issue list -l state:review'; ls_expect 'a list filter sets no label' BLOCK
ls_new; ls_bash 'gh pr ready 57'; ls_bash "echo 'State-Gate-Released: pr-ready x'"; ls_expect 'an echoed released line releases nothing' BLOCK
ls_new; ls_bash 'gh pr ready 57'; ls_bash "gh issue edit 12 --add-label 'tracking, state:review'"; ls_expect 'a label list with spaces' ALLOW
ls_new; ls_bash 'GH_TOKEN=x timeout 30 gh pr ready 57'; ls_expect 'gh behind an assignment and timeout' BLOCK
ls_new; ls_bash 'gh api -X POST repos/example/repo/pulls/57/ccr/ready_for_review'; ls_expect 'ready through the cloud route' BLOCK
check_contains 'cloud route: state:review' '`state:review`' "$out"
ls_new; ls_bash 'gh api -X POST repos/example/repo/pulls/57/ccr/convert_to_draft'; ls_expect 'back to draft is no event (366b-04)' ALLOW
ls_new; ls_bash 'gh pr ready 57 --undo'; ls_expect 'gh pr ready --undo is no event (366b-04)' ALLOW
ls_new; ls_mcp update_pull_request '{"owner":"example","repo":"repo","pullNumber":57,"draft":true}'; ls_expect 'connector back to draft is no event (366b-04)' ALLOW
ls_new; printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr ready 57"},"tool_response":{"stdout":"","stderr":"HTTP 403: Forbidden"}}' "$sid" "$proj" | ls_hook --record
ls_expect 'a failed call records nothing' ALLOW
ls_new; ls_prompt '/controller-mode example/repo'; ls_prompt 'colour #1e1e1e only'; ls_expect 'a hex colour names no issue' ALLOW
ls_new; ls_prompt '/controller-mode example/repo'
printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"Skill","tool_input":{"skill":"pr-poll-review"},"tool_response":{}}' "$sid" "$proj" | ls_hook --record
ls_prompt '#12 Head abc bereit'; ls_expect 'the kind is set once: a later skill call keeps the controller' BLOCK
ls_new; ls_mcp get_file_contents '{"owner":"example","repo":"repo","path":"x"}'; ls_expect 'a connector read records nothing' ALLOW
expect 'a connector read leaves no journal' 0 "$( [ -e "$TMPDIR/claude-rule-gate/live-state/$sid.jsonl" ] && echo 1 || echo 0)"

echo "-- the command as the shell reads it (lib/segments.awk)"
ls_new; ls_bash $'git push -u origin x\ngh pr ready 57'; ls_expect 'a gh call on the second line' BLOCK
ls_bash $'git status\ngh issue edit 12 --add-label state:review'; ls_expect 'a label on the second line fulfils' ALLOW
ls_new; ls_bash 'git commit -m "fix; gh pr merge 57 needs the gate"'; ls_expect 'a ; inside quotes is no command' ALLOW
ls_new; ls_bash 'git commit -m "docs: explain (gh pr ready 57)"'; ls_expect 'a ( inside quotes is no command' ALLOW
ls_new; ls_bash $'cat <<\'EOF\' > note.md\ngh pr ready 57\nEOF'; ls_expect 'a heredoc body is no command' ALLOW
ls_new; ls_bash 'T='"'"'Review: `gh pr merge 57` needs the gate; then (gh pr ready 57)'"'"'; printf "%s\n" "$T" > r.md'; ls_expect 'Markdown with backticks in a quoted text' ALLOW
ls_new; ls_bash 'gh api repos/example/repo/pulls/57/reviews/991/events -f event=APPROVE'; ls_expect 'approve through the review events route' BLOCK
ls_new; ls_bash 'gh pr ready 57'; printf '{"labels":["tracking","state:review"]}\n' > "$ls_dir/labels.json"
ls_bash "gh api repos/example/repo/issues/12/labels --input $ls_dir/labels.json"; ls_expect 'labels sent with --input fulfil' ALLOW
ls_new; ls_bash 'gh pr merge https://github.com/other/repo/pull/5 --squash'; ls_stop
check_contains 'a PR URL names its repository' 'other/repo#12' "$out"
ls_bash 'gh api repos/other/repo/issues/12/labels -f "labels[]=state:release"'; ls_expect 'the label in that repository fulfils' ALLOW

echo "-- a failed call records nothing"
ls_new; printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr merge 57 --squash"},"tool_response":{"stdout":"","stderr":"X Pull request example/repo#57 is not mergeable: the base branch policy prohibits the merge."}}' "$sid" "$proj" | ls_hook --record
ls_expect 'a refused merge (stderr)' ALLOW
ls_new; printf '{"session_id":"%s","hook_event_name":"PostToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"gh pr merge 57 2>&1 | tail -3"},"tool_response":{"stdout":"X Pull request example/repo#57 is not mergeable","stderr":""}}' "$sid" "$proj" | ls_hook --record
ls_expect 'a refused merge (moved to stdout)' ALLOW
ls_new; ls_mcp merge_pull_request '{"owner":"example","repo":"repo","pullNumber":57}' '"failed to merge pull request: 405 Pull Request is not mergeable"'
ls_expect 'a refused merge (connector)' ALLOW
ls_new; ls_mcp merge_pull_request '{"owner":"example","repo":"repo","pullNumber":57}' '{"isError":true,"content":[{"type":"text","text":"boom"}]}'
ls_expect 'a connector error flag' ALLOW

echo "-- the released line: same repository, with a reason"
ls_new; ls_bash 'gh pr create --draft --body "Refs #12"' 'https://github.com/example/repo/pull/57'
ls_mcp add_issue_comment '{"owner":"other","repo":"repo","issue_number":12,"body":"State-Gate-Released: pr-draft-opened x"}'; ls_expect 'a released line in another repository' BLOCK
ls_mcp add_issue_comment '{"owner":"example","repo":"repo","issue_number":12,"body":"State-Gate-Released: pr-draft-opened"}'; ls_expect 'a released line without a reason' BLOCK
ls_mcp add_issue_comment '{"owner":"example","repo":"repo","issue_number":12,"body":"State-Gate-Released: pr-draft-opened label API down"}'; ls_expect 'a released line with a reason' ALLOW

echo "-- tracking issue: only the design session"
ls_new; ls_prompt '/ccweb-prompt example/repo'; ls_bash 'gh issue create --title t --label tracking --body b' 'https://github.com/example/repo/issues/88'
ls_expect 'design opens a tracking issue without state:design' BLOCK
check_contains 'design: reason names the new issue' 'example/repo#88' "$out"
ls_new; ls_prompt '/ccweb-prompt example/repo'; ls_bash 'gh issue create --title t --label tracking,state:design --body b' 'https://github.com/example/repo/issues/88'
ls_expect 'design opens it with state:design' ALLOW
ls_new; ls_prompt '/anthropic-skills:ccweb-prompt x'; ls_mcp issue_write '{"owner":"example","repo":"repo","method":"create","title":"t","labels":["tracking"]}' '{"number":88}'
ls_expect 'design (plugin skill line), connector create without state:design' BLOCK
ls_mcp issue_write '{"owner":"example","repo":"repo","method":"update","issue_number":88,"labels":["tracking","state:design"]}'
ls_expect 'design: connector label list with state:design fulfils it' ALLOW
ls_new; ls_bash 'gh issue create --title t --label tracking --body b' 'https://github.com/example/repo/issues/88'
ls_expect 'a dev session opening a tracking issue is no event' ALLOW

echo "-- a later own label of the same repository fulfils the event"
ls_new; ls_bash 'gh api repos/example/repo/pulls -f head=feat/12-x -F draft=true' '{"number":57}'
ls_bash 'gh api repos/example/repo/issues/12/labels -f "labels[]=state:dev"'; ls_expect 'labels[]= fulfils' ALLOW
ls_new; ls_bash 'gh pr ready 57'; ls_bash 'gh issue edit 12 --add-label state:review --remove-label state:dev'; ls_expect '--add-label fulfils' ALLOW
ls_new; ls_bash 'gh pr ready 57'; ls_bash 'gh issue edit 12 --add-label state:dev --remove-label state:review'; ls_expect 'another label does not' BLOCK
ls_new; ls_bash 'gh pr ready 57'; ls_bash 'gh api -X DELETE repos/example/repo/issues/12/labels/state:review'; ls_expect 'a removal does not' BLOCK
ls_new; ls_bash 'gh pr ready 57'; ls_bash 'gh api repos/other/repo/issues/12/labels -f "labels[]=state:review"'; ls_expect 'another repository does not' BLOCK
ls_new; ls_bash 'gh api repos/example/repo/issues/12/labels -f "labels[]=state:review"'; ls_bash 'gh pr ready 57'; ls_expect 'a label set before the event does not' BLOCK
ls_new; ls_bash 'gh pr ready 57 --repo Example/Repo'; ls_mcp issue_write '{"owner":"Example","repo":"Repo","method":"update","issue_number":12,"labels":["tracking","state:review"]}'
ls_expect 'repository names match without case' ALLOW
ls_new; ls_bash 'gh pr ready 57 && gh api repos/example/repo/issues/12/labels -f "labels[]=state:review"'; ls_expect 'event and label in one line' ALLOW

echo "-- the reason names label, tracking issue and PR"
ls_new; ls_bash 'gh api repos/example/repo/pulls -f head=feat/12-x -F draft=true --jq .number' '57'; ls_bash 'gh pr ready 57'; ls_stop
check_contains 'reason: issue from the head branch' 'example/repo#12' "$out"
check_contains 'reason: the readied PR keeps its issue' 'set `state:review` on example/repo#12' "$out"
check_contains 'reason: the PR' 'PR #57' "$out"
: > "$ls_calls"
ls_new; ls_bash 'gh pr review 57 --approve'; ls_stop
check_contains 'reason: issue unknown -> read from the PR body anchor' 'set `state:gate` on example/repo#12' "$out"
check_contains 'reason: the PR body was read' 'repos/example/repo/pulls/57' "$(cat "$ls_calls")"
ls_new; ls_bash 'gh pr review 57 --approve'; LS_PRBODY='no anchor here' ls_expect 'a PR without a tracking issue (no anchor) is freed' ALLOW
ls_new; ls_bash 'gh pr ready' '✓ Pull request example/repo#57 is marked as "ready for review"'; ls_stop
check_contains 'no number: the PR from the output' 'set `state:review` on example/repo#12' "$out"
check_contains 'no number: the PR from the output is read' 'repos/example/repo/pulls/57' "$(cat "$ls_calls")"
: > "$ls_calls"
ls_new; ls_bash 'gh pr merge --squash'; ls_stop
check_contains 'no number, no output: the PR of the branch' 'set `state:release` on example/repo#12' "$out"
check_contains 'no number, no output: read by the branch' 'pulls?head=example:' "$(cat "$ls_calls")"
ls_new; ls_bash 'gh pr merge --squash'; LS_PRBODY='' ls_expect 'no number, the branch has no PR or no anchor: freed' ALLOW
: > "$ls_calls"
ls_new; ls_bash 'gh pr ready'; LS_PRBODY='Refs #12' LS_BODY=$'State-Gate-Skip: x' ls_expect 'no number: skip line of the issue named by the PR of the branch' ALLOW
expect 'no number: two reads' 2 "$(ls_gh_calls)"
: > "$ls_calls"
ls_new; ls_bash 'gh pr review 57 --approve'; LS_BODY=$'State-Gate-Skip: by hand' ls_expect 'skip line of the issue named by the PR body' ALLOW
expect 'skip through the PR body: two reads' 2 "$(ls_gh_calls)"
body="$ls_dir/body.md"; printf 'Closes #34\n' > "$body"
ls_new; ls_bash "gh api repos/example/repo/pulls -f head=fix/x -F body=@$body -F draft=true" '57'; ls_stop
check_contains 'reason: anchor from the body file' 'example/repo#34' "$out"

echo "-- without an open event: no output, no network"
: > "$ls_calls"
ls_new; ls_expect 'nothing recorded' ALLOW
ls_bash 'gh pr ready 57'; ls_bash 'gh issue edit 12 --add-label state:review'; ls_expect 'all fulfilled' ALLOW
expect 'no gh call without an open event' 0 "$(ls_gh_calls)"
expect 'the journal is emptied once nothing is open' 0 "$(wc -c < "$TMPDIR/claude-rule-gate/live-state/$sid.jsonl" | tr -d '[:space:]')"
ls_bash 'gh pr ready 57'; expect 'recording does not call gh' 0 "$(ls_gh_calls)"

echo "-- the released line after two blocks"
ls_new; ls_bash 'gh pr ready 57'
ls_stop; c1="$out"; ls_stop; c2="$out"; ls_stop; c3="$out"
check_not_contains 'block 1 names no way past' 'State-Gate-Released' "$c1"
check_not_contains 'block 2 names no way past' 'State-Gate-Released' "$c2"
check_contains 'block 3 names the released line' 'State-Gate-Released: <event> <reason>' "$c3"
check_contains 'block 3 names the event' 'event: pr-ready' "$c3"
ls_mcp add_issue_comment '{"owner":"example","repo":"repo","issue_number":12,"body":"State-Gate-Released: pr-ready label API down"}'
ls_expect 'the own released line frees the event' ALLOW
ls_new; ls_bash 'gh pr ready 57'; ls_bash "gh api repos/example/repo/issues/12/comments -f body='State-Gate-Released: pr-merged x'"
ls_expect 'a released line for another event does not' BLOCK

echo "-- State-Gate-Skip at the tracking issue"
: > "$ls_calls"
ls_new; ls_bash 'gh pr create --draft --body "Refs #12"' 'https://github.com/example/repo/pull/57'
LS_BODY=$'## Order\nState-Gate-Skip: maintainer sets labels by hand' ls_expect 'skip line frees the issue' ALLOW
expect 'skip: one read of the issue' 1 "$(ls_gh_calls)"
check_contains 'skip: the read names the issue' 'repos/example/repo/issues/12' "$(cat "$ls_calls")"
ls_expect 'skip: holds at the next stop without a read' ALLOW
expect 'skip: no second read' 1 "$(ls_gh_calls)"
ls_new; ls_bash 'gh pr create --draft --body "Refs #12"' 'https://github.com/example/repo/pull/57'
LS_BODY=$'## Order\nnot State-Gate-Skip: here' ls_expect 'skip only as a line of its own' BLOCK

echo "-- loop guard"
ls_new; ls_bash 'gh pr ready 57'; ls_expect 'loop: first stop blocks' BLOCK
ls_expect 'loop: continued without a tool call ends the turn' WARN true
check_contains 'loop: says the event stays open' 'stays open' "$out"
ls_expect 'loop: the event blocks again at the next turn end' BLOCK
ls_bash 'git status'; ls_expect 'loop: a tool call since the block blocks again' BLOCK true

echo "-- fail-open"
ls_new; ls_bash 'gh pr create --draft --body "Refs #12"' 'https://github.com/example/repo/pull/57'
LS_GH_FAIL=1 ls_expect 'a failed read of the issue ends the turn' ALLOW
ls_new; ls_bash 'gh api repos/example/repo/pulls -f head=feat/12-x -F draft=true' '57'
nojq="$ls_dir/nojq"; mkdir -p "$nojq"; for t in bash cat wc tr date head sed git grep mkdir rm timeout; do p="$(command -v "$t")" && ln -sf "$p" "$nojq/$t"; done
out="$(printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$sid" | CLAUDE_PROJECT_DIR="$proj" PATH="$nojq" "$(command -v bash)" "$live" 2>/dev/null)"
expect 'no jq ends the turn' '' "$out"
ln -sf "$(command -v jq)" "$nojq/jq"
out="$(printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$sid" | CLAUDE_PROJECT_DIR="$proj" PATH="$nojq" "$(command -v bash)" "$live" 2>/dev/null)"
expect 'no gh ends the turn' '' "$out"
ls_new; ls_bash 'gh pr ready 57'
out="$(printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$sid" | CLAUDE_PROJECT_DIR="$ls_dir/no-table" bash "$live" 2>/dev/null)"
expect 'no table ends the turn' '' "$out"
ro="$ls_dir/ro-file"; : > "$ro"
out="$(printf '{"session_id":"x1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"gh pr ready 1"}}' | TMPDIR="$ro" CLAUDE_PROJECT_DIR="$proj" bash "$live" --record 2>&1; echo "rc=$?")"
expect 'an unwritable folder: record ends quietly' 'rc=0' "$out"

echo "-- status comment: controller only, a removable part"
ls_new; ls_prompt '/controller-mode example/repo'; ls_prompt '#12 Head abc1234 bereit'; ls_expect 'controller: a message naming an issue' BLOCK
check_contains 'controller: reason names the status comment' 'rewrite the status comment on example/repo#12' "$out"
ls_bash 'gh api -X PATCH repos/example/repo/issues/comments/991 -F body=@status.md'; ls_expect 'controller: editing a comment fulfils it' ALLOW
ls_new; ls_prompt '/controller-mode example/repo'; ls_prompt 'see https://github.com/example/repo/pull/57'
ls_mcp update_issue_comment '{"owner":"example","repo":"repo","comment_id":991,"body":"Stand"}'; ls_expect 'controller: connector comment edit fulfils it' ALLOW
ls_new; ls_prompt '/controller-mode example/repo'; ls_bash 'gh pr merge 57 --squash'
ls_bash 'gh api repos/example/repo/issues/12/labels -f "labels[]=state:release"'; ls_expect 'controller: own event needs the status comment too' BLOCK
check_contains 'controller: status after the own event' 'status-after-event pr-merged' "$out"
ls_bash 'gh issue comment 12 --edit-last --body-file s.md'; ls_expect 'controller: --edit-last fulfils it' ALLOW
ls_new; ls_prompt '/dev-task example/repo#12'; ls_prompt '#12 Review zu abc steht'; ls_expect 'dev: a message is no status event' ALLOW
ls_new; proj="$ls_nostatus"; ls_prompt '/controller-mode example/repo'; ls_prompt '#12 Head abc bereit'
ls_expect 'status rows struck: no status event' ALLOW
ls_bash 'gh pr merge 57 -R example/repo'; ls_expect 'status rows struck: the label part still blocks' BLOCK
check_not_contains 'status rows struck: no status comment named' 'rewrite the status comment' "$out"
ls_bash 'gh api repos/example/repo/issues/12/labels -f "labels[]=state:release"'; ls_expect 'status rows struck: the label alone fulfils' ALLOW

echo "-- learning log and --stats"
export TMPDIR="$ls_dir/gate-stats"; mkdir -p "$TMPDIR"
ls_new; ls_bash 'gh pr create --draft --body "Refs #12"' 'https://github.com/example/repo/pull/57'; ls_stop
ls_bash 'gh issue edit 12 --add-label state:dev'; ls_stop
ls_bash 'gh pr ready 57'; ls_stop
ls_mcp add_issue_comment '{"owner":"example","repo":"repo","issue_number":12,"body":"State-Gate-Released: pr-ready label API down"}'; ls_stop
st="$(bash "$live" --stats)"; printf '%s\n' "$st"
check_contains 'stats: counts with numbers' 'blocked 2, fulfilled 1, released 1, skipped 0, passed 0' "$st"
check_contains 'stats: counts per event' 'blocks for pr-ready: 1' "$st"

finish
