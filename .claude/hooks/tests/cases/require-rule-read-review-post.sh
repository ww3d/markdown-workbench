#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, the review post
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-review-post.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-rule-read.sh: the review post needs /pr-poll-review for the current head =="
rv_root="$fix/rv-root"
mkdir -p "$rv_root/.agents/rules" "$rv_root/.claude/skills/pr-poll-review"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rv_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rv_root/.claude/skills/pr-poll-review/SKILL.md"
ghstub="$fix/ghstub"; mkdir -p "$ghstub"
cat > "$ghstub/gh" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_GH_LOG:-}" ] || printf '%s\n' "$*" >> "$STUB_GH_LOG"
[ -z "${STUB_GH_FAIL:-}" ] || exit 1
printf '%s\n' "${STUB_GH_OUT:-}"
STUB
chmod +x "$ghstub/gh"
head_a="$(printf 'a%.0s' {1..40})"; head_b="$(printf 'b%.0s' {1..40})"
rv_last="$fix/rv-last.out"
rv_verdict() { # transcript, tool, tool_input json, gh stdout, [gh fails] [project dir] [extra markers] [gh log file]
  local sid out rc root="${6:-$rv_root}" m
  sid="$(next_sid)"
  mkdir -p "$gate_tmp/claude-rule-gate"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
  for m in ${7:-}; do : > "$gate_tmp/claude-rule-gate/${sid}-read-main-${m}"; done
  out="$(printf '%s' "$(tool_event "$1" "$2" "$3" "$sid")" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$root" PATH="${RV_PATH:+$RV_PATH:}$ghstub:$PATH" STUB_GH_OUT="$4" STUB_GH_FAIL="${5:-}" STUB_GH_LOG="${8:-}" bash "$ruleread" 2>&1)"; rc=$?
  printf '%s' "$out" > "$rv_last"
  if   has_text '"permissionDecision":"deny"' "$out"; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  elif has_text 'systemMessage' "$out" && [ "$rc" = 0 ]; then printf 'WARN'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
gh_cmd='{"command":"gh pr review 5 -R o/r --approve --body ok"}'
gh_url="${head_a}" # what the stub prints for `gh api repos/o/r/pulls/5 --jq .head.sha`
expect 'no skill line at all'                              DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'skill line for the current head'                   ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'skill line, the PR head moved since'               DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "${head_b}")"
expect 'skill line for another PR'                         DENY  "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'the line only carried as data does not count'      DENY  "$(rv_verdict "$fix/review-head-data.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a refused command does not count'                  DENY  "$(rv_verdict "$fix/review-head-refused.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a compaction ends the skill run'                   DENY  "$(rv_verdict "$fix/review-head-then-compact.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'the repo name compares without case'               ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 -R O/R --approve"}' "${head_a}")"
expect 'gh cannot answer, the PR is named, a line exists'  WARN  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "" 1)"
expect 'gh cannot answer, the PR is named, no line'        DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "" 1)"
expect 'gh cannot answer, another PR has the line'         DENY  "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash "$gh_cmd" "" 1)"
expect 'a PowerShell call is gated like a Bash call'       DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" PowerShell "$gh_cmd" "$gh_url")"
expect 'the PR given as a URL'                             ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review https://github.com/o/r/pull/5 --comment -b 7"}' "$gh_url")"
mcp_in='{"owner":"o","repo":"r","pullNumber":5,"method":"create","event":"APPROVE"}'
expect 'the connector: no skill line'                      DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url")"
expect 'the connector: skill line for the current head'    ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url")"
expect 'the connector: deleting a pending review is free'  ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write '{"owner":"o","repo":"r","pullNumber":5,"method":"delete_pending"}' "$gh_url")"
expect 'a comment on a pending review is not the post'     ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__add_comment_to_pending_review '{"owner":"o","repo":"r","pullNumber":5}' "$gh_url")"
expect 'gh pr comment is not a review post'                ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh pr comment 5 --body x"}' "$gh_url")"
no_skill="$fix/rv-no-skill"; mkdir -p "$no_skill/.agents/rules"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$no_skill/.agents/rules/$r.md"; done
expect 'a repository without the skill demands nothing'    ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "$gh_url" "" "$no_skill")"

echo "== require-rule-read.sh: the reviews endpoint through gh api is the same post =="
api_post='{"command":"gh api repos/o/r/pulls/5/reviews -f event=APPROVE -f body=ok"}'
expect 'gh api POST to the reviews endpoint: no skill line'   DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$api_post" "$gh_url")"
expect 'gh api POST: skill line for the current head'         ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "$gh_url")"
expect 'gh api POST: the PR head moved since'                 DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "${head_b}")"
expect 'gh api with -X POST and an input file'                DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api -X POST repos/o/r/pulls/5/reviews --input r.json"}' "$gh_url")"
expect 'gh api through PowerShell'                            DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" PowerShell "$api_post" "$gh_url")"
expect 'a submit of a pending review (events)'                DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/reviews/77/events -f event=COMMENT"}' "$gh_url")"
expect 'gh api GET of the reviews is a read'                  ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/reviews"}' "$gh_url")"
expect 'gh api GET with a query field stays a read'           ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api --method GET repos/o/r/pulls/5/reviews -f per_page=1"}' "$gh_url")"
expect 'gh api to another endpoint is no review post'         ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/comments -f body=x"}' "$gh_url")"
sid_api="$(next_sid)"
expect 'gh api also owes the review rule (unread: refused)'   DENY  "$(rule_verdict "$(tool_event "$fix/rule-no-receipt.jsonl" Bash "$api_post" "$sid_api")" "$rv_root")"
gh_log="$fix/gh-args.log"
gh_args() { # tool_input json -> the first gh call of the hook (the forge is asked for a PR with a skill line only)
  : > "$gh_log"
  rv_verdict "$fix/review-head-5-and-352.jsonl" Bash "$1" "$gh_url" "" "" "" "$gh_log" >/dev/null
  head -n1 "$gh_log"
}
expect 'gh api: the PR is read from the endpoint'             'api repos/o/r/pulls/5 --jq .head.sha' \
  "$(gh_args "$api_post")"

# A post that names no repository takes the one of the origin remote (https and ssh spelling).
rv_git="$fix/rv-git"
mkdir -p "$rv_git/.agents/rules" "$rv_git/.claude/skills/pr-poll-review"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rv_git/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rv_git/.claude/skills/pr-poll-review/SKILL.md"
git -C "$rv_git" init -q
git -C "$rv_git" remote add origin https://github.com/o/r.git
: > "$gh_log"
expect 'no -R: the repo comes from origin (https)'            ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 --approve"}' "$gh_url" "" "$rv_git" "" "$gh_log")"
expect 'no -R: gh is asked for the origin repo'               'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"
git -C "$rv_git" remote set-url origin git@github.com:o/r.git
: > "$gh_log"
rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 --approve"}' "$gh_url" "" "$rv_git" "" "$gh_log" >/dev/null
expect 'no -R: the repo comes from origin (ssh)'              'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"

echo "== require-rule-read.sh: gh api reads only its own words and its method as gh does (ww3d/playbook#544) =="
# A root with pr.md, the review rules and the skill's references: a dismissal owes pr.md alone, a post all of them.
dm_root="$fix/dm-root"
mkdir -p "$dm_root/.agents/rules" "$dm_root/.claude/skills/pr-poll-review/reference" "$dm_root/.claude/skills/controller-mode"
for r in pr review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$dm_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$dm_root/.claude/skills/pr-poll-review/SKILL.md"
for r in gates checks; do printf '# %s\n' "$r" > "$dm_root/.claude/skills/pr-poll-review/reference/$r.md"; done
dm() { # command, [markers], [tool], [transcript] -> the verdict with only the markers given read
  local sid out rc m js_cmd
  sid="$(next_sid)"; mkdir -p "$gate_tmp/claude-rule-gate"
  for m in ${2:-}; do : > "$gate_tmp/claude-rule-gate/${sid}-read-main-${m}"; done
  js "$1"; js_cmd="$REPLY"
  out="$(printf '%s' "$(tool_event "${4:-$nr}" "${3:-Bash}" "{\"command\":${js_cmd}}" "$sid")" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$dm_root" PATH="$ghstub:$PATH" STUB_GH_OUT="$gh_url" bash "$ruleread" 2>&1)"; rc=$?
  printf '%s' "$out" > "$rv_last"
  if   has_text '"permissionDecision":"deny"' "$out"; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  elif has_text 'systemMessage' "$out" && [ "$rc" = 0 ]; then printf 'WARN'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
