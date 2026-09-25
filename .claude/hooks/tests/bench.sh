#!/usr/bin/env bash
#
# Runtime benchmark for require-rule-read.sh and read-confirm.sh: the working
# tree against a git ref, interleaved per run so machine load hits both alike.
#
# Not part of run-tests.sh - timings are no pass/fail signal. It exists so a
# runtime claim in a PR body has a reproducible source (issue #275, #276,
# review round 1 of #289): fixed inputs, a fixed synthetic transcript, a fixed
# synthetic project, the median of N runs.
#
# Usage:  bash .claude/hooks/tests/bench.sh [<ref>] [<runs>]
#         <ref>   the old state to compare with (default: origin/main)
#         <runs>  runs per case and side (default: 7)
# Output: one line per case - old median, new median, the verdict of each
#         (ALLOW/DENY), all in ms.
set -uo pipefail

ref="${1:-origin/main}"
runs="${2:-7}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Native paths where the platform has them (Claude Code on Windows hands the
# hooks D:\... paths), POSIX paths elsewhere.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
ms() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%d", (b - a) * 1000 }'; }
median() { printf '%s\n' "$@" | sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }

mkdir -p "$work/old"
for hook in require-rule-read.sh read-confirm.sh; do
  # MSYS_NO_PATHCONV: Git Bash would otherwise rewrite "ref:path" as a path.
  (cd "$repo" && MSYS_NO_PATHCONV=1 git show "${ref}:.claude/hooks/${hook}") > "$work/old/${hook}" || exit 1
done

# ~0.9 MB transcript without a receipt, and the same with a docs receipt at
# its end (the worst case for a scan).
text="$(jq -cn --arg t "$(printf 'Arbeit %.0s' {1..60})" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}')"
tool="$(jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t",name:"Bash",input:{command:"git status --short"}}]}}')"
result="$(jq -cn --arg t "$(printf 'M file.txt\\n%.0s' {1..40})" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t",content:$t}]}}')"
block="$(for _ in $(seq 1 50); do printf '%s\n%s\n%s\n' "$text" "$tool" "$result"; done)"
for _ in $(seq 1 60); do printf '%s\n' "$block"; done > "$work/transcript.jsonl"
{ cat "$work/transcript.jsonl"
  jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"rule | .agents/rules/docs.md | abc1234 | read"}]}}'
} > "$work/receipted.jsonl"

root="$(native "$repo")"
event() { # tool, tool_input json, transcript, session
  jq -cn --arg n "$1" --argjson i "$2" --arg t "$(native "$3")" --arg s "$4" --arg c "$root" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:$n, tool_input:$i}'
}
md="$(jq -cn --arg p "${root}/docs/x.md" '{file_path:$p}')"
cases=(
  "Read (no trigger possible)|$(event Read "$md" "$work/transcript.jsonl" cold)"
  "PowerShell gh pr create|$(event PowerShell '{"command":"gh pr create --draft"}' "$work/transcript.jsonl" cold)"
  "Bash gh issue create|$(event Bash '{"command":"gh issue create"}' "$work/transcript.jsonl" cold)"
  "Write docs/x.md|$(event Write "$md" "$work/transcript.jsonl" cold)"
  "Write, receipt in transcript|$(event Write "$md" "$work/receipted.jsonl" cold)"
  "Write, receipt already found|$(event Write "$md" "$work/receipted.jsonl" warm)"
)

gate="$work/tmp/claude-rule-gate"
mkdir -p "$work/tmp"
printf '%-30s %8s %8s   %s\n' "require-rule-read.sh" "old ms" "new ms" "verdict old -> new"
for c in "${cases[@]}"; do
  name="${c%%|*}"; input="${c#*|}"
  old=(); new=(); v_old=""; v_new=""
  for _ in $(seq 1 "$runs"); do
    for side in old new; do
      rm -f "$gate"/cold-* 2>/dev/null
      hook="$work/old/require-rule-read.sh"; [ "$side" = new ] && hook="$repo/.claude/hooks/require-rule-read.sh"
      t0=$EPOCHREALTIME
      out="$(printf '%s' "$input" | TMPDIR="$work/tmp" CLAUDE_PROJECT_DIR="$root" bash "$hook")"
      t1=$EPOCHREALTIME
      v=ALLOW; case "$out" in *'"deny"'*) v=DENY ;; esac
      if [ "$side" = old ]; then old+=("$(ms "$t0" "$t1")"); v_old=$v; else new+=("$(ms "$t0" "$t1")"); v_new=$v; fi
    done
  done
  printf '%-30s %8s %8s   %s -> %s\n' "$name" "$(median "${old[@]}")" "$(median "${new[@]}")" "$v_old" "$v_new"
done

# A synthetic project the size of a real consumer (ww3d/rc-control on
# 2026-09-24: 51 docs, 87 decision logs, 4 skills), cold (empty SHA cache)
# and warm (the cache of the run before).
proj="$work/proj"
mkdir -p "$proj/docs/common" "$proj/docs/decisions" "$proj/tech/common" "$proj/.agents/rules"
printf '# P\n' > "$proj/CLAUDE.md"; printf '# A\n' > "$proj/AGENTS.md"; printf '1.0.0\n' > "$proj/.playbook-version"
for i in $(seq 1 51); do printf '# Doc %s\n\nStand: build %s\n' "$i" "$i" > "$proj/docs/doc-$i.md"; done
for i in $(seq 1 4); do printf '# c\n' > "$proj/docs/common/c$i.md"; done
for i in $(seq 1 87); do printf '# log\n' > "$proj/docs/decisions/2026-08-$(printf '%02d' $(( i % 28 + 1 )))T$(printf '%04d' "$i")-log.md"; done
printf '# o\n' > "$proj/tech/common/dotnet.md"
for i in 1 2 3 4; do mkdir -p "$proj/.claude/skills/s$i"; printf -- '---\nname: s%s\nmetadata:\n  version: "1.0.0"\n---\n' "$i" > "$proj/.claude/skills/s$i/SKILL.md"; done
cp "$repo/.agents/rules/index.json" "$proj/.agents/rules/index.json"
git -C "$proj" init -q

printf '\n%-30s %8s %8s\n' "read-confirm.sh" "old ms" "new ms"
for state in cold warm; do
  old=(); new=()
  for _ in $(seq 1 "$runs"); do
    for side in old new; do
      hook="$work/old/read-confirm.sh"; [ "$side" = new ] && hook="$repo/.claude/hooks/read-confirm.sh"
      cache="$work/rc-$side"; [ "$state" = cold ] && rm -rf "$cache"; mkdir -p "$cache"
      t0=$EPOCHREALTIME
      printf '{"session_id":"b","source":"startup"}' \
        | CLAUDE_PROJECT_DIR="$(native "$proj")" TMPDIR="$cache" CLAUDE_CONFIG_DIR="$work/cfg" bash "$hook" >/dev/null
      t1=$EPOCHREALTIME
      if [ "$side" = old ]; then old+=("$(ms "$t0" "$t1")"); else new+=("$(ms "$t0" "$t1")"); fi
    done
  done
  printf '%-30s %8s %8s\n' "project of 142 files, $state" "$(median "${old[@]}")" "$(median "${new[@]}")"
done

t0=$EPOCHREALTIME; printf '{}' | bash -c ':'; t1=$EPOCHREALTIME
printf '\nfloor: starting bash once takes %s ms here; ref %s, %s runs per side\n' "$(ms "$t0" "$t1")" "$ref" "$runs"
