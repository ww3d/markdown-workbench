#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, the round gate of the review post
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-review-rounds.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # stand-in scripts and jq text hold $ names as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-rule-read.sh: the fourth review round, and a repeated error class, wait for the controller's note =="
# A root with the review skill, a gh stand-in that answers from files (never the network) and a transcript whose
# '/pr-poll-review' line names the PR's current head. Nothing here reads the machine's git or gh settings.
rd_root="$fix/rd-root"
mkdir -p "$rd_root/.agents/rules" "$rd_root/.claude/skills/pr-poll-review"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rd_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rd_root/.claude/skills/pr-poll-review/SKILL.md"
rd_stub="$fix/rd-stub"; mkdir -p "$rd_stub"
cat > "$rd_stub/gh" <<'STUB'
#!/usr/bin/env bash
# Answers by endpoint from the environment; a variable named ..._FAIL makes that endpoint fail like a forge error.
[ -z "${STUB_GH_LOG:-}" ] || printf '%s\n' "$*" >> "$STUB_GH_LOG"
case "$*" in
  *"/reviews"*)         [ -z "${STUB_REVIEWS_FAIL:-}" ] || exit 1; printf '%s\n' "${STUB_REVIEWS:-[]}" ;;
  *"/pulls/"*"/comments"*) [ -z "${STUB_PCOMMENTS_FAIL:-}" ] || exit 1; printf '%s\n' "${STUB_PCOMMENTS:-[]}" ;;
  *"/issues/5/comments"*) printf '%s\n' "${STUB_ICOMMENTS_5:-${STUB_ICOMMENTS:-[]}}" ;;
  *"/issues/78/comments"*) printf '%s\n' "${STUB_ICOMMENTS_78:-[]}" ;;
  *"/issues/79/comments"*) printf '%s\n' "${STUB_ICOMMENTS_79:-[]}" ;;
  *"/issues/80/comments"*) printf '%s\n' "${STUB_ICOMMENTS_80:-[]}" ;;
  *"/issues/"*"/comments"*) [ -z "${STUB_ICOMMENTS_FAIL:-}" ] || exit 1; printf '%s\n' "${STUB_ICOMMENTS:-[]}" ;;
  *"--jq .body"*)       [ -z "${STUB_BODY_FAIL:-}" ] || exit 1; printf '%s\n' "${STUB_BODY:-}" ;;
  *"--jq .head.sha"*)   printf '%s\n' "${STUB_HEAD:-}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$rd_stub/gh"
rd_head="$(printf 'a%.0s' {1..40})" # the head the transcript's line names
rd_last="$fix/rd-last.out"
rd_log="$fix/rd-gh.log"
rd_hook="$ruleread"

# The hook's verdict for a review post, with the stand-in's answers taken from the caller's environment.
rd_verdict() { # [tool_input json] [tool] -> ALLOW | WARN | DENY | ERR
  local sid out rc cmd="${1:-}"
  [ -n "$cmd" ] || cmd='{"command":"gh pr review 5 -R o/r --approve --body ok"}'
  sid="$(next_sid)"
  mkdir -p "$gate_tmp/claude-rule-gate"
  : > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
  out="$(printf '%s' "$(tool_event "$fix/review-head-a.jsonl" "${2:-Bash}" "$cmd" "$sid")" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$rd_root" PATH="${RD_PATH:+$RD_PATH:}$rd_stub:$PATH" STUB_HEAD="$rd_head" \
      STUB_GH_LOG="$rd_log" bash "$rd_hook" 2>&1)"; rc=$?
  printf '%s' "$out" > "$rd_last"
  if   has_text '"permissionDecision":"deny"' "$out"; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  elif has_text 'systemMessage' "$out" && [ "$rc" = 0 ]; then printf 'WARN'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
# A reviews answer from lines "<id>|<commit>|<state>|<body>"; a `\n` in the body is a line break.
rd_reviews() {
  printf '%s\n' "$@" | jq -Rn '[inputs | split("|") | {id: (.[0] | tonumber), commit_id: .[1], state: .[2],
    body: (.[3:] | join("|") | gsub("\\\\n"; "\n"))}]'
}
# An issue-comments answer from the comment texts.
rd_texts() { printf '%s\n' "$@" | jq -Rn '[inputs | {body: gsub("\\\\n"; "\n")}]'; }