nr="$fix/rule-no-receipt.jsonl"
all_read='pr review evidence skill-pr-poll-review-gates skill-pr-poll-review-checks'
rv5='repos/o/r/pulls/5/reviews'
# The measured probes: reads stay free, whatever follows the call behind a separator.
expect 'read: a grep -F behind a pipe is no field'          ALLOW "$(dm "gh api $rv5 --paginate --jq '.[].body' | grep -F Verdict")"
expect 'read: plain GET'                                    ALLOW "$(dm "gh api $rv5")"
expect 'read: --jq with a pipe inside the filter'           ALLOW "$(dm "gh api $rv5 --jq '.[] | .state'")"
expect 'read: -q'                                           ALLOW "$(dm "gh api $rv5 -q '.[].id'")"
expect 'read: piped to jq'                                  ALLOW "$(dm "gh api $rv5 | jq .")"
expect 'read: piped to Select-String (PowerShell)'          ALLOW "$(dm "gh api $rv5 | Select-String Verdict" '' PowerShell)"
expect 'read: gh pr view --json reviews'                    ALLOW "$(dm 'gh pr view 5 --json reviews')"
expect 'read: a -f of the next command after ;'             ALLOW "$(dm "gh api $rv5; grep -f pat out.txt")"
expect 'read: a -f of the next command after &&'            ALLOW "$(dm "gh api $rv5 && echo -f")"
expect 'read: --method=GET with a query field'              ALLOW "$(dm "gh api --method=GET $rv5 -f per_page=1")"
expect 'free: -X DELETE of a pending review'                ALLOW "$(dm "gh api -X DELETE $rv5/77")"
expect 'free: a quoted text that names a post'              ALLOW "$(dm "git commit -m \"gh api $rv5 -f event=APPROVE\"")"
expect 'free: a heredoc that writes a probe script'         ALLOW "$(dm "cat > p.sh <<'EOF'"$'\n'"gh api $rv5 -f event=APPROVE"$'\n'"EOF")"
# Writes: a field without a method is a POST, as gh sends it, and the denial names the way to read.
expect 'post: -F per_page=100 without a method'             DENY  "$(dm "gh api $rv5 -F per_page=100")"
check_contains 'the denial names --method GET'              '--method GET' "$(cat "$rv_last")"
expect 'post: a field behind a redirection'                 DENY  "$(dm "gh api $rv5 2>&1 -f event=APPROVE")"
expect 'post: -XPUT edits the text of a review'             DENY  "$(dm "gh api -XPUT $rv5/77 -f body=x")"
check_not_contains 'an explicit method gets no read hint'   '--method GET' "$(cat "$rv_last")"
expect 'post: a heredoc read by bash holds one'             DENY  "$(dm "bash <<'EOF'"$'\n'"gh api $rv5 -f event=APPROVE"$'\n'"EOF")"
expect 'post: denied until the review refs are read'      DENY  "$(dm "gh api $rv5 -f event=APPROVE" 'pr review evidence')"
check_contains 'the post owes gates.md'                     'pr-poll-review/reference/gates.md' "$(cat "$rv_last")"
# Words that join or hide a call: a continued line, an escaped separator, a group, a redirection before the endpoint.
nl=$'\n'
# A CR goes into the text through a variable: Git Bash drops one written as $'\r' inside $( ).
cr=$'\r'
expect 'post: a backslash-newline continues the call'      DENY  "$(dm "gh api $rv5 \\${nl}  -f event=APPROVE")"
expect 'post: flags first, continued over three lines'     DENY  "$(dm "gh api \\${nl}  -X POST \\${nl}  $rv5 \\${nl}  -f event=APPROVE")"
expect 'read: the next line is another command'            ALLOW "$(dm "gh api $rv5${nl}grep -f pat out.txt")"
expect 'post: a backtick continues it in PowerShell'       DENY  "$(dm "gh api \`${nl}  -X POST \`${nl}  $rv5 \`${nl}  -f event=APPROVE" '' PowerShell)"
expect 'post: a $(...) field before the endpoint'          DENY  "$(dm "gh api -f event=APPROVE -f body=\"\$(cat b.md)\" $rv5")"
expect 'post: an --input <(...) before the endpoint'       DENY  "$(dm "gh api --input <(jq -n '{}') $rv5")"
expect 'post: an escaped ; in a field value'               DENY  "$(dm "gh api -f body=a\\;b -f event=APPROVE $rv5")"
expect 'post: a redirection before the endpoint'           DENY  "$(dm "gh api > out.json -X POST $rv5 -f event=APPROVE")"
expect 'post: &> is no separator'                          DENY  "$(dm "gh api $rv5 &>/dev/null -f event=APPROVE")"
expect 'post: <& is no separator'                          DENY  "$(dm "gh api $rv5 <&0 -f event=APPROVE")"
# A substitution in the call may hold quotes and brackets the masking cannot follow: the call is then read up to the
# next `gh api`, its first review endpoint counted (fail-closed).
expect 'post: a $(cat "$f") field before the endpoint'     DENY  "$(dm "gh api -f body=\"\$(cat \"\$f\")\" -f event=APPROVE $rv5")"
expect 'post: a heredoc body with 1) before the endpoint'  DENY  "$(dm "gh api -X POST -f event=APPROVE -f body=\"\$(cat <<'EOF'${nl}Two points:${nl}1) naming${nl}EOF${nl})\" $rv5")"
expect 'post: a ) quoted inside the substitution'          DENY  "$(dm "gh api -f body=\"\$(echo ')')\" $rv5")"
expect 'post: a backtick substitution before the endpoint' DENY  "$(dm "gh api -f body=\`cat b.md\` $rv5")"
expect 'post: a nested group before the endpoint'          DENY  "$(dm "gh api -f n=\$(( (1+2) * 3 )) $rv5")"
expect 'post: $(Get-Content) before the endpoint (PowerShell)' DENY "$(dm "gh api -X POST -f \"body=\$(Get-Content \"b.md\" -Raw)\" $rv5" '' PowerShell)"
expect 'dismissal: a $(cat "$m") message, pr.md not read'  DENY  "$(dm "gh api -X PUT -f message=\"\$(cat \"\$m\")\" $rv5/9/dismissals")"
check_contains 'that denial names pr.md'                   '.agents/rules/pr.md' "$(cat "$rv_last")"
expect 'read: a $(...) filter before the endpoint'         ALLOW "$(dm "gh api --jq \"\$(cat q.jq)\" $rv5")"
expect 'read: a substitution, then a field of the next command (over-block)' DENY "$(dm "gh api -H \"\$(cat h)\" $rv5; grep -f x y")"
expect 'post: a CRLF continuation'                         DENY  "$(dm "gh api $rv5 \\${cr}${nl}  -f event=APPROVE")"
expect 'dismissal continued over lines, pr.md not read'    DENY  "$(dm "gh api \\${nl}  -X PUT $rv5/9/dismissals -f message=x")"
check_contains 'the continued dismissal names pr.md'       '.agents/rules/pr.md' "$(cat "$rv_last")"
expect 'post: REST through gh.exe'                         DENY  "$(dm "gh.exe api $rv5 -f event=APPROVE")"
expect 'post: >| before the endpoint'                      DENY  "$(dm "gh api >| out -X POST $rv5")"
expect 'post: *> before the endpoint (PowerShell)'         DENY  "$(dm "gh api *> \$null -X POST $rv5" '' PowerShell)"
expect 'post: an event field gets no read hint'            DENY  "$(dm "gh api $rv5 -f event=APPROVE")"
check_not_contains 'a named post field gets no read hint'  '--method GET' "$(cat "$rv_last")"
# lib/heredoc.sh: an operator inside quotes or a comment is none; an assignment before the heredoc runs nothing.
expect 'a quoted <<EOF opens no heredoc'                   DENY  "$(dm "echo '<<EOF'${nl}gh api $rv5 -f event=APPROVE${nl}EOF")"
expect 'a <<EOF in a comment opens no heredoc'             DENY  "$(dm "echo hi # <<EOF${nl}gh api $rv5 -f event=APPROVE${nl}EOF")"
expect 'an assignment before a heredoc to cat'             ALLOW "$(dm "n=1; cat >> m.sh <<'EOF'${nl}gh api $rv5 -f event=APPROVE${nl}EOF")"
expect 'a quoted assignment before a heredoc to cat'       ALLOW "$(dm "x=\"a\"; cat >> m.sh <<'EOF'${nl}gh api $rv5 -f event=APPROVE${nl}EOF")"
expect 'an unlisted command before the heredoc keeps it'   DENY  "$(dm "head a > m.sh; cat >> m.sh <<'EOF'${nl}gh api $rv5 -f event=APPROVE${nl}EOF")"
# A gh called by a quoted path, PowerShell's $env:GH_REPO, a host before the repo, and a change of folder.
expect 'post through a quoted gh.exe path (PowerShell)'    DENY  "$(dm "& 'C:/Program Files/GitHub CLI/gh.exe' api $rv5 -f event=APPROVE" '' PowerShell)"
expect 'graphql through a quoted gh.exe path'              DENY  "$(dm "& \"C:\\Program Files\\GitHub CLI\\gh.exe\" api graphql -f query='mutation { submitPullRequestReview(input: {}) { clientMutationId } }'" "$all_read" PowerShell)"
expect 'gh pr review through a quoted path'                DENY  "$(dm "& 'C:/Program Files/GitHub CLI/gh.exe' pr review 5 -R o/r --approve" '' PowerShell)"
expect 'a quoted path that names gh is no call'            ALLOW "$(dm "echo 'C:/tools/gh' api $rv5 -f event=APPROVE")"
# A command starts after a keyword, a case label, a PowerShell assignment and inside iex, too.
expect 'post after if'                                     DENY  "$(dm "if gh api $rv5 -f event=APPROVE; then echo ok; fi")"
expect 'post after elif'                                   DENY  "$(dm "if false; then :; elif gh api $rv5 -f event=APPROVE; then :; fi")"
expect 'post after while'                                  DENY  "$(dm "while gh api $rv5 -f event=APPROVE; do break; done")"
expect 'post after until'                                  DENY  "$(dm "until gh api $rv5 -f event=APPROVE; do break; done")"
expect 'post after a case label'                           DENY  "$(dm "case x in x) gh api $rv5 -f event=APPROVE;; esac")"
expect 'post after $null = (PowerShell)'                   DENY  "$(dm "\$null = gh api $rv5 -f event=APPROVE" '' PowerShell)"
expect 'post inside iex (PowerShell)'                      DENY  "$(dm "iex 'gh api $rv5 -f event=APPROVE'" '' PowerShell)"
expect 'post inside Invoke-Expression (PowerShell)'        DENY  "$(dm "Invoke-Expression \"gh api $rv5 -f event=APPROVE\"" '' PowerShell)"
expect 'gh pr review after if'                             DENY  "$(dm "if gh pr review 5 -R o/r --approve; then :; fi")"
# Short flags bundled behind gh's boolean -i count as the last one.
expect 'post: -iX POST'                                    DENY  "$(dm "gh api -iX POST $rv5 -f event=APPROVE")"
expect 'post: -iXPOST'                                     DENY  "$(dm "gh api -iXPOST $rv5 --input r.json")"
expect 'post: -if event=APPROVE'                           DENY  "$(dm "gh api $rv5 -if event=APPROVE")"
expect 'post: -iFevent=APPROVE'                            DENY  "$(dm "gh api $rv5 -iFevent=APPROVE")"
expect 'post: -iH before the endpoint'                     DENY  "$(dm "gh api -iH x $rv5 -f event=APPROVE")"
expect 'read: -i alone'                                    ALLOW "$(dm "gh api -i $rv5")"
# A value flag's word is no endpoint.
for vf in -t --template -p --preview --cache; do
  expect "post: $vf before the endpoint"                   DENY  "$(dm "gh api $vf x $rv5 -f event=APPROVE")"
done
# A literal <<EOF inside "..." with a substitution opens no heredoc; one inside the substitution does.
expect 'a <<EOF in "...$(...)" opens no heredoc'          DENY  "$(dm "echo \"x <<EOF \$(pwd)\"${nl}gh pr review 5 -R o/r --approve${nl}EOF")"
# A quoted delimiter drops the body; an unquoted one keeps its substitutions as code.
expect 'a quoted heredoc drops its substitution'           ALLOW "$(dm "cat <<'EOF'${nl}\$(gh api $rv5 -f event=APPROVE)${nl}EOF")"
expect 'an unquoted heredoc keeps its substitution (api)'  DENY  "$(dm "cat <<EOF${nl}\$(gh api $rv5 -f event=APPROVE)${nl}EOF")"
# A call longer than the window is read as a post whose PR is unknown, and the denial names the way out.
long_body="$(head -c 8300 /dev/zero | tr '\0' x)"
expect 'post: an 8 KB field before the endpoint'           DENY  "$(dm "gh api -X POST -f body='$long_body' -f event=APPROVE $rv5")"
check_contains 'the denial names a body file'              'body=@file' "$(cat "$rv_last")"
expect 'read: an 8 KB call that names no review'           ALLOW "$(dm "gh api -X POST -f body='$long_body' repos/o/r/issues/5/comments")"
# A match that crosses 4 KB of text is found whole.
pad="$(head -c 3500 /dev/zero | tr '\0' x)"; val="$(head -c 700 /dev/zero | tr '\0' y)"
expect 'a post behind 3.5 KB with a 700-byte prefix'       DENY  "$(dm "echo $pad; BODY=$val gh pr review 5 -R o/r --approve")"
# A PR or review id given as a variable takes the path of an unknown PR.
expect 'post to pulls/$PR/reviews'                         DENY  "$(dm "gh api repos/o/r/pulls/\$PR/reviews -f event=APPROVE")"
expect 'post to pulls/${PR}/reviews, a skill line'         WARN  "$(dm "gh api repos/o/r/pulls/\${PR}/reviews -f event=APPROVE" "$all_read" Bash "$fix/review-head-a.jsonl")"
expect 'dismissal of reviews/$ID, pr.md not read'          DENY  "$(dm "gh api -X PUT repos/o/r/pulls/5/reviews/\$ID/dismissals -f message=x")"
check_contains 'the variable dismissal names pr.md'        '.agents/rules/pr.md' "$(cat "$rv_last")"
# Each flag form gh reads, flags before the endpoint included.
expect 'post: a field before the endpoint'                 DENY  "$(dm "gh api -f event=APPROVE $rv5")"
expect 'post: a header before the endpoint'                DENY  "$(dm "gh api -H 'Accept: application/vnd.github+json' $rv5 -f event=APPROVE")"
expect 'post: --hostname before the endpoint'              DENY  "$(dm "gh api --hostname github.com $rv5 -f event=APPROVE")"
expect 'read: -q before the endpoint'                      ALLOW "$(dm "gh api -q .id $rv5")"
expect 'post: an attached -fevent=APPROVE'                 DENY  "$(dm "gh api $rv5 -fevent=APPROVE")"
expect 'post: --field='                                    DENY  "$(dm "gh api $rv5 --field=event=APPROVE")"
expect 'post: --raw-field'                                 DENY  "$(dm "gh api $rv5 --raw-field body=x")"
expect 'post: --input without a method'                    DENY  "$(dm "gh api $rv5 --input r.json")"
expect 'post: --input='                                    DENY  "$(dm "gh api $rv5 --input=r.json")"
expect 'read: -XGET with a query field'                    ALLOW "$(dm "gh api -XGET $rv5 -f per_page=1")"
expect 'post: -XPOST to the reviews'                       DENY  "$(dm "gh api -XPOST $rv5 -f event=APPROVE")"
check_not_contains 'an explicit POST gets no read hint'    '--method GET' "$(cat "$rv_last")"
expect 'read: -X get in lower case'                        ALLOW "$(dm "gh api -X get $rv5 -f per_page=1")"
expect 'post: -X post in lower case'                       DENY  "$(dm "gh api -X post $rv5 --input r.json")"
expect 'read: -X HEAD'                                     ALLOW "$(dm "gh api -X HEAD $rv5 -f per_page=1")"
expect 'post: a quoted endpoint'                           DENY  "$(dm "gh api \"$rv5\" -f event=APPROVE")"
expect 'post: a quoted method'                             DENY  "$(dm "gh api -X \"POST\" $rv5 --input r.json")"
# Every api post of a command is checked against the skill's lines, like every `gh pr review`.
expect 'two api posts, the second for a PR without a line' DENY  "$(dm "gh api $rv5 -f event=COMMENT; gh api repos/o/r/pulls/6/reviews -f event=APPROVE" "$all_read" Bash "$fix/review-head-a.jsonl")"
check_contains 'the denial names the PR without a line'    'o/r#6' "$(cat "$rv_last")"
expect 'gh pr review and an api post for another PR'       DENY  "$(dm "gh pr review 5 -R o/r --approve; gh api repos/o/r/pulls/6/reviews -f event=APPROVE" "$all_read" Bash "$fix/review-head-a.jsonl")"
check_contains 'the mixed denial names the api PR'         'o/r#6' "$(cat "$rv_last")"
expect 'two api posts for the PR of the line'              ALLOW "$(dm "gh api $rv5 -f event=COMMENT; gh api $rv5 -f event=APPROVE" "$all_read" Bash "$fix/review-head-a.jsonl")"
# A dismissal owes pr.md alone: no review rule, no skill reference, no '/pr-poll-review' run.
dismiss="gh api -X PUT $rv5/123/dismissals -f message=superseded"
expect 'dismissal: pr.md read'                              ALLOW "$(dm "$dismiss" pr)"
expect 'dismissal: pr.md not read'                          DENY  "$(dm "$dismiss")"
check_contains 'the denial names pr.md'                     '.agents/rules/pr.md' "$(cat "$rv_last")"
check_contains 'the denial names controller-mode step 5'    'controller-mode/SKILL.md, step 5' "$(cat "$rv_last")"
check_not_contains 'the denial does not ask for review.md'  'review.md' "$(cat "$rv_last")"
expect 'dismissal: --method PUT, pr.md read'                ALLOW "$(dm "gh api --method PUT $rv5/123/dismissals -f message=x" pr)"
expect 'dismissal: --method PUT, pr.md not read'            DENY  "$(dm "gh api --method PUT $rv5/123/dismissals -f message=x")"
check_contains 'the --method PUT denial names pr.md'        '.agents/rules/pr.md' "$(cat "$rv_last")"
expect 'a post next to a dismissal still owes the review'   DENY  "$(dm "$dismiss; gh api $rv5 -f event=APPROVE" pr)"
# The placeholders gh fills from the checkout name no repo: the origin remote is the target.
: > "$gh_log"
expect 'post to {owner}/{repo}: the origin repo'            ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE"}' "$gh_url" "" "$rv_git" "" "$gh_log")"
expect 'post to {owner}/{repo}: gh is asked for o/r'        'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"
expect 'post to {owner}/{repo} with GH_REPO of another repo' DENY "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"GH_REPO=ghost/x gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE"}' "$gh_url" "" "$rv_git")"
expect 'post to {owner}/{repo} with GH_REPO of the line'    ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"GH_REPO=o/r gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE"}' "$gh_url" "" "$rv_git")"

echo "== require-rule-read.sh: review mutations through gh api graphql (ww3d/playbook#544) =="
gql() { printf 'gh api graphql -f query='"'"'mutation { %s(input: {pullRequestId: "PR_1"}) { clientMutationId } }'"'" "$1"; }
for mut in addPullRequestReview submitPullRequestReview updatePullRequestReview; do
  expect "graphql $mut: no skill run"                      DENY  "$(dm "$(gql "$mut")" "$all_read")"
  check_contains "graphql $mut: the denial asks for the run" "no '/pr-poll-review' ran" "$(cat "$rv_last")"
done
expect 'graphql post: the references are owed'              DENY  "$(dm "$(gql addPullRequestReview)" 'review evidence')"
expect 'graphql post with a skill line: the PR is unknown'  WARN  "$(dm "$(gql addPullRequestReview)" "$all_read" Bash "$fix/review-head-a.jsonl")"
check_contains 'the warning says the head was not compared' 'GraphQL post names node ids only' "$(cat "$rv_last")"
expect 'graphql dismissPullRequestReview: pr.md read'       ALLOW "$(dm "$(gql dismissPullRequestReview)" pr)"
expect 'graphql dismissPullRequestReview: pr.md not read'   DENY  "$(dm "$(gql dismissPullRequestReview)")"
check_contains 'graphql dismissal names controller-mode'    'controller-mode/SKILL.md, step 5' "$(cat "$rv_last")"
for mut in deletePullRequestReview addPullRequestReviewComment addPullRequestReviewThread; do
  expect "graphql $mut is free"                            ALLOW "$(dm "$(gql "$mut")")"
done
expect 'graphql query without a mutation is free'           ALLOW "$(dm "gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { pullRequest(number: 5) { reviews(first: 5) { nodes { state } } } } }'")"
expect 'graphql mutation in a heredoc fed to gh'            DENY  "$(dm "gh api graphql --input - <<'EOF'"$'\n''{"query": "mutation { addPullRequestReview(input: {}) { clientMutationId } }"}'$'\n'"EOF" "$all_read")"
expect 'a mutation word in a heredoc to cat, no call'       ALLOW "$(dm "cat > q.graphql <<'EOF'"$'\n'"mutation { submitPullRequestReview(input: {}) { clientMutationId } }"$'\n'"EOF")"
expect 'graphql through gh.exe'                             DENY  "$(dm "gh.exe api graphql -f query='mutation { submitPullRequestReview(input: {}) { clientMutationId } }'" "$all_read")"
expect 'graphql with two blanks before api'                DENY  "$(dm "gh  api graphql -f query='mutation { addPullRequestReview(input: {}) { clientMutationId } }'" "$all_read")"
expect 'graphql by its full URL'                           DENY  "$(dm "gh api https://api.github.com/graphql -f query='mutation { addPullRequestReview(input: {}) { clientMutationId } }'" "$all_read")"
# Wanted over-block: once a `gh api graphql` call stands, the mutation word counts anywhere in the command text.
expect 'a mutation word beside a graphql query (over-block)' DENY "$(dm "gh api graphql -f query='query { viewer { login } }'; echo submitPullRequestReview" "$all_read")"
expect 'a mutation word with gh api elsewhere, not graphql' ALLOW "$(dm "gh api $rv5 --jq . # submitPullRequestReview")"

echo "== require-rule-read.sh: gh pr review counts at a command position only =="
nr="$fix/rule-no-receipt.jsonl"
expect 'a commit message that names it'                  ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"docs: the gh pr review gate\""}' "$gh_url")"
expect 'a pr comment that names it'                      ALLOW "$(rv_verdict "$nr" Bash '{"command":"gh pr comment 5 --body \"see gh pr review 5\""}' "$gh_url")"
expect 'a single-quoted text that names it'              ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo '"'"'gh pr review 5'"'"'"}' "$gh_url")"
expect 'an escaped quote does not end the text early'    ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"fix \\\"x\\\" gh pr review y\""}' "$gh_url")"
expect 'the post at the start, several spaces'           DENY  "$(rv_verdict "$nr" Bash '{"command":"gh   pr  review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post after &&'                               DENY  "$(rv_verdict "$nr" Bash '{"command":"cd x && gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post on a line of its own'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"cd x\ngh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post behind an environment assignment'       DENY  "$(rv_verdict "$nr" Bash '{"command":"GH_TOKEN=x gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post with a path and .exe'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"/usr/bin/gh.exe pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post inside bash -c'                         DENY  "$(rv_verdict "$nr" Bash '{"command":"bash -c \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'the post inside a command substitution'          DENY  "$(rv_verdict "$nr" Bash '{"command":"echo \"$(gh pr review 5 -R o/r --approve)\""}' "$gh_url")"
expect 'the shell flag in capitals, quoted'              DENY  "$(rv_verdict "$nr" Bash '{"command":"pwsh -Command \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'the shell flag in capitals, unquoted'            DENY  "$(rv_verdict "$nr" Bash '{"command":"powershell -Command gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'cmd /c, quoted'                                  DENY  "$(rv_verdict "$nr" Bash '{"command":"cmd /c \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'cmd /c, unquoted'                                DENY  "$(rv_verdict "$nr" Bash '{"command":"cmd /c gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'cmd /K, unquoted'                                DENY  "$(rv_verdict "$nr" Bash '{"command":"CMD /K gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'bash -lc, unquoted'                              DENY  "$(rv_verdict "$nr" Bash '{"command":"bash -lc gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the verb in capitals'                            DENY  "$(rv_verdict "$nr" Bash '{"command":"GH PR REVIEW 5 -R o/r --approve"}' "$gh_url")"
expect 'behind sudo with an option'                      DENY  "$(rv_verdict "$nr" Bash '{"command":"sudo -u x gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind env with an option'                       DENY  "$(rv_verdict "$nr" Bash '{"command":"env -i gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind timeout with a number'                    DENY  "$(rv_verdict "$nr" Bash '{"command":"timeout 5 gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind xargs'                                    DENY  "$(rv_verdict "$nr" Bash '{"command":"echo 5 | xargs gh pr review"}' "$gh_url")"
expect 'behind a wrapper with a path'                    DENY  "$(rv_verdict "$nr" Bash '{"command":"/usr/bin/env gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'options between gh and pr'                       DENY  "$(rv_verdict "$nr" Bash '{"command":"gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options between pr and review'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"gh pr -R x review 5 --approve"}' "$gh_url")"
expect 'a switch before pr'                              DENY  "$(rv_verdict "$nr" Bash '{"command":"gh --paginate pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'options in the middle, behind sudo'              DENY  "$(rv_verdict "$nr" Bash '{"command":"sudo gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options in the middle: a skill line for the PR'  ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options in the middle: the line is for another PR' DENY "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash '{"command":"gh pr -R o/r review 5 --approve"}' "$gh_url")"
expect 'gh -R ... pr view is no review'                  ALLOW "$(rv_verdict "$nr" Bash '{"command":"gh -R o/r pr view 5"}' "$gh_url")"
expect 'a quoted mention with options is no review'      ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"gh -R o/r pr review 5\""}' "$gh_url")"
# The target repo is read from the `gh` TOKEN: a "gh" inside a slug or a path is no `gh` word, and an attached
# `-Ro/r`, a `GH_REPO=` assignment and quoted values name the repo too. The line is for o/r#5 and the origin
# remote is o/r, so a lost repo option would fall back to o/r and ALLOW.
chk_target() { expect "$1" "$2" "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$3" "$gh_url" "" "$rv_git")"; }
chk_target 'slug with gh: -R ghost/x'                     DENY  '{"command":"gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: -R o/ghx'                       DENY  '{"command":"gh -R o/ghx pr review 5 --approve"}'
chk_target 'slug with gh: --repo ghost/x'                 DENY  '{"command":"gh --repo ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: --repo=ghost/x'                 DENY  '{"command":"gh --repo=ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: -R after pr'                    DENY  '{"command":"gh pr --repo ghost/x review 5 --approve"}'
chk_target 'slug with gh: gh behind a path'               DENY  '{"command":"/usr/bin/gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: a gh folder before the command' DENY  '{"command":"cd /tmp/gh && gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: gh.exe'                         DENY  '{"command":"gh.exe -R ghost/x pr review 5 --approve"}'
chk_target '-R with the value attached'                   DENY  '{"command":"gh -Rghost/x pr review 5 --approve"}'
chk_target '-R with the value attached: the right repo'   ALLOW '{"command":"gh -Ro/r pr review 5 --approve"}'
chk_target 'quoted -R value'                              DENY  '{"command":"gh -R \"ghost/x\" pr review 5 --approve"}'
chk_target 'GH_REPO names another repo'                   DENY  '{"command":"GH_REPO=ghost/x gh pr review 5 --approve"}'
chk_target 'GH_REPO quoted'                               DENY  '{"command":"GH_REPO=\"ghost/x\" gh pr review 5 --approve"}'
chk_target 'GH_REPO behind env'                           DENY  '{"command":"env GH_REPO=ghost/x gh pr review 5 --approve"}'
chk_target 'GH_REPO names the repo of the line'           ALLOW '{"command":"GH_REPO=o/r gh pr review 5 --approve"}'
chk_target '-R beats GH_REPO'                             ALLOW '{"command":"GH_REPO=ghost/x gh -R o/r pr review 5 --approve"}'
# Any earlier `GH_REPO=` assignment is the target, exported or not (a later `export GH_REPO`, `declare -x`, `set -a`
# and `export A=1 GH_REPO=...` are not parsed: a plain one blocks too); `-R=o/r` is the repo o/r; `env -u` clears it.
chk_target 'GH_REPO set apart by ; counts as the target'  DENY  '{"command":"GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'GH_REPO, then export GH_REPO'                 DENY  '{"command":"GH_REPO=ghost/x; export GH_REPO; gh pr review 5 --approve"}'
chk_target 'declare -x GH_REPO='                          DENY  '{"command":"declare -x GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export A=1 GH_REPO='                          DENY  '{"command":"export A=1 GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export -- GH_REPO='                           DENY  '{"command":"export -- GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'set -a, then GH_REPO='                        DENY  '{"command":"set -a; GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export GH_REPO with a quoted value'           DENY  '{"command":"export GH_REPO=\"ghost/x\"; gh pr review 5 --approve"}'
chk_target 'GH_REPO= of the repo of the line'             ALLOW '{"command":"GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target 'an earlier GH_REPO= of another repo blocks'      DENY  '{"command":"GH_REPO=ghost/x; GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target '-R=o/r'                                       ALLOW '{"command":"gh -R=o/r pr review 5 --approve"}'
chk_target '-R=ghost/x'                                   DENY  '{"command":"gh -R=ghost/x pr review 5 --approve"}'
chk_target 'env -u GH_REPO clears the target'             ALLOW '{"command":"GH_REPO=ghost/x env -u GH_REPO gh pr review 5 --approve"}'
chk_target 'env --unset=GH_REPO clears the target'        ALLOW '{"command":"GH_REPO=ghost/x env --unset=GH_REPO gh pr review 5 --approve"}'
chk_target 'env -u of another name keeps the target'      DENY  '{"command":"GH_REPO=ghost/x env -u FOO gh pr review 5 --approve"}'
# Every post of a command is checked, the target of an earlier `export` counts, a heredoc text does not hide the
# real call, and a `#` comment holds no command and no option. Any earlier `GH_REPO=` that differs from the checked
# target blocks, a prefix of another command too (fail-closed).
chk_target 'export GH_REPO earlier in the command'        DENY  '{"command":"export GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'GH_REPO= as the prefix of another command'      DENY  '{"command":"export GH_REPO=ghost/x; GH_REPO=o/r gh pr view 5; gh pr review 5 --approve"}'
chk_target 'export GH_REPO of the line'                   ALLOW '{"command":"export GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target 'export GH_REPO, then env -u (fail-closed)'      DENY  '{"command":"export GH_REPO=ghost/x; env -u GH_REPO gh pr review 5 --approve"}'
chk_target 'two posts, the second for another PR'         DENY  '{"command":"gh pr review 5 -R o/r --approve; gh pr review 6 -R o/r --approve"}'
chk_target 'two posts, both for the PR of the line'       ALLOW '{"command":"gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --approve"}'
chk_target 'a heredoc text before the real post'          DENY  '{"command":"cat <<EOF\ngh -R o/r pr review 5\nEOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a comment with -R is no option'               ALLOW '{"command":"gh pr review 5 --approve # -R ghost/x"}'
expect 'a comment that holds a post is no post'          ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo hi # ; gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'a # inside a word starts no comment'             DENY  "$(rv_verdict "$nr" Bash '{"command":"echo a#b; gh pr review 5 -R o/r --approve"}' "$gh_url")"
# A heredoc body that only data takes (`cat`, a file) holds no post (lib/heredoc.sh); one an interpreter reads
# (`bash <<EOF`, `| sh`) and one that never ends stay code, so their post for a PR without a line blocks.
chk_target 'a heredoc text after the real post'           ALLOW '{"command":"gh pr review 5 -R o/r --approve; cat <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a body file by heredoc before the post'       ALLOW '{"command":"cat > b.md <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF\ngh pr review 5 -R o/r --approve --body-file b.md"}'
chk_target 'a <<- heredoc with a tab-indented end'        ALLOW '{"command":"cat <<-EOF\n\tgh pr review 6 -R o/r --approve\n\tEOF\ngh pr review 5 -R o/r --approve"}'
chk_target 'an unquoted heredoc keeps its substitution'   DENY  '{"command":"cat <<EOF\n$(gh pr review 6 -R o/r --approve)\nEOF"}'
# Without lib/heredoc.sh no body is stripped: the post quoted in a heredoc to `cat` counts as a post.
rr_nolib="$fix/rr-nolib"; mkdir -p "$rr_nolib/lib"
cp "$ruleread" "$rr_nolib/"; cp "$hooks/lib/stdin.sh" "$hooks/lib/segments.awk" "$rr_nolib/lib/"
ruleread="$rr_nolib/require-rule-read.sh" chk_target 'without lib/heredoc.sh a body counts' DENY '{"command":"gh pr review 5 -R o/r --approve; cat <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
# Without lib/segments.awk, or with an awk that fails or is missing, the command cannot be split: the review gate
# passes the call.
rr_noseg="$fix/rr-noseg"; mkdir -p "$rr_noseg/lib"
cp "$ruleread" "$rr_noseg/"; cp "$hooks/lib/stdin.sh" "$hooks/lib/heredoc.sh" "$rr_noseg/lib/"
ruleread="$rr_noseg/require-rule-read.sh" chk_target 'without lib/segments.awk the call passes' ALLOW '{"command":"gh pr review 6 -R o/r --approve"}'
awkfail="$fix/awkfail"; mkdir -p "$awkfail"; printf '#!/usr/bin/env bash\nexit 2\n' > "$awkfail/awk"; chmod +x "$awkfail/awk"
expect 'an awk that fails lets the call pass'             ALLOW "$(RV_PATH="$awkfail" rv_verdict "$nr" Bash '{"command":"gh pr review 6 -R o/r --approve"}' "$gh_url")"
noawk="$fix/noawk"; mkdir -p "$noawk"
# A wrapper per tool, not a link: Git Bash copies an .exe for ln -s, and the copy finds none of its DLLs.
for t in bash jq git cat timeout date tail grep mkdir rm; do
  printf '#!%s\nexec %q "$@"\n' "$(command -v bash)" "$(command -v "$t")" > "$noawk/$t"; chmod +x "$noawk/$t"
