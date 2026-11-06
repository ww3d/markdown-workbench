#!/usr/bin/env bash
#
# Run time of the command splitting in require-rule-read.sh (ww3d/playbook#537): the working tree against a git
# ref, on long commands of four kinds, each at n and 2n, so a PR can show the time grows with the length and not
# faster. Not part of run-tests.sh - timings are no pass/fail signal.
#
# Usage:  bash .claude/hooks/tests/bench-split.sh [<ref>] [<n>]
#         <ref>   the old state to compare with (default: origin/main)
#         <n>     a factor on the base sizes (default: 1); each kind runs at its size and twice that
# Output: one line per kind and size - its size in KB, the old and the new time in seconds, and each verdict.
# The hook runs with a transcript that does not exist, so it stops after the split: what is timed is the split.
set -uo pipefail

ref="${1:-origin/main}"
scale="${2:-1}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# shellcheck source=SCRIPTDIR/run-folder.sh
. "$here/run-folder.sh"
open_run_folder "$repo"
work="$RUN_DIR"
trap 'rm -rf "$work"' EXIT

# The old hook with the libraries of its own ref, the new one from the working tree.
mkdir -p "$work/old/lib" "$work/new" "$work/root/.agents/rules" "$work/root/.claude/skills/pr-poll-review" "$work/tmp"
(cd "$repo" && MSYS_NO_PATHCONV=1 git archive "$ref" .claude/hooks/require-rule-read.sh .claude/hooks/lib) \
  | tar -x -C "$work/old" || { echo "ref $ref cannot be read" >&2; exit 1; }
cp -R "$repo/.claude/hooks/require-rule-read.sh" "$repo/.claude/hooks/lib" "$work/new/"
for r in pr review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$work/root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$work/root/.claude/skills/pr-poll-review/SKILL.md"
mkdir -p "$work/tmp/claude-rule-gate"
for m in pr review evidence skill-pr-poll-review-gates skill-pr-poll-review-checks; do
  : > "$work/tmp/claude-rule-gate/bench-read-main-$m"
done

verdict() { if grep -q '"permissionDecision":"deny"' "$1"; then echo DENY; else echo ALLOW; fi; }
run() { # hook, event file -> seconds and verdict
  local t0 t1 out="$work/out"
  t0="$EPOCHREALTIME"
  TMPDIR="$work/tmp" CLAUDE_PROJECT_DIR="$work/root" timeout 120 bash "$1" < "$2" > "$out" 2>/dev/null
  t1="$EPOCHREALTIME"
  awk -v a="$t0" -v b="$t1" -v v="$(verdict "$out")" 'BEGIN { printf "%6.2f s %-5s", b - a, v }'
}
kind() { # label, unit, count
  local i cmd="" ev="$work/event.json"
  for ((i = 0; i < $3; i++)); do cmd+="$2"; done
  printf '%s' "$cmd" > "$work/cmd.txt"
  jq -cn --rawfile c "$work/cmd.txt" --arg r "$work/root" \
    '{session_id:"bench",transcript_path:"/nonexistent.jsonl",cwd:$r,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' \
    > "$ev"
  printf '%-30s %5d KB  old %s  new %s\n' "$1 x$3" $(( ${#cmd} / 1024 )) \
    "$(run "$work/old/.claude/hooks/require-rule-read.sh" "$ev")" "$(run "$work/new/require-rule-read.sh" "$ev")"
}
pair() { kind "$1" "$2" $(($3 * scale)); kind "$1" "$2" $(($3 * scale * 2)); }

pair 'reviews --jq' 'gh api repos/o/r/pulls/5/reviews --jq .[].id;' 1000
pair 'GET calls' $'gh api --method GET repos/o/r/pulls/5/reviews -f per_page=100\n' 2940
# shellcheck disable=SC2016 # the command text holds $(...) as text for the hook, never to expand
pair 'calls with $(...)' 'gh api -H "$(cat h)" repos/o/r/pulls/5/reviews; ' 2800
pair 'posts without repo' '(cd x; gh api repos/{owner}/{repo}/pulls/5/reviews -f event=APPROVE); ' 1200
