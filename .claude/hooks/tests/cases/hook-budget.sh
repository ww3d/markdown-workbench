#!/usr/bin/env bash
# Hook suite section: the process budget of each path through the hooks (ww3d/playbook#734, decision 8)
# Run alone: bash .claude/hooks/tests/cases/hook-budget.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# Each path of decision 1 starts its entries from settings.json as Claude Code does (`bash -c '<command>'`, an
# args entry as it is) and stays within budgets.tsv: programs counted through shims on every platform, processes
# through a job object (Windows, count-processes.ps1) or strace (Linux); without either the line says so and nothing
# fails. No time is a condition here; measure-hooks.sh measures time.
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"
# shellcheck source=SCRIPTDIR/../hook-paths.sh
. "$here/hook-paths.sh"

hb_work="$fix/budget"; mkdir -p "$hb_work"
hp_fixtures "$hb_work" "$repo_root"
hb_settings="$repo_root/.claude/settings.json"
hb_budgets="$here/budgets.tsv"
hb_log="$hb_work/programs.log"; hp_shims "$hb_work/shims" "$hb_log"
CLAUDE_PROJECT_DIR="$(hp_native "$repo_root")"
export TMPDIR="$hp_gate" CLAUDE_PROJECT_DIR CLAUDE_CODE_ENTRYPOINT=cli

# The counter of this platform: a job object needs Git Bash and pwsh, strace a Linux.
hb_counter=none
if [ -r "/proc/$$/winpid" ] && command -v pwsh >/dev/null 2>&1; then hb_counter=job
elif command -v strace >/dev/null 2>&1 && strace -f -qq -o /dev/null true 2>/dev/null; then hb_counter=strace; fi
# What Claude Code starts on Windows: the Git launcher, which starts bash -c and a console host. Both come with every
# entry there and nowhere else, so on Linux each entry's budget is two processes less.
hb_launcher="$(hp_native /)/bin/bash.exe"; [ "$hb_counter" = job ] && [ -f "$hb_launcher" ] || hb_launcher=""
hb_win_only=2
# A shell that is no bash, as /bin/sh is on Linux (dash); Git for Windows ships dash too, its sh is bash.
hb_posix_sh=""
for s in dash /bin/sh; do
  s="$(type -P "$s" 2>/dev/null)" || continue
  # shellcheck disable=SC2016 # the shell under test expands it, not this one
  [ -n "$("$s" -c 'echo "${BASH_VERSION:-}"')" ] || { hb_posix_sh="$s"; break; }
done

hb_win_quote() { # argument -> it quoted for a Windows command line (the rules CommandLineToArgvW reads back)
  local s="$1" out='"' run=''
  # A run of backslashes doubles before a quote and at the end; a quote gets one more. No subshell: this runs
  # per character.
  while [ -n "$s" ]; do
    case "$s" in
      \\*) run+=\\ ;;
      '"'*) out+="$run$run"'\"'; run='' ;;
      *) out+="$run${s:0:1}"; run='' ;;
    esac
    s="${s:1}"
  done
  printf '%s%s%s"' "$out" "$run" "$run"
}
hb_processes() { # payload file, entry... -> one process count per entry, a line each
  local e word line f="$1"; shift
  case "$hb_counter" in
    job)
      : > "$hb_work/commands.txt"
      for e in "$@"; do
        hp_argv "$e"
        [ "${hp_cmd[0]}" != bash ] || hp_cmd[0]="$(cygpath -w "${hb_launcher:-/usr/bin/bash}")"
        line=""; for word in "${hp_cmd[@]}"; do line+="${line:+ }$(hb_win_quote "$word")"; done
        printf '%s\n' "$line" >> "$hb_work/commands.txt"
      done
      MSYS2_ARG_CONV_EXCL='*' pwsh -NoProfile -NonInteractive -File "$(cygpath -w "$here/count-processes.ps1")" \
        -CommandFile "$(cygpath -w "$hb_work/commands.txt")" -InputFile "$(cygpath -w "$f")" 2>/dev/null \
        | jq -r 'if .killed or .processes < 1 then "uncounted" else .processes end' 2>/dev/null | tr -d '\r' ;;
    strace)
      for e in "$@"; do
        hp_argv "$e"
        strace -f -qq -e trace=process -o "$hb_work/strace.log" "${hp_cmd[@]}" < "$f" >/dev/null 2>&1
        # One process, plus each fork or clone that made a process rather than a thread.
        awk '/(^|[ (])(v?fork|clone3?)\(/ && !/CLONE_THREAD/ { n++ } END { print n + 1 }' "$hb_work/strace.log"
      done ;;
  esac
}

echo "== hook paths: each stays within its budget of programs and processes (ww3d/playbook#734, decision 8) =="
declare -A hb_max_prog hb_max_proc
while IFS=$'\t' read -r p mp mq; do
  case "$p" in ''|'#'*) continue ;; esac
  hb_max_prog[$p]="$mp"; hb_max_proc[$p]="${mq%$'\r'}"