done
expect 'a missing awk lets the review post pass'       0 "$(printf '%s' "$(tool_event "$nr" Bash '{"command":"gh pr review 6 -R o/r --approve"}' "$(next_sid)")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$rv_root" PATH="$noawk" "$noawk/bash" "$ruleread" 2>&1 | grep -c deny || true)"
chk_target 'a heredoc body with an apostrophe'            DENY  '{"command":"cat <<EOF\nit'"'"'s fine\nEOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a heredoc read by bash holds a post'          DENY  '{"command":"bash <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc piped to a shell holds a post'      DENY  '{"command":"cat <<EOF | sh\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc without a closing line is kept'     DENY  '{"command":"cat <<EOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a here-string is no heredoc'                  DENY  '{"command":"cat <<<x\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target '$env:GH_REPO names another repo (PowerShell)'  DENY  '{"command":"$env:GH_REPO = \"ghost/x\"; gh pr review 5 --approve"}'
chk_target '$env:GH_REPO names the repo of the line'       ALLOW '{"command":"$env:GH_REPO = \"o/r\"; gh pr review 5 --approve"}'
chk_target 'GH_REPO with a host names the repo'            ALLOW '{"command":"GH_REPO=github.com/o/r gh pr review 5 --approve"}'
chk_target '-R with a host names the repo'                 ALLOW '{"command":"gh pr review 5 -R github.com/o/r --approve"}'
# gh reads the repo of the folder it runs in: a change of folder before an unnamed post is read, or refused.
rv_other="$fix/rv-other"; mkdir -p "$rv_other"; git -C "$rv_other" init -q; git -C "$rv_other" remote add origin https://github.com/ghost/x.git
rv_same="$fix/rv-same"; mkdir -p "$rv_same"; git -C "$rv_same" init -q; git -C "$rv_same" remote add origin git@github.com:o/r.git
chk_target 'cd into a clone of another repo'               DENY  "{\"command\":\"cd $rv_other && gh pr review 5 --approve\"}"
chk_target 'cd into a clone of the repo of the line'       ALLOW "{\"command\":\"cd $rv_same && gh pr review 5 --approve\"}"
# The origin of a folder is asked once per command, however many posts run in it.
gitlog="$fix/git-calls.log"; gitstub="$fix/gitstub"; mkdir -p "$gitstub"
printf '#!/usr/bin/env bash\n[ "$3" != remote ] || echo x >> "%s"\nexec "%s" "$@"\n' "$gitlog" "$(command -v git)" > "$gitstub/git"
chmod +x "$gitstub/git"; : > "$gitlog"
RV_PATH="$gitstub" rv_verdict "$fix/review-head-a.jsonl" Bash "{\"command\":\"cd $rv_same && gh pr review 5 --comment; gh pr review 5 --approve\"}" "$gh_url" "" "$rv_git" >/dev/null
expect 'one origin lookup for two posts in one folder'     1     "$(wc -l < "$gitlog" | tr -d ' ')"
chk_target 'cd into a folder that is no clone'             DENY  '{"command":"cd / && gh pr review 5 --approve"}'
check_contains 'the denial names the way out'              '-R <owner>/<repo>' "$(cat "$rv_last")"
chk_target 'cd to a variable'                              DENY  '{"command":"cd \"$d\" && gh pr review 5 --approve"}'
chk_target 'cd, but the post names its repo'               ALLOW "{\"command\":\"cd $rv_other && gh pr review 5 -R o/r --approve\"}"
chk_target 'cd in a subshell that ended'                   ALLOW "{\"command\":\"(cd $rv_other); gh pr review 5 --approve\"}"
chk_target 'cd before an api post to {owner}/{repo}'       DENY  "{\"command\":\"cd $rv_other && gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE\"}"
chk_target 'Set-Location into the repo of the line'        ALLOW "{\"command\":\"Set-Location $rv_same; gh pr review 5 --approve\"}"
chk_target 'export GH_REPO inside a quoted text'          ALLOW '{"command":"echo \"export GH_REPO=ghost/x\"; gh pr review 5 --approve"}'
chk_target 'export GH_REPO in a subshell that ended'      ALLOW '{"command":"(export GH_REPO=ghost/x); gh pr review 5 --approve"}'
chk_target 'export GH_REPO in the same subshell'          DENY  '{"command":"(export GH_REPO=ghost/x; gh pr review 5 --approve)"}'
# A `#` starts a comment only behind an unescaped blank and outside `${...}`; a quote in a comment hides nothing.
chk_target 'an escaped blank before # is no comment'      DENY  '{"command":"echo \\ #; gh pr review 6 -R o/r --approve"}'
chk_target 'a # inside ${...} is no comment'              DENY  '{"command":"echo ${v:- #}; gh pr review 6 -R o/r --approve"}'
chk_target 'an apostrophe in a comment hides nothing'     DENY  '{"command":"echo hi # don'"'"'t\ngh pr review 6 -R o/r --approve\n# it'"'"'s"}'
chk_target 'a comment with an apostrophe after the post'  ALLOW '{"command":"gh pr review 5 -R o/r --approve # don'"'"'t worry"}'
chk_target 'a comment after a quoted span'                ALLOW '{"command":"echo \"x\" # ; gh pr review 6 -R o/r --approve"}'
# Without awk only the review gate passes: `gh pr create` in the same call still owes pr.md.
pr_root="$fix/pr-root"; mkdir -p "$pr_root/.agents/rules"; printf -- '---\ntrigger: pr\n---\n' > "$pr_root/.agents/rules/pr.md"
cr_root="$fix/cr-root"; mkdir -p "$cr_root/.agents/rules"; printf -- '---\ntrigger: carrier\n---\n' > "$cr_root/.agents/rules/carrier.md"
expect 'a missing awk keeps the carrier gate'            1     "$(printf '%s' "$(tool_event "$nr" Bash '{"command":"gh issue create -t x -b y; gh api user"}' "$(next_sid)")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$cr_root" PATH="$noawk" "$noawk/bash" "$ruleread" 2>&1 | grep -c '.agents/rules/carrier.md' || true)"
expect 'a missing awk keeps the pr gate'                  1     "$(printf '%s' "$(tool_event "$nr" Bash '{"command":"gh pr create -t x -b y; gh api repos/o/r/pulls/5/comments"}' "$(next_sid)")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$pr_root" PATH="$noawk" "$noawk/bash" "$ruleread" 2>&1 | grep -c '.agents/rules/pr.md' || true)"
deep="gh pr review 5 -R o/r --approve"; for _ in $(seq 1 20); do deep="eval $deep"; done
expect 'a post nested too deep is read fail-closed'       DENY  "$(dm "$deep" "$all_read")"
check_contains 'the denial names the nesting'              'nested more than 16 levels' "$(cat "$rv_last")"
# The endpoint of a call comes from a substitution: the commands inside it count for the call (fail-closed).
expect 'an endpoint only from $(...)'                     DENY  "$(dm "gh api \$(echo $rv5) -f event=APPROVE")"
expect 'a review id from $(...)'                          DENY  "$(dm "gh api $rv5/\$(cat id)/events -f event=APPROVE")"
expect 'PowerShell $r=gh pr review'                       DENY  "$(dm '$r=gh pr review 5 -R o/r --approve' '' PowerShell)"
# gh pr create in a quoted text is no command; at a command position it owes pr.md.
expect 'gh pr create in a quoted text owes nothing'       ALLOW "$(dm 'git commit -m "gh pr create"')"
expect 'gh pr create at a command position owes pr.md'    DENY  "$(dm 'echo x && gh pr create -t a -b b')"
# Flags and value options before the endpoint, long field forms, a query string, redirections: each still a post.
for pre in '--silent' '--paginate' '-i' '-q .id' '--jq .id' '--header X:1' '2>e' '< in' '0< in' '&>o'; do
  expect "post: $pre before the endpoint"                 DENY  "$(dm "gh api $pre $rv5 -f event=APPROVE")"
