#!/usr/bin/env bash
# Hook suite section: guard-kill.sh, background sessions, here-docs and the own process
# Run alone: bash .claude/hooks/tests/cases/guard-kill-session.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh: a background session is denied like any other (ww3d/playbook#356, #511) =="
# An `ask` parks a `claude --bg` session as waiting (measured with Claude Code 2.1.294); the hook never asks.
bg_kill() { # label, expected, command, [reason fragment]
  local out got
  out="$(printf '%s' "$(kill_event Bash "$3")" | CLAUDE_JOB_DIR="$fix/job" bash "$guard" 2>&1)"
  if [ -z "$out" ]; then got=allow
  else got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ERR"' 2>/dev/null)"; fi
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
  if [ -n "${4:-}" ]; then check_contains "$1: reason" "$4" "$out"; fi
}
bg_kill 'background: one named PID is denied'      deny  'kill 1234'        'owner of this session'
bg_kill 'background: the reason still names it'    deny  'kill 1234'        '1234'
# The reason must not send the session into a retry loop: the question goes on to the orchestrator, whose grant lets
# the same command pass while that process runs (ww3d/playbook#516, #531).
bg_kill 'background: no retry in another form'  deny  'kill 1234'        'Do not retry it here in another form'
bg_kill 'background: the orchestrator grants it'  deny  'kill 1234'        'it goes on to the orchestrator'
# The session's own background task is not a dead end: the harness stops it without a kill command.
bg_kill 'background: its own task goes by TaskStop'  deny  'kill 1234'        "A background task this session started itself is stopped with the harness's task stop (TaskStop), not with a kill command."
bg_kill 'background: a broad ending stays denied'  deny  'pkill -f node'    'Blocked, broad ending'
bg_kill 'background: one number in a script block'  deny  '& { Stop-Process -Id 3568 }'  '3568'
bg_kill 'background: several numbers in one command' deny 'kill 1 2'                      'kill 2'
bg_kill 'background: several commands, one number each' deny 'kill 1; kill 2'            'kill 2'
bg_kill 'background: a CIM filter on one process id' deny 'Get-CimInstance Win32_Process -Filter "ProcessId=3568" | Invoke-CimMethod -MethodName Terminate' '3568'
bg_kill 'background: a target in a variable'        deny  '$p = Start-Process x -PassThru; Stop-Process -Id $p.Id' 'variable'
bg_kill 'background: a call without a verb passes' allow 'git log --oneline'
chk_kill 'foreground: one named PID is denied too' deny  Bash 'kill 1234'        'owner of this session'
out="$(printf '%s' "$(kill_event Bash 'kill 1234')" | CLAUDE_JOB_DIR="" bash "$guard" 2>&1)"
if has_text '"permissionDecision":"deny"' "$out"; then ok 'an empty CLAUDE_JOB_DIR changes nothing' deny
else bad 'an empty CLAUDE_JOB_DIR changes nothing' "$out" deny; fi

echo "== guard-kill.sh: here-doc and here-string text is data (ww3d/playbook#511) =="
chk_kill 'a quoted here-doc body'                  allow Bash "cat <<'EOF' > n.md
Stop-Process -Id 4242
kill 5
EOF"
chk_kill 'an unquoted here-doc body without a substitution' allow Bash 'cat <<EOF
built $(date) after kill 5
EOF'
chk_kill 'a substitution in an unquoted here-doc'  deny   Bash       'cat <<EOF
$(kill 5)
EOF'                                                                                                             'kill 5'
chk_kill 'a here-doc an interpreter runs'          deny   Bash       "bash <<'EOF'
kill 5
EOF"                                                                                                             'kill 5'
chk_kill 'a here-doc piped into a shell'           deny   Bash       "cat <<'EOF' | sh
kill 5
EOF"                                                                                                             'kill 5'
chk_kill 'a command after the here-doc'            deny   Bash       "cat <<'EOF'
text
EOF
kill 6"                                                                                                          'kill 6'
chk_kill 'an unterminated here-doc stays checked'  deny   Bash       "cat <<'EOF'
kill 5"                                                                                                          'kill 5'
chk_kill 'a tab-stripped here-doc'                 allow Bash       "cat <<-'EOF'
	kill 5
	EOF"