c1=c1; c2=c2; c3=c3
three="$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c")"
two="$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b")"
tracked='Fix the gate.\n\nRefs #77'
tracked="${tracked//\\n/$'\n'}"
note4='Review-Round-Decision: #5 round 4 recut: the point set is too wide'

rd_case() { # label, expected, reviews, pr body, issue comments [, tool_input] [, tool]
  expect "$1" "$2" "$(STUB_REVIEWS="$3" STUB_BODY="$4" STUB_ICOMMENTS="$5" rd_verdict "${6:-}" "${7:-}")"
}

echo "-- the count: distinct commits with a review body"
rd_case 'one round: free'                                   ALLOW '[]' "$tracked" '[]'
rd_case 'two rounds: the third is free'                     ALLOW "$two" "$tracked" '[]'
rd_case 'three rounds, no note: the fourth is refused'      DENY  "$three" "$tracked" '[]'
check_contains 'the denial names the count'                 '3 review rounds' "$(cat "$rd_last")"
check_contains 'the denial names the line to post'          'Review-Round-Decision: #5 round 4 recut|continue: <reason>' "$(cat "$rd_last")"
check_contains 'the denial names the tracking issue'        '#77' "$(cat "$rd_last")"
rd_case 'a review without a body is no round'               ALLOW "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|APPROVED|")" "$tracked" '[]'
rd_case 'a blank body is no round'                          ALLOW "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|  ")" "$tracked" '[]'
rd_case 'two reviews on one commit are one round'           ALLOW "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c1|COMMENTED|b" "3|$c2|COMMENTED|c")" "$tracked" '[]'
rd_case 'a dismissed review still counts'                   DENY  "$(rd_reviews "1|$c1|DISMISSED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c")" "$tracked" '[]'
rd_case 'a post at a head that has a review is not a new round' ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c" "4|$rd_head|COMMENTED|d")" "$tracked" '[]'
rd_case 'the fifth round is refused as well'                DENY  \
  "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c" "4|c4|COMMENTED|d")" "$tracked" "$(rd_texts "$note4")"
check_contains 'the fifth round asks for round 5'           'round 5' "$(cat "$rd_last")"

echo "-- the note: a comment line at the tracking issue"
rd_case 'the note of round 4 frees the fourth round'        ALLOW "$three" "$tracked" "$(rd_texts "$note4")"
rd_case 'continue frees it as well'                         ALLOW "$three" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 4 continue: findings differ')"
rd_case 'the note among other lines of a comment'           ALLOW "$three" "$tracked" "$(rd_texts "Status.\\n  $note4\\nMore.")"
rd_case 'a note with Windows line ends'                     ALLOW "$three" "$tracked" "$(rd_texts "x\\r\\n${note4}\\r\\ny")"
rd_case 'the note of round 3 does not free round 4'         DENY  "$three" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 3 recut: why')"
rd_case 'the note of another PR does not count'             DENY  "$three" "$tracked" "$(rd_texts 'Review-Round-Decision: #6 round 4 recut: why')"
rd_case 'a note without a reason does not count'            DENY  "$three" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 4 recut:   ')"
rd_case 'another decision word does not count'              DENY  "$three" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 4 skip: why')"
rd_case 'the note inside a sentence is no note'             DENY  "$three" "$tracked" "$(rd_texts "see $note4")"
rd_case 'the note of the previous round frees only that'    DENY  \
  "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c" "4|c4|COMMENTED|d")" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 4 recut: why')"
rd_case 'the fifth round with its own note'                 ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b" "3|$c3|COMMENTED|c" "4|c4|COMMENTED|d")" "$tracked" \
  "$(rd_texts 'Review-Round-Decision: #5 round 4 recut: why' 'Review-Round-Decision: #5 round 5 continue: why')"
: > "$rd_log"
STUB_REVIEWS="$three" STUB_BODY='Closes ww3d/playbook#77' rd_verdict >/dev/null
check_contains 'a Closes line names the repo of the issue'  'repos/ww3d/playbook/issues/77/comments' "$(cat "$rd_log")"
: > "$rd_log"
STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict >/dev/null
check_contains 'a Refs line names an issue of the PR repo'  'repos/o/r/issues/77/comments' "$(cat "$rd_log")"
: > "$rd_log"
STUB_REVIEWS="$three" STUB_BODY='Refs #5' rd_verdict >/dev/null
check_contains 'without another anchor issue the note stands at the PR' 'issues/5/comments' "$(cat "$rd_log")"