done
expect 'post: --field event=APPROVE'                      DENY  "$(dm "gh api $rv5 --field event=APPROVE")"
expect 'post: --raw-field=body=x'                         DENY  "$(dm "gh api $rv5 --raw-field=body=x")"
check_not_contains 'a named body field gets no read hint'  '--method GET' "$(cat "$rv_last")"
expect 'post: a query string on the endpoint'             DENY  "$(dm "gh api $rv5?x=1 -f event=APPROVE")"
# A call with a substitution reads on only up to the next gh api: that call's field is its own.
expect 'read: a substitution, then another gh api'        ALLOW "$(dm "gh api -H \"\$(cat h)\" $rv5 --jq .; gh api -f x=1 repos/o/r/issues/5/comments")"
# A substitution for the start of the path still names a review endpoint (fail-closed).
expect 'post: "$(...)/reviews" as the endpoint'          DENY  "$(dm "gh api \"\$(echo repos/o/r/pulls/5)/reviews\" -f event=APPROVE")"
expect 'read: "$(...)/reviews" with GET'                 ALLOW "$(dm "gh api --method GET \"\$(echo repos/o/r/pulls/5)/reviews\"")"
# A call without a substitution reads none of the records before it.
expect 'read: a call after another, no substitution'      ALLOW "$(dm "gh api $rv5 --jq .[].id; gh api -f x=\"\$(date)\" repos/o/r/issues/5/comments")"
expect 'a CR between the words is a blank'                DENY  "$(dm "gh pr${cr}review 5 -R o/r --approve")"
# GH_REPO for {owner}/{repo}: in scope or as the call's prefix, the last one is the target - before the folder.
expect '{owner}/{repo}: GH_REPO beats the folder'         ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "{\"command\":\"export GH_REPO=o/r; cd $rv_other; gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE\"}" "$gh_url" "" "$rv_git")"
: > "$gh_log"
expect '{owner}/{repo} with GH_REPO in scope'             ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"export GH_REPO=o/r; gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE"}' "$gh_url" "" "$rv_git" "" "$gh_log")"
expect '{owner}/{repo}: gh is asked for the GH_REPO'      'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"
expect '{owner}/{repo} with another GH_REPO in scope'     DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"export GH_REPO=o/x; gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE"}' "$gh_url" "" "$rv_git")"
expect 'a glued $env:GH_REPO="o/r" (PowerShell)'          ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" PowerShell '{"command":"$env:GH_REPO=\"o/r\"; gh pr review 5 --approve"}' "$gh_url" "" "$rv_git")"
expect 'a backtick does not leak GH_REPO'                 ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"echo `export GH_REPO=ghost/x`; gh pr review 5 --approve"}' "$gh_url" "" "$rv_git")"
# A body flag's value is no PR number, wherever it stands.
for b in '-b 3' '--body 3' '-F 3' '--body-file 3'; do
  expect "a body flag $b before the PR number"             'api repos/o/r/pulls/5 --jq .head.sha' \
    "$(gh_args "{\"command\":\"gh pr review $b 5 -R o/r --approve\"}")"
