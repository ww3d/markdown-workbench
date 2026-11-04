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
# Fail-closed: a `gh pr review` quoted in a heredoc body counts as a post, so a body that quotes one for a PR
# without a line blocks (a wanted false block) until the gate reads commands with a shell parser.
chk_target 'a heredoc text after the real post'           DENY '{"command":"gh pr review 5 -R o/r --approve; cat <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a body file by heredoc before the post'       DENY  '{"command":"cat > b.md <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF\ngh pr review 5 -R o/r --approve --body-file b.md"}'
chk_target 'a <<- heredoc with a tab-indented end'        DENY  '{"command":"cat <<-EOF\n\tgh pr review 6 -R o/r --approve\n\tEOF\ngh pr review 5 -R o/r --approve"}'
chk_target 'a heredoc body with an apostrophe'            DENY  '{"command":"cat <<EOF\nit'"'"'s fine\nEOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a heredoc read by bash holds a post'          DENY  '{"command":"bash <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc piped to a shell holds a post'      DENY  '{"command":"cat <<EOF | sh\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc without a closing line is kept'     DENY  '{"command":"cat <<EOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a here-string is no heredoc'                  DENY  '{"command":"cat <<<x\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'export GH_REPO inside a quoted text'          ALLOW '{"command":"echo \"export GH_REPO=ghost/x\"; gh pr review 5 --approve"}'
chk_target 'export GH_REPO in a subshell that ended'      ALLOW '{"command":"(export GH_REPO=ghost/x); gh pr review 5 --approve"}'
chk_target 'export GH_REPO in the same subshell'          DENY  '{"command":"(export GH_REPO=ghost/x; gh pr review 5 --approve)"}'
# A `#` starts a comment only behind an unescaped blank and outside `${...}`; a quote in a comment hides nothing.
chk_target 'an escaped blank before # is no comment'      DENY  '{"command":"echo \\ #; gh pr review 6 -R o/r --approve"}'
chk_target 'a # inside ${...} is no comment'              DENY  '{"command":"echo ${v:- #}; gh pr review 6 -R o/r --approve"}'
chk_target 'an apostrophe in a comment hides nothing'     DENY  '{"command":"echo hi # don'"'"'t\ngh pr review 6 -R o/r --approve\n# it'"'"'s"}'
chk_target 'a comment with an apostrophe after the post'  ALLOW '{"command":"gh pr review 5 -R o/r --approve # don'"'"'t worry"}'
chk_target 'a comment after a quoted span'                ALLOW '{"command":"echo \"x\" # ; gh pr review 6 -R o/r --approve"}'
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

finish