echo "-- several tracking issues, pages and Windows line ends"
multi='Refs #77\nRefs #78'; multi="${multi//\\n/$'\n'}"
expect 'the note at the second tracking issue frees it' ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$multi" STUB_ICOMMENTS_78="$(rd_texts "$note4")" rd_verdict)"
dupes='Refs #77\nCloses #77\nRefs #78\nRefs #79'; dupes="${dupes//\\n/$'\n'}"
expect 'a repeated issue number takes no place of its own' ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$dupes" STUB_ICOMMENTS_79="$(rd_texts "$note4")" rd_verdict)"
four='Refs #77\nRefs #78\nRefs #79\nRefs #80'; four="${four//\\n/$'\n'}"
expect 'only three tracking issues are read' DENY "$(STUB_REVIEWS="$three" STUB_BODY="$four" STUB_ICOMMENTS_80="$(rd_texts "$note4")" rd_verdict)"
fenced=$'Fix.\n\n```\nCloses #999\n```\nRefs #78'
expect 'an issue named inside a code block is no anchor' ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$fenced" STUB_ICOMMENTS_78="$(rd_texts "$note4")" rd_verdict)"
selfref=$'Refs #5\nRefs #77'
expect 'the PR itself is no anchor beside another issue: a note at the PR does not count' DENY "$(STUB_REVIEWS="$three" STUB_BODY="$selfref" STUB_ICOMMENTS_5="$(rd_texts "$note4")" rd_verdict)"
check_contains 'the denial names the other issue, not the PR' 'o/r#77' "$(cat "$rd_last")"
paged="$(rd_reviews "1|$c1|COMMENTED|a" "2|$c2|COMMENTED|b")
$(rd_reviews "3|$c3|COMMENTED|c")"
expect 'the rounds are counted over two pages of reviews' DENY "$(STUB_REVIEWS="$paged" STUB_BODY="$tracked" rd_verdict)"
crlf_body="$(printf 'Fix the gate.\r\n\r\nRefs #77\r\n')"
expect 'a PR body with Windows line ends names its issue' ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$crlf_body" STUB_ICOMMENTS="$(rd_texts "$note4")" rd_verdict)"

echo "-- the same error class in the last two rounds"
fa() { printf 'issue: (blocking) x\\nFehlerart: %s\\nSuche: y' "$1"; }
rep="$(rd_reviews "1|$c1|COMMENTED|$(fa 'Pfad ohne -LiteralPath')" "2|$c2|COMMENTED|$(fa 'pfad  ohne   -literalpath')")"
rd_case 'same Fehlerart twice in a row: round 3 is refused' DENY  "$rep" "$tracked" '[]'
check_contains 'the denial names the repeated class'        'Fehlerart' "$(cat "$rd_last")"
check_contains 'the denial asks for round 3'                'Review-Round-Decision: #5 round 3 recut|continue:' "$(cat "$rd_last")"
rd_case 'the note of round 3 frees it'                      ALLOW "$rep" "$tracked" "$(rd_texts 'Review-Round-Decision: #5 round 3 continue: new head fixes it')"
rd_case 'two different Fehlerarten: free'                   ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|$(fa 'Pfad ohne -LiteralPath')" "2|$c2|COMMENTED|$(fa 'Exit-Code ungeprueft')")" "$tracked" '[]'
rd_case 'the class in round 1 only: free'                   ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|$(fa 'Pfad ohne -LiteralPath')" "2|$c2|COMMENTED|plain")" "$tracked" '[]'
rd_case 'a Fehlerart line outside an issue: is no class'    ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|nitpick: a\\nFehlerart: Pfad" "2|$c2|COMMENTED|nitpick: b\\nFehlerart: Pfad")" "$tracked" '[]'
rd_case 'a Fehlerart under a nitpick: beside an issue: is no class' ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|issue: a\\nFehlerart: Alpha\\nnitpick: b\\nFehlerart: Shared" "2|$c2|COMMENTED|issue: c\\nFehlerart: Beta\\nnitpick: d\\nFehlerart: Shared")" "$tracked" '[]'
rd_case 'a numbered issue: point and its Fehlerart line count' DENY \
  "$(rd_reviews "1|$c1|COMMENTED|1. issue: (blocking) a\\n   Fehlerart: Pfad" "2|$c2|COMMENTED|1. issue: (blocking) b\\n   Fehlerart: pfad")" "$tracked" '[]'