done
expect 'a URL with a path after the number'              'api repos/o/r/pulls/5 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review https://github.com/o/r/pull/5/files --approve"}')"
chk_target 'env --unset GH_REPO clears the target'        ALLOW '{"command":"GH_REPO=ghost/x env --unset GH_REPO gh pr review 5 --approve"}'
chk_target 'env -uGH_REPO clears the target'              ALLOW '{"command":"GH_REPO=ghost/x env -uGH_REPO gh pr review 5 --approve"}'
# The words of an earlier command's -c code are no substitution of a later call.
expect 'read: -c code before a call with a substitution'  ALLOW "$(dm "bash -c \"echo $rv5\"; gh api user -f a=\$(date) --jq .x # /reviews")"
# Code nested too deep still owes the rule of the gh command it holds.
deep="gh pr create -t a -b b"; for _ in $(seq 1 18); do deep="eval $deep"; done
expect 'gh pr create nested too deep owes pr.md'          DENY  "$(dm "$deep" 'review evidence skill-pr-poll-review-gates skill-pr-poll-review-checks')"
check_contains 'that denial names pr.md'                   '.agents/rules/pr.md' "$(cat "$rv_last")"
expect 'watch -n 5 gh pr review'                          DENY  "$(dm 'watch -n 5 gh pr review 5 -R o/r --approve')"
# Where the segmenter (lib/segments.awk) reads a command as the shell does.
expect 'a quoted text with a substitution holds no post'  ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo \"gh pr review 5 -R o/r $(date)\""}' "$gh_url")"
expect 'a -c of a program that is no shell holds no code' ALLOW "$(rv_verdict "$nr" Bash '{"command":"git -c \"gh pr review 5 -R o/r\" status"}' "$gh_url")"
expect 'a # right after ; starts a comment'               ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo a;#; gh pr review 6 -R o/r --approve"}' "$gh_url")"
expect 'the verb right before a ; is the post'            DENY  "$(rv_verdict "$nr" Bash '{"command":"echo 5 | xargs gh pr review; echo done"}' "$gh_url")"
chk_target 'a cd that is an argument changes no folder'   ALLOW '{"command":"echo cd /; gh pr review 5 --approve"}'
expect 'several spaces: the PR is still read'            'api repos/o/r/pulls/5 --jq .head.sha' \
  "$(gh_args '{"command":"gh   pr  review 5 -R o/r --approve"}')"