done < "$hb_budgets"
[ "$hb_counter" != none ] || echo "  processes not counted (neither a job object with pwsh nor strace here)"
hb_seen=()
while read -r name event tool payload setup kind; do
  hb_seen+=("$name")
  mapfile -t hb_entries < <(hp_entries "$hb_settings" "$event" "$tool" "$kind")
  if [ -z "${hb_max_prog[$name]+x}" ]; then bad "$name: a line in budgets.tsv" none 'a budget'; continue; fi
  progs=0; hb_names=""
  for e in "${hb_entries[@]}"; do
    "$setup"; : > "$hb_log"
    hp_argv "$e"
    out_entry="$(PATH="$hb_work/shims:$PATH" "${hp_cmd[@]}" < "$hb_work/$payload" 2>/dev/null)"; rc_entry=$?
    progs=$((progs + $(wc -l < "$hb_log")))
    hb_names+="$(sort "$hb_log" | tr '\n' ' ')"
    if [ "${hp_cmd[0]}" != bash ]; then
      # A program that fails would start nothing and pass any budget; cases/*-tool-parity.sh hold its answers.
      expect "$name: $(hp_entry_name "$e") answers" 0 "$rc_entry"
      continue
    fi
    # Sourced or started, the hook gives the same answer: the entry against the file run by a bash of its own.
    hb_file="${e##*; . \"\$\{CLAUDE_PROJECT_DIR\}/.claude/hooks/}"; hb_args="${hb_file#*\"}"; hb_file="${hb_file%%\"*}"
    "$setup"
    # shellcheck disable=SC2086 # the entry's arguments are plain words
    out_file="$(bash "$hooks/$hb_file" $hb_args < "$hb_work/$payload" 2>/dev/null)"; rc_file=$?
    expect "$name: $hb_file$hb_args answers sourced as started" "$rc_file:$out_file" "$rc_entry:$out_entry"
    # Where Claude Code starts the entry with /bin/sh (Linux), the entry hands the hook to bash: the same answer.
    if [ -n "$hb_posix_sh" ]; then
      "$setup"
      out_sh="$("$hb_posix_sh" -c "$e" < "$hb_work/$payload" 2>/dev/null)"; rc_sh=$?
      expect "$name: $hb_file$hb_args answers under $hb_posix_sh as under bash" "$rc_sh:$out_sh" "$rc_entry:$out_entry"
    fi
  done
  if [ "$event" = Stop ] && hp_open_lists "$repo_root"; then
    echo "  $name: budget not compared (open tick lists in .agent/state/ticks/open of this checkout start the tick guard)"
    continue
  fi
  if [ "$progs" -le "${hb_max_prog[$name]}" ]; then ok "$name: programs within budget" "$progs <= ${hb_max_prog[$name]} (${hb_names% })"
  else bad "$name: programs within budget" "$progs (${hb_names% })" "<= ${hb_max_prog[$name]}"; fi
  [ "$hb_counter" != none ] || continue
  "$setup"
  procs=0 counted=0
  while IFS= read -r n; do [[ $n =~ ^[0-9]+$ ]] && { procs=$((procs + n)); counted=$((counted + 1)); }; done \
    < <(hb_processes "$hb_work/$payload" "${hb_entries[@]}")
  max="${hb_max_proc[$name]}"
  # Linux counts two processes less for each shell entry (Git launcher and console host on Windows) and one less
  # for an args entry, which has the console host only.
  if [ "$hb_counter" != job ]; then
    for e in "${hb_entries[@]}"; do
      if [[ $e == $'exec\t'* ]]; then max=$((max - 1)); else max=$((max - hb_win_only)); fi
    done
  fi
  if [ "$counted" != "${#hb_entries[@]}" ]; then bad "$name: processes counted for every entry" "$counted" "${#hb_entries[@]}"
  elif [ "$procs" -le "$max" ]; then ok "$name: processes within budget ($hb_counter)" "$procs <= $max"
  else bad "$name: processes within budget ($hb_counter)" "$procs" "<= $max"; fi
done < <(hp_paths)
expect 'budgets.tsv names exactly the paths' "$(printf '%s\n' "${hb_seen[@]}" | sort | paste -sd' ')" \
  "$(printf '%s\n' "${!hb_max_prog[@]}" | sort | paste -sd' ')"

# The program the entry names finds the guards: a program that asks none would pass every budget.
printf '{"session_id":"hb","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' > "$hb_work/kill.json"
hb_kill="$(hp_entries "$hb_settings" PreToolUse Bash sync)"; hp_argv "$hb_kill"
case "$("${hp_cmd[@]}" < "$hb_work/kill.json" 2>/dev/null)" in
  *'"deny"'*) ok 'pre-bash: the entry denies a kill by name' deny ;;
  *) bad 'pre-bash: the entry denies a kill by name' 'no deny' deny ;;
esac

# Mutation: an entry that starts a second bash and reads with `cat` costs a program more than the start form.
printf '{"tool_name":"Bash"}' > "$hb_work/mut.json"
printf 'read_hook_payload\n' > "$hb_work/mut-hook.sh"
hb_mut() { : > "$hb_log"; PATH="$hb_work/shims:$PATH" bash -c "$1" < "$hb_work/mut.json" >/dev/null 2>&1; wc -l < "$hb_log" | tr -d ' '; }
hb_lib="$hooks/lib/stdin.sh"
# shellcheck disable=SC2016 # the name quotes the code it is about
expect 'mutation: $(cat) in place of the builtin read starts one program' '0 1' \
  "$(hb_mut ". '$hb_lib'; . '$hb_work/mut-hook.sh'") $(hb_mut ". '$hb_lib'; x=\$(cat)")"
if [ "$hb_counter" = job ]; then
  : > "$hb_work/empty.sh"
  hb_two="$(hb_processes "$hb_work/mut.json" "[ -f '$hb_work/empty.sh' ] || exit 0; . '$hb_work/empty.sh'" "[ -f '$hb_work/empty.sh' ] || exit 0; exec bash '$hb_work/empty.sh'" | paste -sd' ')"
  hb_one="${hb_two%% *}"; hb_exec="${hb_two##* }"
  if [[ $hb_one =~ ^[0-9]+$ && $hb_exec =~ ^[0-9]+$ ]] && [ "$hb_exec" -gt "$hb_one" ]; then ok 'mutation: exec bash costs a process more than sourcing' "$hb_one < $hb_exec"
  else bad 'mutation: exec bash costs a process more than sourcing' "$hb_two" 'sourced < exec'; fi
fi

finish