rd_case 'a word that only starts like a label does not end the issue: point' DENY \
  "$(rd_reviews "1|$c1|COMMENTED|issue: a\\nissue-tracker: x\\nFehlerart: Pfad" "2|$c2|COMMENTED|issue: b\\nnotes on it\\nFehlerart: Pfad")" "$tracked" '[]'
rd_case 'a bold Fehlerart label counts'                     DENY  \
  "$(rd_reviews "1|$c1|COMMENTED|issue: a\\n**Fehlerart:** Pfad" "2|$c2|COMMENTED|issue: b\\n- **Fehlerart**: pfad")" "$tracked" '[]'
inline="$(printf '%s\n' 'issue: x\nFehlerart: Pfad' | jq -Rn '[inputs | {pull_request_review_id: 1, body: gsub("\\\\n"; "\n")}]')"
inline2="$(printf '%s\n' 'issue: x\nFehlerart: PFAD' | jq -Rn '[inputs | {pull_request_review_id: 2, body: gsub("\\\\n"; "\n")}]')"
inline_other="$(printf '%s\n' 'issue: x\nFehlerart: Exit' | jq -Rn '[inputs | {pull_request_review_id: 2, body: gsub("\\\\n"; "\n")}]')"
inline_both="$(printf '%s\n%s\n' "$inline" "$inline2" | jq -s 'add')"
inline_mixed="$(printf '%s\n%s\n' "$inline" "$inline_other" | jq -s 'add')"
expect 'inline comments with the same Fehlerart: refused'    DENY  "$(STUB_REVIEWS="$two" STUB_BODY="$tracked" STUB_PCOMMENTS="$inline_both" rd_verdict)"
expect 'inline comments with different Fehlerarten: free'    ALLOW "$(STUB_REVIEWS="$two" STUB_BODY="$tracked" STUB_PCOMMENTS="$inline_mixed" rd_verdict)"
expect 'the repeat with the note of round 3'                 ALLOW "$(STUB_REVIEWS="$two" STUB_BODY="$tracked" STUB_PCOMMENTS="$inline_both" STUB_ICOMMENTS="$(rd_texts 'Review-Round-Decision: #5 round 3 recut: why')" rd_verdict)"

echo "-- every kind of review post, the approve included"
cmd_gh='{"command":"gh pr review 5 -R o/r --approve --body ok"}'
expect 'gh pr review --approve'                             DENY  "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict "$cmd_gh")"
expect 'gh pr review --comment'                             DENY  "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict '{"command":"gh pr review 5 -R o/r --comment --body x"}')"
expect 'gh api POST of an APPROVE'                          DENY  "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict '{"command":"gh api repos/o/r/pulls/5/reviews -f event=APPROVE -f body=ok"}')"
mcp_in='{"owner":"o","repo":"r","pullNumber":5,"method":"create","event":"APPROVE"}'
expect 'the connector APPROVE'                              DENY  "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict "$mcp_in" mcp__claude_ai_GitHub_MCP__pull_request_review_write)"
expect 'the connector APPROVE with the note'                ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" STUB_ICOMMENTS="$(rd_texts "$note4")" rd_verdict "$mcp_in" mcp__claude_ai_GitHub_MCP__pull_request_review_write)"
expect 'a read of the reviews owes no note'                 ALLOW "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict '{"command":"gh api repos/o/r/pulls/5/reviews"}')"