chk_kill 'a PR body from a here-doc'               allow Bash       "gh pr create --body \"\$(cat <<'EOF'
Stop-Process -Id 4242 ended the probe
EOF
)\""
chk_kill 'a substitution in a double-quoted message' allow Bash     'git commit -m "built $(date) then kill 5"'
chk_kill 'an ending inside a quoted substitution'  deny   Bash       'echo "$(kill 7)"'                           'kill 7'
chk_kill 'a literal here-string'                   allow PowerShell "\$t = @'
Stop-Process -Id 44
'@"
chk_kill 'a substitution in an expanding here-string' deny PowerShell '$t = @"
$(Stop-Process -Id 44)
"@'                                                                                                              '44'
chk_kill 'an ending after the here-string'         deny   PowerShell "\$t = @'
text
'@
Stop-Process -Id 45"                                                                                             '45'

echo "== guard-kill.sh: an ending of the session's own process passes (ww3d/playbook#511) =="
# The test shell stands in for the session's process. The probe child ends by itself; nothing here ends anything.
own_kill() { # label, expected, tool, command, [reason fragment], [root]
  local out got
  out="$(printf '%s' "$(kill_event "$3" "$4")" | GUARD_KILL_ROOT_PID="${6:-$own_root}" bash "$guard" 2>&1)"
  if [ -z "$out" ]; then got=allow
  else got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ERR"' 2>/dev/null)"; fi
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
  if [ -n "${5:-}" ]; then check_contains "$1: reason" "$5" "$out"; fi
}
own_root=$$ own_child_win=""
if [ -r "/proc/$$/winpid" ]; then read -r own_root <"/proc/$$/winpid"; fi
sleep 30 >/dev/null 2>&1 &
own_child=$!
if [ -r "/proc/$own_child/winpid" ]; then read -r own_child_win <"/proc/$own_child/winpid"; fi
true </dev/null >/dev/null 2>&1 &
own_gone=$!
wait "$own_gone"
if [ -r "/proc/$$/winpid" ] || [ -r "/proc/$$/stat" ]; then
  own_kill 'kill of an own child passes'              allow Bash       "kill $own_child"
  own_kill 'kill -9 of an own child passes'           allow Bash       "kill -9 $own_child"
  own_kill 'Stop-Process of an own child passes'      allow PowerShell "Stop-Process -Id ${own_child_win:-$own_child}"
  own_kill 'a number that no longer exists passes'    allow Bash       "kill $own_gone"
  own_kill 'the session process itself is denied'          deny   Bash       "kill $$"                     "kill $$"
  # With the probe child as root the test shell is its ancestor; Windows' System process (4) and init (1) are foreign.
  own_kill 'an ancestor of the session process is denied'  deny   Bash       "kill $$"                     "kill $$" \
    "${own_child_win:-$own_child}"
  if [ -n "$own_child_win" ]; then
    own_kill 'a foreign process is denied'                 deny   PowerShell 'Stop-Process -Id 4'          'stop-process 4'
    own_kill 'own and foreign: the reason names the foreign' deny PowerShell "Stop-Process -Id $own_child_win, 4" '4'
  else
    own_kill 'a foreign process is denied'                 deny   Bash       'kill 1'                      'kill 1'
    own_kill 'own and foreign: the reason names the foreign' deny Bash     "kill $own_child 1"           '(kill 1)'
  fi
  own_kill 'an unreadable tree passes nothing'        deny   Bash       "kill $own_child"             "kill $own_child" 999999999
  own_kill 'no walk with root none'                   deny   Bash       "kill $own_child"             "kill $own_child" none
  own_kill 'a target in a variable is still denied'        deny   Bash       'kill $p'
  own_kill 'a broad ending stays denied'              deny  Bash       'pkill -f node'
else
  printf '  skip %-52s %s\n' 'own-process walk' 'no /proc on this platform'
fi

finish
