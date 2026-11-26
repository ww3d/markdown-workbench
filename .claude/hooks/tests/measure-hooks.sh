#!/usr/bin/env bash
#
# Cost per tool call and turn end of the hooks (ww3d/playbook#734): wall time, CPU time and the programs each hook
# starts, per path of decision 1 and per hook, one run after the other - never in parallel, so a loaded machine is
# not loaded further. Not part of run-tests.sh: timings are no pass/fail signal; the numbers are the evidence of the
# design round and of each build PR of #734 (before / after on the same machine). The process budget is the test
# cases/hook-budget.sh.
#
# Usage:  bash .claude/hooks/tests/measure-hooks.sh [<runs>] [<hooks folder>]
#         run it under one timeout, e.g. `timeout 900 bash .claude/hooks/tests/measure-hooks.sh 9`
#         <runs>          runs per case (default 9); the median is printed
#         <hooks folder>  the hooks to measure (default: this tree's .claude/hooks); a second checkout's folder
#                         measures another state against the same fixtures, started by that checkout's settings.json
# Env:    MEASURE_TIMEOUT  seconds per hook run (default 30, the hooks' own limit in settings.json)
#
# Each hook starts as its entry in settings.json registers it: `bash -c '<command>'`, the command read from the
# file, ${CLAUDE_PROJECT_DIR} the checkout the hooks folder belongs to.
#
# Output: one line per path and hook - wall ms and CPU ms (user + sys of the hook and its children), each the
# median, the programs started and the verdict. Then the floor: the start form with an empty file, which every
# hook pays before its first check, and the stdin reads on a small and a large payload.
#
# Programs are counted in a run of their own, with a folder of shims first on PATH: each shim logs its name and
# execs the real program. bash itself and a subshell that execs nothing (`$( builtin )`) are not counted.
set -uo pipefail

runs="${1:-9}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
hooks="$(cd "${2:-$repo/.claude/hooks}" && pwd)"
project="$(cd "$hooks/../.." && pwd)"
settings="$hooks/../settings.json"
tmo="${MEASURE_TIMEOUT:-30}"
# shellcheck source=SCRIPTDIR/run-folder.sh
. "$here/run-folder.sh"
# shellcheck source=SCRIPTDIR/hook-paths.sh
. "$here/hook-paths.sh"
open_run_folder "$repo"
work="$RUN_DIR"
trap 'rm -rf "$work"' EXIT
hp_fixtures "$work" "$project"

median() { printf '%s\n' "$@" | sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }

# Shims for the count run: every program a hook may start.
shims="$work/shims"; count_log="$work/count.log"
hp_shims "$shims" "$count_log"

timed() { # command... -> globals wall_ms cpu_ms out (stdin is the caller's)
  local t0 t1 tf="$work/time.txt"
  t0=$EPOCHREALTIME
  { TIMEFORMAT='%3U %3S'; time { out="$("$@" 2>/dev/null)"; }; } 2> "$tf"
  t1=$EPOCHREALTIME
  wall_ms=$(( (10#${t1//[.,]/} - 10#${t0//[.,]/}) / 1000 ))
  cpu_ms="$(awk '{ printf "%d", ($1 + $2) * 1000 }' "$tf")"
}
count_entry() { # entry command, payload file -> global progs ("n (a x1, b x2)")
  : > "$count_log"
  hp_argv "$1"
  timeout "$tmo" env PATH="$shims:$PATH" "${hp_cmd[@]}" < <(printf '%s' "$(<"$2")") >/dev/null 2>&1
  local n names
  n="$(wc -l < "$count_log" | tr -d ' ')"
  names="$(sort "$count_log" | uniq -c | awk '{ printf "%s%s x%s", (NR > 1 ? ", " : ""), $2, $1 }')"
  progs="$n${names:+ ($names)}"
}
verdict() { case "$1" in *'"deny"'*) echo DENY ;; *'"block"'*) echo BLOCK ;; *additionalContext*) echo CONTEXT ;; *) echo ALLOW ;; esac; }
row() { printf '%-16s %-34s %7s %7s   %-8s %s\n' "$@"; }

measure_entry() { # path name, entry command, payload file, setup function run before every run
  local w=() c=() v data; data="$(<"$3")"   # a pipe, as Claude Code hands the payload
  for _ in $(seq 1 "$runs"); do
    "$4"; hp_argv "$2"; timed "${hp_cmd[@]}" < <(printf '%s' "$data"); w+=("$wall_ms"); c+=("$cpu_ms")
  done
  v="$(verdict "$out")"
  "$4"; count_entry "$2" "$3"
  row "$1" "$(hp_entry_name "$2")" "$(median "${w[@]}")" "$(median "${c[@]}")" "$v" "$progs"
}

# The hooks' environment; the timed runs carry no `timeout` of their own (its start would be measured too): run the
# whole script under one, as the usage says. The count runs have one per run.
CLAUDE_PROJECT_DIR="$(hp_native "$project")"
export TMPDIR="$hp_gate" CLAUDE_PROJECT_DIR CLAUDE_CODE_ENTRYPOINT=cli
printf 'hooks: %s (runs %s, timeout %s s, %s)\n' "$hooks" "$runs" "$tmo" "$(date -u +%Y-%m-%dT%H%MZ)"
! hp_open_lists "$project" || echo "note: open tick lists in $project/.agent/state/ticks/open start the tick guard at each turn end"
row path hook "wall ms" "cpu ms" verdict programs
while read -r name event tool payload setup kind; do
  while IFS= read -r entry; do
    [ -n "$entry" ] && measure_entry "$name" "$entry" "$work/$payload" "$setup"
  done < <(hp_entries "$settings" "$event" "$tool" "$kind")
done < <(hp_paths)

floor() { # label, bash -c text, payload file
  local w=() c=() data; data="$(<"$3")"
  for _ in $(seq 1 "$runs"); do timed bash -c "$2" < <(printf '%s' "$data"); w+=("$wall_ms"); c+=("$cpu_ms"); done
  row floor "$1" "$(median "${w[@]}")" "$(median "${c[@]}")" "" "$(wc -c < "$3" | tr -d ' ') bytes"
}
# The start form of every entry (#734, decision 2) on an empty file: what each hook pays before its first line.
: > "$work/empty-hook.sh"
floor 'start form, empty file' "[ -f \"$work/empty-hook.sh\" ] || exit 0; [ -n \"\$BASH_VERSION\" ] || exec bash \"$work/empty-hook.sh\"; . \"$work/empty-hook.sh\"" "$work/pre-bash.json"
floor 'bash -c :' ':' "$work/pre-bash.json"
# The stdin read on a small and a large payload (a 50 KB Write): the builtin reads a pipe byte by byte.
seq 1 4000 | sed 's/^/line of text /' > "$work/big.txt"
jq -cn --rawfile c "$work/big.txt" '{session_id:"measure-734", hook_event_name:"PreToolUse", tool_name:"Write",
  tool_input:{file_path:"x", content:$c}}' > "$work/big.json"
# shellcheck disable=SC2016 # the texts run in the inner bash
for p in pre-bash.json big.json; do
  floor 'x=$(cat)' 'x=$(cat)' "$work/$p"
  floor 'read builtin' 'IFS= read -r -d "" x || :' "$work/$p"
  floor 'read_hook_payload' ". \"$here/../lib/stdin.sh\"; read_hook_payload" "$work/$p"
done