echo "-- the forge cannot answer: the post passes with a note"
expect 'the reviews cannot be read'                         WARN  "$(STUB_REVIEWS_FAIL=1 STUB_BODY="$tracked" rd_verdict)"
check_contains 'the note names the rounds'                  'review rounds' "$(cat "$rd_last")"
expect 'the PR body cannot be read'                         WARN  "$(STUB_REVIEWS="$three" STUB_BODY_FAIL=1 rd_verdict)"
expect 'the issue comments cannot be read'                  WARN  "$(STUB_REVIEWS="$three" STUB_BODY="$tracked" STUB_ICOMMENTS_FAIL=1 rd_verdict)"
expect 'the inline comments cannot be read'                 WARN  "$(STUB_REVIEWS="$two" STUB_BODY="$tracked" STUB_PCOMMENTS_FAIL=1 rd_verdict)"
expect 'the reviews are no JSON'                            WARN  "$(STUB_REVIEWS='not json' STUB_BODY="$tracked" rd_verdict)"
expect 'the inline comments are no JSON'                   WARN  "$(STUB_REVIEWS="$two" STUB_BODY="$tracked" STUB_PCOMMENTS='not json' rd_verdict)"
expect 'the PR names no tracking issue: the lock stays'      DENY  "$(STUB_REVIEWS="$three" STUB_BODY='no anchor here' rd_verdict)"
expect 'the PR names no tracking issue: its own note frees'  ALLOW "$(STUB_REVIEWS="$three" STUB_BODY='no anchor here' STUB_ICOMMENTS="$(rd_texts "$note4")" rd_verdict)"
# The clock: the first two reads (deadline, head) see the start, every later one sees the budget spent.
datejump="$fix/rd-datejump"; mkdir -p "$datejump"
printf '#!/usr/bin/env bash\nif [ "$1" = "+%%s" ]; then n=$(cat "$STUB_DATE_N" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB_DATE_N"; if [ "$n" -lt 2 ]; then echo 1700000000; else echo 1700000100; fi; else exec "%s" "$@"; fi\n' "$(command -v date)" > "$datejump/date"
chmod +x "$datejump/date"; rm -f "$fix/rd-date.n"
expect 'the time budget is spent after the head'            WARN  "$(RD_PATH="$datejump" STUB_DATE_N="$fix/rd-date.n" STUB_REVIEWS="$three" STUB_BODY="$tracked" rd_verdict)"
check_contains 'the note names the rounds when time ran out' 'review rounds' "$(cat "$rd_last")"

echo "-- mutation probes: the tests above turn red on a fault put into the gate"
rd_mut="$fix/rd-mut"; rm -rf "$rd_mut"; mkdir -p "$rd_mut"; cp -R "$hooks/." "$rd_mut/"
rd_src="$(cat "$hooks/require-rule-read.sh")"
rd_probe() { # label, gate text, its mutation, case label, mutant verdict, reviews, comments [, body [, PR comments]]
  local mutant="${rd_src/"$2"/"$3"}"
  if [ "$mutant" = "$rd_src" ]; then bad "$1" "mutation did not apply: $2" "applied"; return; fi
  printf '%s\n' "$mutant" > "$rd_mut/require-rule-read.sh"
  rd_hook="$rd_mut/require-rule-read.sh"
  expect "$1: $4" "$5" "$(STUB_REVIEWS="$6" STUB_BODY="${8:-$tracked}" STUB_ICOMMENTS="$7" STUB_ICOMMENTS_5="${9:-[]}" rd_verdict)"
  rd_hook="$ruleread"
}
# The limit of three rounds raised: the fourth round slips through, the unmutated gate refuses it (case above).
rd_probe 'limit mutated to 4' 'round_limit=3' 'round_limit=4' 'three rounds, no note' ALLOW "$three" '[]'
# The note matched for any round number: the note of round 3 frees round 4, the unmutated gate refuses it.
rd_probe 'round number ignored' '\($want)' '[0-9]+' 'the note of round 3 frees round 4' ALLOW "$three" "$(rd_texts 'Review-Round-Decision: #5 round 3 recut: why')"
# A list number before a label ignored: a numbered issue: point is no longer read; the real gate refuses the repeat.
rd_probe 'list number ignored' '(?:[0-9]+[.)]\\s*)?' '' 'a numbered issue: point' ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|1. issue: (blocking) a\\n   Fehlerart: Pfad" "2|$c2|COMMENTED|1. issue: (blocking) b\\n   Fehlerart: pfad")" '[]'
# Any word that starts like a label ends the point again: the unmutated gate keeps the Fehlerart with its issue: point.
rd_probe 'label read loosely' '\\s*(\\([^)]*\\))?[*_]*\\s*:"' '\\b[^:]*:"' 'a word that only starts like a label' ALLOW \
  "$(rd_reviews "1|$c1|COMMENTED|issue: a\\nissue-tracker: x\\nFehlerart: Pfad" "2|$c2|COMMENTED|issue: b\\nnotes on it\\nFehlerart: Pfad")" '[]'

# The own PR number no longer skipped: a note at the PR itself frees the post, the real gate refuses it.
rd_probe 'own PR number not skipped' '&& [ "$inum" = "$pull" ]; then continue; fi' '&& false; then continue; fi' 'a note at the PR beside another issue' ALLOW "$three" '[]' "$selfref" "$(rd_texts "$note4")"
# A code block read as text: an issue named inside it is taken as an anchor, the real gate ignores it.
rd_probe 'code blocks not skipped' 'if [ "$fence" = 1 ]; then continue; fi' ':' 'an issue named inside a code block' ALLOW "$three" "$(rd_texts "$note4")" "$fenced"

finish
