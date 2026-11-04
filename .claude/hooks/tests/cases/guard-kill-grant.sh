#!/usr/bin/env bash
# Hook suite section: guard-kill.sh and lib/grant-kill.sh, the orchestrator's grant, fail-open and cost
# Run alone: bash .claude/hooks/tests/cases/guard-kill-grant.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh + lib/grant-kill.sh: the orchestrator's grant, once per process (ww3d/playbook#516) =="
# Real probe processes under a stand-in clone folder; each ends by itself. The folder and the clock are injected
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
  g_say='read -r w 2>/dev/null </proc/$$/winpid || w=$$; echo "$w"; sleep 170 >/dev/null 2>&1; :'
  printf '%s\n' "$g_say" >"$gclones/c2/run.sh"
  printf '%s\n' 'read -r _ < <("$1" -c "echo up; sleep 170 >/dev/null 2>&1; :")' "$g_say" >"$gclones/c3/run.sh"
  probe() { # global name, program, args...: starts the probe and sets the name to its number
    local fd n="$1"; shift
    exec {fd}< <("$@")
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
  else bad 'the denial names the start of a foreign process' "$gk_out" 'a start'; fi
  gkv 'a foreign process without a grant is denied'   deny  req1 "Stop-Process -Id $g_copy" \
    "bash .claude/hooks/lib/grant-kill.sh --pid $g_copy --start $s_copy --session req1 --repo '$grepo' --clones <clones-folder>"
  check_contains 'the denial sends the question on to the orchestrator' 'it goes on to the orchestrator' "$gk_out"
  check_contains 'the denial says to run the same command once more' 'run the same command once more' "$gk_out"
  check_not_contains 'the owner no longer runs it itself' 'runs the command itself' "$gk_out"
  check_not_contains 'without a grant no grant reason' 'No grant passes' "$gk_out"

  # The way through: grant, one pass, the second try denied.
  gr 'grant-kill grants a copy of a program under a clone' 0 "clone: " --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  check_contains 'grant-kill shows the program before it writes' "bash$g_ext" "$gr_out"
  check_contains 'grant-kill shows the parents' 'parents: ' "$gr_out"
  present_file 'the grant file is there' "$gd/grants/$g_copy-$s_copy-req1.json"
  journal_has 'the grant is a journal line' ".action == \"grant\" and .pid == \"$g_copy\" and .granter.session == \"orch\""
  gr 'a second grant does not overwrite the first' 1 'stands already' --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  gkv 'another session finds no grant of its own'    deny  req2 "Stop-Process -Id $g_copy" 'the grant is for another session'
  journal_has 'the failed check is a journal line'   ".action == \"reject\" and .session == \"req2\""
  gk_now=$((gnow + 601)) gkv 'an expired grant passes nothing' deny req1 "Stop-Process -Id $g_copy" 'its grant expired'
  present_file 'an expired grant is not used up' "$gd/grants/$g_copy-$s_copy-req1.json"
  gkv 'with the grant the ending passes once'        allow req1 "Stop-Process -Id $g_copy"
  absent_file 'the used grant left grants/' "$gd/grants/$g_copy-$s_copy-req1.json"
  journal_has 'the use is a journal line'            ".action == \"use\" and .pid == \"$g_copy\" and .requester.session == \"req1\""
  gkv 'the same command a second time is denied'     deny  req1 "Stop-Process -Id $g_copy" 'its grant was used already'
  # A grant for an earlier start of the same number is no grant for this one.
  rm -rf "$gd/used"
  gr 'grant again for the next case' 0 '' --pid "$g_copy" --start "$s_copy" --session req1 "${gca[@]}"
  mv "$gd/grants/$g_copy-$s_copy-req1.json" "$gd/grants/$g_copy-$((s_copy - 1))-req1.json"
  gkv 'a grant for another start passes nothing'     deny  req1 "Stop-Process -Id $g_copy" 'another start of this number'
  rm -rf "$gd"

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