echo "== require-rule-read.sh: the lines are checked offline first, the forge is asked once per PR =="
# The forge calls of one command share a 15 s deadline and the hook has 30 s: so a post without a line is refused
# before any call, and the posts of one PR share one call.
posts_5_6='{"command":"gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --approve; gh pr review 6 -R o/r --approve"}'
: > "$gh_log"
expect 'a post on a PR without a line is refused'         DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$posts_5_6" "$gh_url" "" "" "" "$gh_log")"
check_contains 'the denial names the PR without a line'   'o/r#6' "$(cat "$rv_last")"
expect 'no gh call before that refusal'                  0     "$(wc -l < "$gh_log" | tr -d ' ')"
: > "$gh_log"
expect 'lines for both PRs, both heads current'           ALLOW "$(rv_verdict "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "$gh_url" "" "" "" "$gh_log")"
expect 'four posts on two PRs: one gh call per PR'       2     "$(wc -l < "$gh_log" | tr -d ' ')"
: > "$gh_log"
expect 'lines for both PRs, the heads moved'              DENY  "$(rv_verdict "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "${head_b}" "" "" "" "$gh_log")"
expect 'a stale head ends the hook after one gh call'     1     "$(wc -l < "$gh_log" | tr -d ' ')"

echo "== require-rule-read.sh: digits in a review body never replace the PR number =="
expect 'a body with a bare number'            'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review 352 -R o/r --approve -b \"LGTM, 2 nits fixed\""}')"
expect 'a body with a number, -R before the number'  'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --comment -b \"Siehe Punkt 3 unten\""}')"
expect 'a long body option, the number last'  'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r --approve --body \"3 nits, 4 questions\" 352"}')"
expect 'a body given with ='                 'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --body=\"fixes 7 of 9\""}')"
expect 'a wrapper number is no PR number'     'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"timeout 9 gh pr review 352 -R o/r --approve"}')"
expect 'the first number wins over a later one' 'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --approve 9"}')"

