#!/usr/bin/env bash
# Hook suite section: guard-kill.sh and lib/grant-kill.sh, the orchestrator's grant, fail-open and cost
# Run alone: bash .claude/hooks/tests/cases/guard-kill-grant.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh + lib/grant-kill.sh: the orchestrator's grant, one ending per process (ww3d/playbook#516, #531) =="
# Real probe processes under a stand-in clone folder; each ends with the section. The folder and the clock are injected
# (GUARD_KILL_DIR, GUARD_KILL_NOW), so no case waits on the real clock; a sibling probe stands in for the asking
# session's process, which makes the probes foreign to it.
grant="$hooks/lib/grant-kill.sh"
if [ -r "/proc/$$/winpid" ] || [ -r "/proc/$$/stat" ]; then
  gd="$fix/grant" gnow=2000000000
  gclones="$fix/clones"; grepo="$gclones/asker/repo"
  mkdir -p "$grepo" "$gclones/c1/bin" "$gclones/c2" "$gclones/c3" "$fix/keep"
  win_of() { local w; if read -r w 2>/dev/null <"/proc/$1/winpid"; then printf '%s' "$w"; else printf '%s' "$1"; fi; }
  # Each probe is a bash that prints its own number once it runs - a signal, not a wait. Read from outside, the
  # Windows number of a fresh MSYS child is still the one of the fork, which ends when the program starts.
  g_bin="$(command -v bash)"; g_ext=""
  if [ -e "$g_bin.exe" ]; then g_bin="$g_bin.exe"; g_ext=.exe; fi
  cp "$g_bin" "$gclones/c1/bin/bash$g_ext"; cp "$g_bin" "$gclones/c1/bin/claude$g_ext"
  # A probe lives while the section runs and ends on a signal, never on a clock: it reads a fifo whose write end
  # only the section holds, and the read ends once the section is gone. The write end is opened write-only
  # (a read-write handle shows no end of file to the reader under MSYS), after a read-write handle let it open.
  mkfifo "$fix/hold"; exec {g_hold_rw}<>"$fix/hold"; exec {g_hold_fd}>"$fix/hold"; exec {g_hold_rw}<&-
  g_hold="read -r _ <'$fix/hold'; :" # single quotes: the path survives the double-quoted -c of the c3 probe
  g_say='read -r w 2>/dev/null </proc/$$/winpid || w=$$; echo "$w"; '"$g_hold"
  printf '%s\n' "$g_say" >"$gclones/c2/run.sh"
  printf '%s\n' 'read -r _ < <("$1" -c "echo up; '"$g_hold"'")' "$g_say" >"$gclones/c3/run.sh"
  probe() { # global name, program, args...: starts the probe and sets the name to its number
    local fd n="$1"; shift
    exec {fd}< <("$@" {g_hold_fd}>&-) # the probe must not hold the fifo itself, or it would never see it close
    read -r "${n?}" <&"$fd"
    g_fds+=("$fd")
  }
  g_fds=() g_copy="" g_tool="" g_agent="" g_root="" g_interp="" g_above=""
  probe g_copy "$gclones/c1/bin/bash$g_ext" -c "$g_say"
  probe g_tool "$g_bin" -c "$g_say"
  probe g_agent "$gclones/c1/bin/claude$g_ext" -c "$g_say"
  probe g_root "$g_bin" -c "$g_say"
  probe g_interp "$g_bin" "$gclones/c2/run.sh"
  probe g_above "$g_bin" "$gclones/c3/run.sh" "$gclones/c1/bin/claude$g_ext"
  # A probe that also names its own MSYS number, so the test can end it; folders named by session ids.
  g_say2='read -r w 2>/dev/null </proc/$$/winpid || w=$$; echo "$w $$"; '"$g_hold"
  gs="$fix/scratch"
  for d in req1 req req1x xreq1 req2; do mkdir -p "$gs/$d/bin"; cp "$g_bin" "$gs/$d/bin/bash$g_ext"; done
  cp "$g_bin" "$gs/req1/bin/claude$g_ext"; printf '%s\n' "$g_say" >"$gs/req1/run.sh"
  g_sid="" g_sidcmd="" g_sidpre="" g_sidsub="" g_sidxpre="" g_sidcwd="" g_sidoth="" g_sidagent="" g_cwd="" g_cwd_why=""
  probe g_sid "$gs/req1/bin/bash$g_ext" -c "$g_say"
  probe g_sidcmd "$g_bin" "$gs/req1/run.sh"
  probe g_sidpre "$gs/req/bin/bash$g_ext" -c "$g_say"
  probe g_sidsub "$gs/req1x/bin/bash$g_ext" -c "$g_say"
  probe g_sidxpre "$gs/xreq1/bin/bash$g_ext" -c "$g_say"
  probe g_sidoth "$gs/req2/bin/bash$g_ext" -c "$g_say"
  probe g_sidagent "$gs/req1/bin/claude$g_ext" -c "$g_say"
  # A program outside the clones, started with a relative path from inside a folder: only its working folder tells.
  g_cwd_fds=()
  cwd_probe() { # variable, folder
    printf '%s\n' "$g_say" >"$2/run.sh"
    if [ -r "/proc/$$/winpid" ]; then
      if command -v pwsh >/dev/null 2>&1; then
        printf '%s\n' '[Console]::Out.WriteLine($PID); [Console]::Out.Flush(); Wait-Process -Id '"$(win_of $$)"' -ErrorAction SilentlyContinue' >"$2/run.ps1"
        probe "$1" bash -c 'cd "$1" && exec pwsh -NoProfile -NonInteractive -File ./run.ps1' _ "$2"
        printf -v "$1" '%s' "${!1%$'\r'}"; g_cwd_fds+=("${!1}:${g_fds[-1]}")
      else
        g_cwd_why='no pwsh on this machine'
      fi
    else
      probe "$1" bash -c 'cd "$1" && exec "$2" ./run.sh' _ "$2" "$g_bin"
    fi
  }
  mkdir -p "$gclones/c4"
  cwd_probe g_cwd "$gclones/c4"
  cwd_probe g_sidcwd "$gs/req1"

  gk() { # session, command -> global gk_out: the hook's answer for a PowerShell call
    local gk_c gk_s; js "$2"; gk_c="$REPLY"; js "$1"; gk_s="$REPLY"
    gk_out="$(printf '{"session_id":%s,"hook_event_name":"PreToolUse","tool_name":"PowerShell","tool_input":{"command":%s}}\n' "$gk_s" "$gk_c" |
      CLAUDE_PROJECT_DIR="$grepo" GUARD_KILL_ROOT_PID="$g_root" GUARD_KILL_DIR="$gd" GUARD_KILL_NOW="${gk_now:-$gnow}" \
      bash "$guard" 2>&1)"
  }
  gkv() { # label, expected (allow|deny), session, command, [reason fragment]
    local got=allow
    gk "$3" "$4"
    [ -z "$gk_out" ] || got="$(jq -r '.hookSpecificOutput.permissionDecision // "ERR"' <<<"$gk_out" 2>/dev/null)"
    expect "$1" "$2" "$got"
    if [ -n "${5:-}" ]; then check_contains "$1: reason" "$5" "$gk_out"; fi
  }
  gr() { # label, expected exit, output fragment, grant-kill args... -> global gr_out
    local rc
    gr_out="$(CLAUDE_CODE_SESSION_ID="${gr_me-orch}" GUARD_KILL_DIR="$gd" GUARD_KILL_NOW="${gr_now:-$gnow}" \
      bash "$grant" "${@:4}" 2>&1)"; rc=$?
    expect "$1" "$2" "$rc"
    if [ -n "$3" ]; then check_contains "$1: says" "$3" "$gr_out"; fi
  }
  start_of() { # pid -> the start the denial's ready command names (empty when none)
    local re="--pid $1 --start ([0-9]+) "
    gk req0 "Stop-Process -Id $1"
    if [[ $gk_out =~ $re ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
  }
  clone_args() { printf '%s\n' --repo "$grepo" --clones "$gclones" --reason probe; }
  journal_has() { # label, jq condition on a journal line
    if [ -n "$(jq -c "select($2)" "$gd/journal.jsonl" 2>/dev/null)" ]; then
      ok "$1" logged; else bad "$1" missing logged; fi
  }
  mapfile -t gca < <(clone_args)

  s_copy="$(start_of "$g_copy")"
  if [ -n "$s_copy" ]; then ok 'the denial names the start of a foreign process' "$s_copy"
  else gk req0 "Stop-Process -Id $g_copy"; bad 'the denial names the start of a foreign process' "$gk_out" 'a start'; fi
  gkv 'a foreign process without a grant is denied'   deny  req1 "Stop-Process -Id $g_copy" \
    "bash .claude/hooks/lib/grant-kill.sh --pid $g_copy --start $s_copy --session req1 --repo '$grepo' --clones <clones-folder>"
  check_contains 'the denial sends the question on to the orchestrator' 'it goes on to the orchestrator' "$gk_out"
  check_contains 'the denial says to run the same command once more' 'run the same command once more' "$gk_out"
  check_not_contains 'the owner no longer runs it itself' 'runs the command itself' "$gk_out"
  check_not_contains 'without a grant no grant reason' 'No grant passes' "$gk_out"
  # A value parameter is no target, so the grant check runs and the denial names the ready command.
  gkv 'without a grant, -ErrorAction Stop is denied with the command' deny req1 "Stop-Process -Id $g_copy -ErrorAction Stop" \
    "bash .claude/hooks/lib/grant-kill.sh --pid $g_copy --start $s_copy --session req1 --repo '$grepo'"

  # The way through: a grant holds until its expiry or until its process is gone (ww3d/playbook#531).
  gr 'grant-kill grants a copy of a program under a clone' 0 "clone: " --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  check_contains 'grant-kill shows the program before it writes' "bash$g_ext" "$gr_out"
  check_contains 'grant-kill shows the parents' 'parents: ' "$gr_out"
  present_file 'the grant file is there' "$gd/grants/$g_copy-$s_copy-req1.json"
  journal_has 'the grant is a journal line' ".action == \"grant\" and .pid == \"$g_copy\" and .granter.session == \"orch\""
  gr 'a second grant does not overwrite the first' 1 'stands already' --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  gkv 'another session finds no grant of its own'    deny  req2 "Stop-Process -Id $g_copy" 'the grant is for another session'
  journal_has 'the failed check is a journal line'   ".action == \"reject\" and .session == \"req2\""
  gkv 'with the grant the ending passes'             allow req1 "Stop-Process -Id $g_copy"
  present_file 'a pass leaves the grant in grants/'  "$gd/grants/$g_copy-$s_copy-req1.json"
  journal_has 'the use is a journal line'            ".action == \"use\" and .pid == \"$g_copy\" and .requester.session == \"req1\""
  # The first pass stands for a call another hook denied: the process still runs, so the grant still holds.
  gkv 'the same grant passes a second call while the process runs' allow req1 "Stop-Process -Id $g_copy"
  g_uses="$(jq -c "select(.action == \"use\" and .pid == \"$g_copy\")" "$gd/journal.jsonl" | grep -c .)"
  expect 'every pass is a journal line' 2 "$g_uses"
  gkv 'with the grant, -ErrorAction Stop passes'     allow req1 "Stop-Process -Id $g_copy -ErrorAction Stop"
  # A target the guard cannot read keeps the call denied, yet the numbers beside it run through the grant check.
  gkv 'a word beside a granted number keeps the call denied' deny req1 "kill %1; Stop-Process -Id $g_copy" 'kill %1'
  check_not_contains 'the granted number is not denied' "stop-process $g_copy" "$gk_out"
  check_not_contains 'the granted number gets no grant command' "--pid $g_copy " "$gk_out"
  gkv 'a word beside a foreign number names its command' deny req2 "kill %1; Stop-Process -Id $g_copy" \
    "--pid $g_copy --start $s_copy --session req2"
  gk_now=$((gnow + 601)) gkv 'an expired grant passes nothing' deny req1 "Stop-Process -Id $g_copy" 'its grant expired'
  absent_file 'an expired grant left grants/'        "$gd/grants/$g_copy-$s_copy-req1.json"
  journal_has 'the expiry is a journal line'         ".action == \"expire\" and .pid == \"$g_copy\" and .why == \"expired\""
  gkv 'after the expiry the call stays denied'       deny  req1 "Stop-Process -Id $g_copy" 'its grant expired'
  check_not_contains 'no grant is used already'      'used already' "$gk_out"
  # A grant for an earlier start of the same number is no grant for this one, and its process is gone.
  rm -rf "$gd/used"
  gr 'grant again for the next case' 0 '' --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  mv "$gd/grants/$g_copy-$s_copy-req1.json" "$gd/grants/$g_copy-$((s_copy - 1))-req1.json"
  gkv 'a grant for another start passes nothing'     deny  req1 "Stop-Process -Id $g_copy" 'another start of this number'
  absent_file 'the grant of the earlier start left grants/' "$gd/grants/$g_copy-$((s_copy - 1))-req1.json"
  journal_has 'its move is a journal line'           ".action == \"expire\" and .pid == \"$g_copy\" and .why == \"gone\""
  rm -rf "$gd"

  # A grant whose process ended moves to used/ the next time guard-kill sees it.
  probe g_end "$gclones/c1/bin/bash$g_ext" -c "$g_say2"
  g_end_fd="${g_fds[-1]}"; g_end_msys="${g_end#* }"; g_end="${g_end%% *}"
  s_end="$(start_of "$g_end")"
  gr 'grant a probe that will end' 0 'clone: ' --pid "$g_end" --start "$s_end" --session req1 "${gca[@]}"
  kill "$g_end_msys"; cat <&"$g_end_fd" >/dev/null # its own child; the pipe closes once it is gone
  gkv 'the ending of a gone process passes'          allow req1 "Stop-Process -Id $g_end"
  absent_file 'the grant of a gone process left grants/' "$gd/grants/$g_end-$s_end-req1.json"
  journal_has 'the move is a journal line naming why' ".action == \"expire\" and .pid == \"$g_end\" and .why == \"gone\""
  # grant-kill moves a grant whose process is gone as well.
  mkdir -p "$gd/grants"; printf '{"expires": %s}\n' "$((gnow + 600))" >"$gd/grants/999999999-1-req1.json"
  gr 'grant-kill: a process that no longer runs' 1 'no longer runs' --pid 999999999 --start 1 --session req1 "${gca[@]}"
  absent_file 'grant-kill moves the grant of a gone process' "$gd/grants/999999999-1-req1.json"
  rm -rf "$gd"

  # Clone mode: a folder named by the asking session's full id belongs to it (ww3d/playbook#531).
  gr_sid() { # label, expected exit, fragment, pid
    local s; s="$(start_of "$4")"
    gr "$1" "$2" "$3" --pid "$4" --start "$s" --session req1 "${gca[@]}"
    rm -rf "$gd/grants"
  }
  gr_sid 'a program in the session-id folder'        0 "clone: " "$g_sid"
  check_contains 'the session-id folder is named'    "/scratch/req1" "$gr_out"
  gr_sid 'a script in the session-id folder'         0 "clone: " "$g_sidcmd"
  gr_sid 'a folder named by a prefix of the id'      1 'belongs to no clone' "$g_sidpre"
  check_contains 'the refusal names the session-id folder' 'nor to a folder named req1' "$gr_out"
  gr_sid 'a folder with the id inside a longer name' 1 'belongs to no clone' "$g_sidsub"
  gr_sid 'a folder with the id at the end of a longer name' 1 'belongs to no clone' "$g_sidxpre"
  gr_sid "a folder named by another session's id"    1 'belongs to no clone' "$g_sidoth"
  gr_sid 'an AI-agent host in the session-id folder' 1 'is an AI-agent host' "$g_sidagent"

  # Clone mode: the working folder, for a program started with a relative path (pwsh -File ./build.ps1).
  if [ -n "$g_cwd" ]; then
    gr_sid 'a process started with a relative path in a clone' 0 "clone: " "$g_cwd"
    check_contains 'its clone is named by its working folder' "/c4" "$gr_out"
    gr_sid 'a process started with a relative path in the session-id folder' 0 "clone: " "$g_sidcwd"
    check_contains 'the session-id folder is named by its working folder' "/scratch/req1" "$gr_out"
  else
    printf '  skip %-52s %s\n' 'a process started with a relative path' "$g_cwd_why"
  fi
  # Where the working folder cannot be read (the window manager of another account), the refusal says why.
  g_dwm=""
  if [ -r "/proc/$$/winpid" ] && command -v pwsh >/dev/null 2>&1; then
    g_dwm="$(pwsh -NoProfile -NonInteractive -Command '$a = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators"); if (-not $a) { (Get-Process dwm -ErrorAction SilentlyContinue | Select-Object -First 1).Id }' 2>/dev/null)"
    g_dwm="${g_dwm//[$'\r\n']/}"
  fi
  if [ -n "$g_dwm" ]; then
    gr_sid 'an unreadable working folder is refused'  1 'belongs to no clone' "$g_dwm"
    check_contains 'the refusal names why the working folder is unknown' 'opening the process failed' "$gr_out"
  else
    printf '  skip %-52s %s\n' 'an unreadable working folder' 'not Windows, no pwsh, elevated, or no dwm.exe'
  fi

  # Self-grant, both ways.
  gkv 'calling grant-kill with the own session id is denied' deny req1 \
    "bash .claude/hooks/lib/grant-kill.sh --pid 5 --start 1 --session req1 --repo x --clones y --reason z" 'never grants'
  gkv 'calling grant-kill with the session variable is denied' deny req1 \
    'bash .claude/hooks/lib/grant-kill.sh --pid 5 --start 1 --session "$CLAUDE_CODE_SESSION_ID" --repo x --clones y --reason z' 'never grants'
  gkv 'calling grant-kill for another session passes' allow req1 \
    "bash .claude/hooks/lib/grant-kill.sh --pid 5 --start 1 --session req2 --repo x --clones y --reason z"
  gkv 'a session id that only starts the same passes' allow req1 \
    "bash .claude/hooks/lib/grant-kill.sh --pid 5 --start 1 --session req10 --repo x --clones y --reason z"
  gr_me=req1 gr 'grant-kill refuses the own session' 1 'never grants an ending to itself' \
    --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  journal_has 'a refusal is a journal line' '.action == "refuse" and .requester.session == "req1"'
  gr_me='' gr 'grant-kill runs inside a session only' 1 'CLAUDE_CODE_SESSION_ID is empty' \
    --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"

  # Refusals of grant-kill.
  gr 'a process that no longer runs'          1 'no longer runs'        --pid 999999999 --start 1 --session req1 "${gca[@]}"
  gr 'a start that differs'                   1 'the number was reused' --pid "$g_copy" --start 1 --session req1 "${gca[@]}"
  s_agent="$(start_of "$g_agent")"
  gr 'an AI-agent host'                       1 'is an AI-agent host'   --pid "$g_agent" --start "$s_agent" --session req1 "${gca[@]}"
  s_above="$(start_of "$g_above")"
  gr 'a process with an AI-agent host below'  1 'AI-agent host below it' --pid "$g_above" --start "$s_above" --session req1 "${gca[@]}"
  g_self="$(win_of $$)"; s_self="$(start_of "$g_self")"
  gr "the granting session's chain"           1 "granting session's process or one of its ancestors" \
    --pid "$g_self" --start "$s_self" --session req1 "${gca[@]}"
  s_tool="$(start_of "$g_tool")"
  gr 'the installed program outside the clones' 1 'belongs to no clone' --pid "$g_tool" --start "$s_tool" --session req1 "${gca[@]}"
  gr '--clones as the root'                   1 'file-system root'      --pid "$g_copy" --start "$s_copy" --session req1 \
    --repo "$grepo" --clones / --reason probe
  gr '--clones as the home folder'            1 'holds the home folder' --pid "$g_copy" --start "$s_copy" --session req1 \
    --repo "$grepo" --clones "$HOME" --reason probe
  gr '--clones without the repo below'        1 'does not lie under --clones' --pid "$g_copy" --start "$s_copy" \
    --session req1 --repo "$fix/elsewhere" --clones "$gclones" --reason probe
  gr 'clone mode needs --clones'              1 '--clones <folder> is required' --pid "$g_copy" --start "$s_copy" \
    --session req1 --repo "$grepo" --reason probe

  # Grants in clone mode.
  s_interp="$(start_of "$g_interp")"
  gr 'an interpreter running a script of a clone' 0 "clone: " --pid "$g_interp" --start "$s_interp" --session req1 "${gca[@]}"
  check_contains 'the clone it belongs to is named' "/c2" "$gr_out"
  rm -rf "$gd"
  # A clone under a Git Bash mount that is no drive (/tmp) stands on the command line in that mount's form.
  g_mnt="$(cygpath -u "$(cygpath -m "$gclones" 2>/dev/null)" 2>/dev/null)" || g_mnt=""
  if [ -n "$g_mnt" ] && [[ $g_mnt != /?/* ]]; then
    g_mntp=""; probe g_mntp "$g_bin" "$g_mnt/c2/run.sh"
    gr 'a script named under a mount that is no drive' 0 "clone: " --pid "$g_mntp" --start "$(start_of "$g_mntp")" \
      --session req1 "${gca[@]}"
    rm -rf "$gd"
  else
    printf '  skip %-52s %s\n' 'a script named under a mount that is no drive' 'no such mount covers the test folder'
  fi

  # The away switch.
  gr '--all without the switch'               1 'only while the away switch stands' --pid "$g_tool" --start "$s_tool" \
    --session req1 --repo "$grepo" --all --keep "$fix/keep" --reason probe
  gr 'a switch over 12 hours'                 1 'at most 12 hours'      --away-on 13 --said 'bin 13 h weg'
  absent_file 'no switch after the refusal'   "$gd/away.json"
  gr 'the switch needs the words'             2 'is required'           --away-on 2
  gr 'the switch for 2 hours'                 0 'away switch on'        --away-on 2 --said 'bin 2 h weg'
  journal_has 'the switch is a journal line with the words' '.action == "away-on" and .said == "bin 2 h weg"'
  gr '--all grants the installed program'     0 'mode: all processes'   --pid "$g_tool" --start "$s_tool" --session req1 \
    --repo "$grepo" --all --keep "$fix/keep" --reason probe
  rm -f "$gd"/grants/*
  gr '--all needs --keep'                     1 'needs --keep'          --pid "$g_tool" --start "$s_tool" --session req1 \
    --repo "$grepo" --all --reason probe
  gr '--all keeps the programs under --keep'  1 'lies under --keep'     --pid "$g_tool" --start "$s_tool" --session req1 \
    --repo "$grepo" --all --keep "${g_bin%/*}" --reason probe
  gr '--all never grants an AI-agent host'    1 'is an AI-agent host'   --pid "$g_agent" --start "$s_agent" --session req1 \
    --repo "$grepo" --all --keep "$fix/keep" --reason probe
  if [ -r "/proc/$$/winpid" ]; then g_core=4; else g_core=1; fi
  gr '--all never grants the system core'     1 "part of the system's core" --pid "$g_core" --start 1 --session req1 \
    --repo "$grepo" --all --keep "$fix/keep" --reason probe
  if [ -r /proc/2/stat ] && [ ! -r "/proc/$$/winpid" ]; then
    gr '--all never grants a kernel thread'   1 "part of the system's core" --pid 2 --start 1 --session req1 \
      --repo "$grepo" --all --keep "$fix/keep" --reason probe
  fi
  gr_now=$((gnow + 7201)) gr 'an expired switch counts as off' 1 'only while the away switch stands' --pid "$g_tool" \
    --start "$s_tool" --session req1 --repo "$grepo" --all --keep "$fix/keep" --reason probe
  gr 'the switch off'                         0 'away switch off'       --away-off --said 'bin zurueck'
  absent_file 'the switch is gone'            "$gd/away.json"
  journal_has 'switching off is a journal line' '.action == "away-off" and .said == "bin zurueck"'
  # The native probe holds its working folder open, which would keep the run's folder from going: it is ended
  # here, as the test's own child, and its pipe closes once it is gone.
  for x in ${g_cwd_fds[@]+"${g_cwd_fds[@]}"}; do taskkill //PID "${x%%:*}" //F >/dev/null 2>&1 || true; cat <&"${x#*:}" >/dev/null; done
  # The section lets go of the write end of the fifo; every probe then ends, and the pipe of each closes with it.
  # Reading the pipes to their end is waiting on that signal; the limit only guards against a hang.
  exec {g_hold_fd}>&-
  timeout 120 bash -c 'for fd; do cat <&"$fd" >/dev/null; done' _ "${g_fds[@]}"; g_left=$?
  expect 'no probe of the section is left after it' 0 "$g_left"
  for fd in "${g_fds[@]}"; do exec {fd}<&-; done
else
  printf '  skip %-52s %s\n' 'grants' 'no /proc on this platform'
fi

echo "== guard-kill.sh: fail-open and cost =="
out="$(printf 'not json at all kill 5' | bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok 'junk payload: allow, rc=0' 'rc=0'; else bad 'junk payload' "rc=$rc $out" 'rc=0'; fi
# A trace file that cannot be written must not cost the verdict an exit code or a line on stderr.
errf="$fix/guard-trace.err"
out="$(printf '%s' "$(kill_event Bash 'kill 1234')" | GUARD_KILL_TRACE="$fix/no-such-dir/trace" bash "$guard" 2>"$errf")"; rc=$?
if [ "$rc" = 0 ] && [ ! -s "$errf" ] && has_text '"permissionDecision":"deny"' "$out"; then
  ok 'an unwritable GUARD_KILL_TRACE: verdict intact, rc=0, no stderr' 'rc=0'
else bad 'an unwritable GUARD_KILL_TRACE' "rc=$rc err=$(cat "$errf") out=$out" 'rc=0, no stderr, deny'; fi
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/jq"; chmod +x "$stub/jq"
out="$(printf '%s' "$(kill_event Bash 'killall node')" | PATH="$stub:$PATH" bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! has_text deny "$out"; then ok 'without jq: allow, rc=0' 'rc=0'; else bad 'without jq' "rc=$rc $out" 'rc=0'; fi
# A failing jq while building the answer must not turn into a blocking exit code.
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-cn" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
out="$(printf '%s' "$(kill_event Bash 'killall node')" | PATH="$stub:$PATH" bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok 'answer-building jq failure still exits 0' 'rc=0'; else bad 'answer-building jq failure' "rc=$rc" 'rc=0'; fi
rm -f "$stub/jq"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "jq" >> "%s"\nexec "%s" "$@"\n' "$calls" "$(command -v jq)" > "$stub/jq"
chmod +x "$stub/jq"
: > "$calls"
printf '%s' "$(kill_event Bash 'git log --oneline -5')" | PATH="$stub:$PATH" bash "$guard"
printf '%s' "$(kill_event Bash 'ls .claude/skills')" | PATH="$stub:$PATH" bash "$guard"
if [ ! -s "$calls" ]; then ok 'a call without a verb starts no jq' 'none'; else bad 'a call without a verb' "$(tr '\n' ' ' < "$calls")" 'none'; fi
rm -f "$stub/jq"

finish