echo "== require-rule-read.sh: a review post needs gates.md and checks.md read (read state or receipt) =="
rf_root="$fix/rf-root"
mkdir -p "$rf_root/.agents/rules" "$rf_root/.claude/skills/pr-poll-review/reference"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rf_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rf_root/.claude/skills/pr-poll-review/SKILL.md"
printf '# gates\n' > "$rf_root/.claude/skills/pr-poll-review/reference/gates.md"
printf '# checks\n' > "$rf_root/.claude/skills/pr-poll-review/reference/checks.md"
rf() { rv_verdict "$1" Bash "$gh_cmd" "$gh_url" "" "$rf_root" "${2:-}"; }
expect 'neither reference read, a current skill line'      DENY  "$(rf "$fix/review-head-a.jsonl")"
check_contains 'the denial names the first missing file'   '.claude/skills/pr-poll-review/reference/gates.md' "$(cat "$rv_last")"
check_contains 'the denial carries the blob SHA'           "$(git hash-object "$rf_root/.claude/skills/pr-poll-review/reference/gates.md")" "$(cat "$rv_last")"
expect 'gates.md read, checks.md not'                      DENY  "$(rf "$fix/review-head-a.jsonl" skill-pr-poll-review-gates)"
check_contains 'the denial now names checks.md'            '.claude/skills/pr-poll-review/reference/checks.md' "$(cat "$rv_last")"
expect 'both read (state)'                                 ALLOW "$(rf "$fix/review-head-a.jsonl" 'skill-pr-poll-review-gates skill-pr-poll-review-checks')"
expect 'both receipted (second source)'                    ALLOW "$(rf "$fix/review-refs-both.jsonl")"
expect 'only gates.md receipted'                           DENY  "$(rf "$fix/review-refs-gates-only.jsonl")"
expect 'both receipted in the new line form'                ALLOW "$(rf "$fix/review-refs-new-both.jsonl")"
expect 'a compaction ends the receipts'                    DENY  "$(rf "$fix/review-refs-then-compact.jsonl")"
expect 'a reader of another name does not count'           DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url" "" "$rf_root" 'skill-pr-poll-review-gates skill-other-checks')"
expect 'the connector post owes the references too'        DENY  "$(rv_verdict "$fix/review-head-a.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url" "" "$rf_root")"
expect 'gh api post owes the references too'               DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "$gh_url" "" "$rf_root")"
expect 'a missing reference file demands nothing'          ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a transcript that cannot be read fails open'       ALLOW "$(rf "$fix/nope.jsonl")"

echo "== require-rule-read.sh: the review gate where it cannot decide =="
expect 'transcript missing: allowed'                       ALLOW "$(rv_verdict "$fix/nope.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'PR not named and gh silent: allowed with a note'   WARN  "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review --approve"}' "")"
expect 'an old and a current line for the PR'              ALLOW "$(rv_verdict "$fix/review-head-old-and-new.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'an old and a current line, the head moved on'      DENY  "$(rv_verdict "$fix/review-head-old-and-new.jsonl" Bash "$gh_cmd" "$(printf 'c%.0s' {1..40})")"

echo "== require-rule-read.sh: a review post needs the run for the head, no release word (ww3d/playbook#359) =="
rr() { rv_verdict "$fix/$1.jsonl" Bash "$gh_cmd" "${2:-$gh_url}" "${3:-}"; }
expect 'the run for the current head is enough'            ALLOW "$(rr review-head-a)"
expect 'a run before a compaction and one after it'        ALLOW "$(rr review-compact-then-run)"

echo "== require-rule-read.sh: only a real compaction cuts, and a broken pipe step fails open =="
expect 'a compaction named in a later message'             ALLOW "$(rr review-compact-text-user)"
expect 'a compaction named in a tool result'               ALLOW "$(rr review-compact-text-result)"
# A step of the transcript pipe that fails is a read error, never "no skill ran": the post is let through.
# grep fails with 2 (1 only means "no line matched"); jq is not stubbed, the hook needs it before the pipe.
for t in tail grep; do
  code=1; [ "$t" = grep ] && code=2
  st="$fix/fail-$t"; mkdir -p "$st"; printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$st/$t"; chmod +x "$st/$t"
  expect "a failing $t: fails open"                        ALLOW \
    "$(RV_PATH="$st" rv_verdict "$fix/review-head-refused.jsonl" Bash "$gh_cmd" "$gh_url")"
done
expect 'the same transcript, every step ok: refused'       DENY  "$(rr review-head-refused)"
echo "== require-rule-read.sh: the forge calls of one command share one deadline, read from the injected clock =="
# A stand-in `timeout` logs the seconds it is given and runs the command at once; RULE_GATE_NOW_EPOCH freezes the clock.
tostub="$fix/tostub"; mkdir -p "$tostub"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "$STUB_TO_LOG"; shift; exec "$@"\n' > "$tostub/timeout"
chmod +x "$tostub/timeout"
to_log="$fix/to.log"; : > "$to_log"
sid="$(next_sid)"
: > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
printf '%s' "$(tool_event "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "$sid")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$rv_root" PATH="$tostub:$ghstub:$PATH" STUB_GH_OUT="$gh_url" \
    STUB_TO_LOG="$to_log" RULE_GATE_NOW_EPOCH=1700000000 bash "$ruleread" >/dev/null 2>&1
to_first="$(sed -n 1p "$to_log")"; to_second="$(sed -n 2p "$to_log")"
if [ "$to_first" = 15 ]; then ok 'the first call gets the whole budget, counted from the injected clock' "$to_first"
else bad 'the first call gets the whole budget, counted from the injected clock' "${to_first:-none}" 15; fi
if [ "$to_second" = 15 ]; then ok 'the second call reads the same clock: no time has passed' "$to_second"
else bad 'the second call reads the same clock: no time has passed' "${to_second:-none}" 15; fi
# Without RULE_GATE_NOW_EPOCH the clock is `date +%s`: a stand-in on PATH answers with a value that rises
# two seconds per call, so the second PR gets less than the first without any time passing.
datestub="$fix/datestub"; mkdir -p "$datestub"
printf '#!/usr/bin/env bash\nif [ "$1" = "+%%s" ]; then n=$(cat "$STUB_DATE_N" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB_DATE_N"; echo $((1700000000 + 2 * n)); else exec "%s" "$@"; fi\n' "$(command -v date)" > "$datestub/date"
chmod +x "$datestub/date"
: > "$to_log"; rm -f "$fix/date.n"
sid="$(next_sid)"
: > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
printf '%s' "$(tool_event "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "$sid")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$rv_root" PATH="$datestub:$tostub:$ghstub:$PATH" STUB_GH_OUT="$gh_url" \
    STUB_TO_LOG="$to_log" STUB_DATE_N="$fix/date.n" bash "$ruleread" >/dev/null 2>&1
to_first="$(sed -n 1p "$to_log")"; to_second="$(sed -n 2p "$to_log")"
if [ "$to_first" = 13 ]; then ok 'the first call gets the budget less what the clock has run' "$to_first"
else bad 'the first call gets the budget less what the clock has run' "${to_first:-none}" 13; fi
if [ "$to_second" = 11 ]; then ok 'the second call gets what is left' "$to_second"
else bad 'the second call gets what is left' "${to_second:-none}" 11; fi

# Every escape and quote form inside ${...} (the list in tests/param-forms.txt), per mode: the post after it is
# denied, read exactly or, where the ${...} is not read, as the rest of the command.
n_forms=0
while IFS=$'\t' read -r mode form; do
  case "$mode" in bash) tool=Bash ;; ps) tool=PowerShell ;; *) continue ;; esac
  n_forms=$((n_forms + 1))
  expect "post after ${mode}: $form" DENY "$(dm "$form; gh api -X POST $rv5 -f event=APPROVE" '' "$tool")"
done < "$hooks/tests/param-forms.txt"
expect 'the escape forms are read from their list' 1 "$([ "$n_forms" -ge 30 ] && echo 1)"
expect 'a ${...} that is not read says so'                   1     "$(dm "echo \${x:-'a'}; gh api $rv5" >/dev/null; has_text 'is not read: from it on' "$(cat "$rv_last")" && echo 1)"
# Without a quote, \, backtick, $( or $' a ${...} is read exactly: a read after it stays free.
for c in 'echo ${x}' 'echo ${x:-a}' 'echo ${#a[@]}' 'echo ${x:-${y}}'; do
  expect "read after Bash: $c"                               ALLOW "$(dm "$c; gh api $rv5")"
done
expect 'read after PowerShell: echo ${env:x}'                ALLOW "$(dm "echo \${env:x}; gh api $rv5" '' PowerShell)"
expect 'read after a quoted ${...} (over-block)'             DENY  "$(dm "echo \${x:-'a'}; gh api $rv5")"

finish
